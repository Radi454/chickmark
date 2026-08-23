# ChickMark Change Log

- 2026-08-23: The Supabase cloud mirror now has the seven panel sample/domain
  metadata columns (`sample_mode`, `scope_type`, `sample_label`,
  `sample_index`, `source_domain`, `action_domain`, `recommendation_target`)
  on all nine panel tables, matching the local v61 SQLite columns. Additive
  and nullable — no data migration, no destructive change. This must land
  before any client writes those columns, otherwise PostgREST would reject
  the whole upload batch for that table.
- 2026-08-23: Panel tables now record what each saved row represents
  (`sampleMode`, `scopeType`, `sampleLabel`, `sampleIndex`) and which side of
  the operation owns it (`sourceDomain`, `actionDomain`,
  `recommendationTarget`). All nullable; schema version 61.
- 2026-08-20: fix(pip): opening a brand-new Pip conversation no longer shows
  "Could not load the conversation. Please try again.". The history action
  answers `{conversationId: null, messages: []}` for a conversation that has
  no server row yet (by design), but the Flutter parser required a non-empty
  `conversationId` and threw a `FormatException`, which
  `AssistantProvider.load()` caught as an unknown error and surfaced as an
  error banner on every first open. `AssistantChatHistory.conversationId` is
  now nullable and parsed with a new `_optionalText` helper; nothing in the
  app read that id. Regression tests cover both an explicit null and a
  missing key.
- 2026-08-20: fix(voice): recorded voice notes now speak with the `cedar`
  voice, the same voice Pip Live uses, instead of `ash` — Pip no longer
  changes vocal identity between a voice note and a live call. Verified
  against `/v1/audio/speech` that `cedar` is accepted by `gpt-4o-mini-tts`.
  The Arabic and mixed-language TTS steering now names Egyptian Colloquial
  Arabic (Cairo) explicitly and rules out Modern Standard Arabic and other
  regional accents, including the Egyptian pronunciation of ج and ق; the
  previous "natural, clear Egyptian Arabic" wording was read as MSA.
- 2026-08-20: feat(pip): move the OpenRouter text-agent default to the paid
  tier (`openai/gpt-oss-120b`, fallback `openai/gpt-oss-20b`, both were
  `:free`) and add a separate vision-capable route
  (`google/gemma-4-31b-it`, paid) for a call whose `input` carries an image
  or video. `resolveOpenRouterTextModels` (`_shared/pip_model_routing.ts`)
  now returns `{primary, fallback, vision}`, `vision` overridable with
  `OPENROUTER_VISION_MODEL`. `createResponsesAgentProvider`
  (`telegram-hatchery-agent/agent_provider.ts`) detects visual content
  (`requestIsVisual`: any `input_image` part, or an `input_file` part whose
  filename/mime indicates an image or video) BEFORE choosing a model and
  routes to `visionModel` instead of the text primary/fallback pair; the
  vision route has its own independent, optional fallback
  (`visionFallbackModel` / `OPENROUTER_VISION_FALLBACK_MODEL`, default
  unset) and NEVER falls back to the text fallback model, since that model
  is text->text and would guarantee a second failure on image/video input
  -- with no vision fallback configured, a failed vision call throws
  `AgentProviderError` after exactly one attempt. Sticky within-turn
  fallback is now tracked per route (`stickyTextFallbackReason` /
  `stickyVisionFallbackReason`) so a text call going sticky can never force
  a later vision call onto a text model, and vice versa.
  `AgentProviderTelemetry` gained `visionRouted: boolean`. Both doors'
  `readAiConfig()` (`app-hatchery-agent/index.ts`,
  `telegram-hatchery-agent/index.ts`) wire `visionModel`/
  `visionFallbackModel` through on the OpenRouter branch only. The app door
  still hardcodes `attachment: null` for every turn, so vision routing is
  reachable only from Telegram until the app gains its own attachment
  upload path; a native Telegram video message is also not yet captured as
  an attachment at all (`TelegramMessage` has no `video` field), so today
  only an image, or a video re-sent as a generic document, reaches the
  vision route. Also added a new "Grounding guard" policy section to
  `CHICKMARK_AGENT_POLICY` (Telegram + typed Pip only, NOT
  `CHICKMARK_REALTIME_POLICY`, which stays byte-identical and out of
  scope): a value belonging to a specific flock, hatchery, farm, user,
  session, production record, metric, or other database state must come
  from a tool result or already-grounded trusted context, never invented,
  estimated, interpolated, or carried over from an example -- while
  explicitly not restricting general veterinary/husbandry reference
  knowledge or arithmetic on values the user themselves already supplied.
  `CHICKMARK_AGENT_POLICY_VERSION` bumped `1.1.0` -> `1.2.0`; the pinned
  byte-for-byte snapshot test in `agent_prompt_test.ts` was updated to
  match. New/updated tests across `pip_model_routing_test.ts`,
  `agent_provider_test.ts`, `agent_prompt_test.ts`,
  `agent_runtime_test.ts`, and `app-hatchery-agent/index_test.ts`. Full
  suites green: `telegram-hatchery-agent` (276 tests), `app-hatchery-agent`
  (83 tests), and `_shared` (9 tests, run from a directory with a
  `deno.json`). Did not touch `evals/` and did not run the model
  comparison/acceptance harnesses (real-money, deliberately out of `deno
  test`).

- 2026-08-19: test(app-hatchery-agent): add a MODEL-VS-MODEL comparison
  suite on top of the existing text-agent eval harness in
  `supabase/functions/app-hatchery-agent/evals/`, to decide which of five
  candidate paid OpenRouter models (`openai/gpt-oss-20b`,
  `openai/gpt-oss-120b`, `qwen/qwen3-30b-a3b-instruct-2507`,
  `deepseek/deepseek-v4-flash-0731`, and the current production default
  `google/gemma-4-31b-it` as baseline) is the cheapest one that still meets
  our reliability bar. New files only, reusing rather than forking the
  existing harness: `models.ts` (hand-verified pricing snapshot, dated
  2026-08-19, plus `verifyModelsAgainstOpenRouter` to re-check it live at
  runner startup and abort before spending if an id or its price has
  drifted), `comparison_scenarios.ts` (45 scenarios across 9 dimensions --
  Arabic/mixed-language understanding, tool selection, tool arguments,
  tool-result reasoning, progressive disclosure, brevity,
  hallucination/grounding, multi-turn, and degradation under load -- built
  from the real tool/prompt contracts after reading
  `agent_tool_contract.ts`, `agent_read_tools.ts`, `bmk_tools.ts`, and
  `agent_audit_tools.ts`), and `run_comparison.ts` (the runner: `--models`,
  `--repeats` for per-scenario pass-RATE plus flap detection, `--filter`,
  `--json`, and a `--max-cost` budget guard against real reported
  OpenRouter cost). `agent_client.ts` was extended, additively, to parse and
  return `/v1/responses`'s `usage` block (input/output/cached/reasoning
  tokens and real `cost`) on `Round` and `TurnResult` -- `run_evals.ts` and
  `run_probe.ts` are unaffected and still pass `deno check`/`lint`/`fmt`.
  Like the rest of `evals/`, this is on-demand and NOT part of `deno test`.
  Validated with `deno check`/`lint`/`fmt --check` (clean) and a real smoke
  run (`--models openai/gpt-oss-20b --repeats 1 --filter toolsel-no
  --max-cost 0.10`) confirming cost tracking, latency capture, the budget
  abort path, and `--json` export all work; the full five-model matrix was
  deliberately NOT run (that costs real money and is left for the user to
  run on demand). No existing runtime file touched, and no default model
  changed.
- 2026-08-19: test(app-hatchery-agent): add a text-agent model-acceptance
  harness (`supabase/functions/app-hatchery-agent/evals/`) to decide whether
  `google/gemma-4-31b-it:free` is fit to be the default text-agent model, with
  `openai/gpt-oss-20b:free` as fallback. Modeled on the house style of
  `services/pip-realtime-sideband/evals/`, but driving the REAL OpenRouter
  `/v1/responses` REST shape (not a WebSocket) with the REAL production
  artefacts imported directly — `AGENT_MODEL_TOOL_DEFINITIONS` from
  `agent_tools.ts`, `buildAgentInstructions` from `agent_prompt.ts`, and a
  request body/multi-round tool loop copied field-for-field from
  `createResponsesAgentProvider`/`runAgentTurn` in `agent_provider.ts`/
  `agent_runtime.ts`. Two entry points: `run_probe.ts` (7 fast pass/fail
  tool-calling compatibility checks) and `run_evals.ts` (an 18-scenario,
  9-dimension scored acceptance suite, runnable against any `--model` with
  `--json` output for cross-model diffing). Neither is part of `deno test` —
  both cost real money and are meant to be run on demand. New files only;
  no existing runtime file touched. Not run in this change (no API key
  available here) — verified with `deno check`/`deno lint`/`deno fmt --check`
  and dry-run CLI wiring instead.
- 2026-08-19: feat(flags): park Pip Live (Realtime voice) behind
  `FeatureFlags.realtimeEnabled` (new `lib/core/config/feature_flags.dart`,
  compile-time default off via `bool.fromEnvironment('PIP_REALTIME_ENABLED')`,
  runtime-overridable for tests) during the text-agent stabilization phase.
  `MainShell` no longer constructs or provides a `RealtimeVoiceController`
  when the flag is off — the shell's Live route guard, the push to
  `RealtimeVoiceScreen`, and the `RealtimeLiveBanner` all become unreachable
  from that one choke point — and `AssistantChatScreen` adds a matching
  explicit flag check alongside its existing nullable-controller lookup so no
  live control (`assistant-live`) can appear even if a controller were
  injected some other way. The recorded-voice mic button (`assistant-mic`)
  and all Realtime source, services, edge functions and tests are untouched —
  this is a UI-reachability change only, not a removal. Added
  `test/features/chat/realtime_parked_test.dart` asserting the flag-off
  behaviour; existing Realtime widget tests now set
  `FeatureFlags.realtimeEnabled = true` in `setUp`/reset in `tearDown` to keep
  covering the full implementation.
- 2026-08-19: fix(pip-realtime-sideband): restore public Cloud Run invoker —
  self-inflicted Pip Live outage. The 00016-577 deploy followed the README's
  documented `gcloud run deploy` line, which carried
  `--no-allow-unauthenticated`. That stripped the `allUsers`
  `roles/run.invoker` binding, so every client bind was rejected by the Cloud
  Run IAM layer ("The request was not authenticated. Empty Authorization
  header value.") BEFORE reaching the container, surfacing in the app as
  `bind: RealtimeSidebandException: Could not connect the live voice session.`
  The sideband never sees a Google IAM token: it authenticates every request
  itself (bind tokens, JWT verification, authority re-resolution), and the one
  privileged endpoint `/internal/cleanup` is separately gated by OIDC audience
  plus a service-account allowlist — so public invocability at the edge is the
  design, and the cleanup allowlist would be redundant otherwise. Restored the
  `allUsers` invoker binding; a raw upgrade against `/v1/realtime` now returns
  `101 Switching Protocols` and the IAM rejections stopped. The README's deploy
  command has been corrected to `--allow-unauthenticated` with an explicit
  do-not-harden warning and a recovery snippet, since the wrong flag was
  documented and would have repeated on the next deploy. Also noted there:
  this gcloud version rejects `--cpu-always-allocated`, the equivalent being
  `--no-cpu-throttling`. No application code changed.


- 2026-08-19: feat(iot): build, deploy and verify the `iot-gateway` device API.
  Added the IoT schema (hubs, hub secrets, device tokens, sensors, metric
  registry, month-partitioned telemetry, batches, events, commands, config
  layers, firmware tables), the `iot_claim_hub` RPC, four service-role ingestion
  RPCs, and the `iot-gateway` Edge Function deployed with `--no-verify-jwt` at
  `/functions/v1/iot-gateway`. Twelve endpoints are live and were verified end to
  end against the deployed project: provisioning, token issuance, telemetry with
  two-layer idempotency, heartbeat, command delivery and acknowledgement,
  topology, config with ETag, events, and an OTA check that reports no update.
  Added `scripts/test_iot_tenant_isolation.sh`, which replays every migration into
  a throwaway Postgres and asserts cross-tenant access is impossible; it caught
  three real defects during this work. Fixed along the way: `iot_ingest_telemetry`
  used `returning (xmax = 0)`, which is illegal on a partitioned table and failed
  on every call; `iot_ack_commands` wrote the device's `received` status straight
  into a column whose check constraint has no such value, breaking the ack
  firmware must send before rebooting; `iot_claim_hub` still referenced the
  pre-move `chickmark_private` schema, so claiming a hub was broken; the
  claim-code lockout incremented a counter and then raised, which rolled the
  increment back, so the lockout never engaged; and nothing incremented
  `iot_hub_config.version`, so a hub would never have refetched changed config.
  Added `docs/IOT_FIRMWARE_HANDOFF.md` as the forwardable integration package.
  An adversarial review of the deployed build against the contract then found ten
  more, all fixed and redeployed: re-provisioning rotated the ESP-NOW primary key
  and would have stranded every paired sensor node on a recovery; omitting the
  optional `topology_hash` wiped the stored one and put the hub in a permanent
  snapshot loop; `POST /v1/firmware/status` answered `accepted: 1` for an
  `update_id` that did not exist; OTA ignored channel, `min_from_version` and
  `rollout_percent`, so a 1% staged release would have gone to the whole fleet;
  `GET /v1/config` swallowed database errors and silently served defaults with no
  ESP-NOW key; its scope filter was string-interpolated from a client-minted
  `customer_id`; `GET /v1/commands` consumed commands despite being documented as
  a pure read; a wrong HTTP method returned `400`, which tells firmware to discard
  the payload; the device's `completed_at` was dropped on the way to storage; and
  there was no way to enqueue a command at all. Added `public.iot_enqueue_command`
  (closed command set enforced server-side) and widened telemetry partitions to
  cover the 90-day backlog window plus twelve months ahead.

- 2026-08-19: fix(pip-realtime-sideband): three fixes from an Opus production
  review of the response-usage telemetry work.
  (1) TELEMETRY NO LONGER MUTATES BUDGET STATE. `#persistResponseUsage` in
  `src/sideband.ts` used to call `InteractionTracker#interactionForResponse`,
  which MINTS a new interaction (and can evict, and consumes
  `#pendingRootInteractionId`) when the response id is unknown — a pure
  telemetry read was able to alter budget-tracking state, and could never
  actually produce the documented null `interactionId` for an unattributed
  response (it invented a synthetic `resp:<id>` instead, indistinguishable
  from a real one in the table). Added a pure
  `InteractionTracker#lookupInteractionForResponse(responseId): string | null`
  that only reads `#responseInteraction` and never mints, evicts, or touches
  pending-attribution state; `#persistResponseUsage` now uses it, so the null
  documented on `ResponseUsageInsert.interactionId` (`src/store.ts`) and in
  the `interaction_id` column comment
  (`supabase/migrations/20260819120000_pip_realtime_response_usage_interaction.sql`)
  is now real. The other call sites of `interactionForResponse`
  (`src/interaction.ts`'s own `tryConsumeToolBudget`, and the `session_not_live`
  rejection path in `src/claims.ts`) are budget/attribution paths handling a
  real event and correctly keep the minting behavior. New tests:
  `test/interaction_test.ts` ("lookupInteractionForResponse is a pure read:
  null for an unseen response, no minting" and the paired "...returns the
  same answer as interactionForResponse once attributed") and
  `test/sideband_test.ts` ("persisting usage for a response the tracker never
  saw writes a null interactionId and does not mint an interaction").
  (2) SCHEMA CONTRACT TEST HEADER CORRECTED. The header on
  `test/response_usage_schema_contract_test.ts` claimed it existed because a
  migration "was not applied before the sideband revision shipped" — but the
  test reads migration files off disk, and that migration file was on disk
  throughout the incident, so this test would have PASSED during it. Rewrote
  the header to say honestly what the test catches (code drifting ahead of
  the committed migration files) versus what it does not (a committed but
  unapplied migration — guarded instead by deploy ordering plus the fail-loud
  `response_usage.persist_failed_first`/`response_usage.all_failed` logging).
  Also gave `parseAlterTableAddColumns`'s blind spot on `alter table ... drop
  column` a real fix rather than just a caveat: added
  `parseAlterTableDropColumns`, wired into `loadMigrationColumns` so a
  chronologically later drop removes the column from the derived set (and a
  still-later re-add can reintroduce it). New tests cover the parser directly
  and a synthetic add-then-drop migration pair.
  (3) STALE DERIVATION COMMENT FIXED. `src/config.ts`'s comment on
  `PIP_REALTIME_MAX_OUTPUT_TOKENS` still justified 1536 as "~2.1x the longest
  legitimate spoken reply (488 output tokens)" — the derivation for the OLD
  1024 default. Updated it to match the real derivation already documented in
  `src/session_config.ts` (a live canary measurement of 832/865 output tokens
  for an explicitly requested full eleven-metric summary; 1536 is ~1.8x that),
  pointing at `session_config.ts` instead of duplicating it.
  No behavior change to what gets persisted for an ATTRIBUTED response, no
  change to the tool-budget enforcement path, and no assertion in any
  existing test was weakened.

- 2026-08-19: fix(pip-live): four production fixes from the diagnosed Realtime
  session — report-vs-benchmark routing, breakout answer shaping, a spoken
  output ceiling, and restored token telemetry. `propose_intake` / Voice Data
  Entry deliberately untouched.
  (1) ROUTING. A live call asked "إيه آخر تقرير break out موجود عندك؟" (the
  last breakout REPORT) and Pip answered from the published standard via
  `get_egg_breakout_benchmark`. A new voice-only `REPORT_VS_BENCHMARK` section
  in `agent_prompt.ts` separates "what the standard says" from "what was
  actually recorded", defaults ambiguous wording to the STANDARD, requires the
  decision to be made silently (never asking the user which they meant),
  routes real report requests through the audit tools, forbids answering a
  report request from a benchmark, forbids carrying `ageWeek`/`breed` forward
  from an earlier benchmark turn, records that the egg-breakout table is
  age-only and needs no breed, and leaves every non-audit question on its
  existing tool. Voice-only: `CHICKMARK_AGENT_POLICY` is byte-identical and
  its pinned snapshot is untouched. `CHICKMARK_REALTIME_POLICY_VERSION`
  2.2.0 → 2.3.0.
  (2) SHAPING. `get_egg_breakout_benchmark` returned a flat 11-metric row,
  which the mini realtime model read aloud in full (~25 seconds). It now
  mirrors `get_breed_benchmark` exactly: an optional `metrics` argument and a
  `requested`/`unavailable`/`unknownMetrics`/`context` payload, with the full
  authoritative row preserved in `context`. An unknown metric name yields an
  empty `requested` plus `unknownMetrics` and never degrades to the flat row.
  `parseRequestedMetrics`/`nullMetricKeys` were generalized over a catalogue
  rather than duplicated, so the two tools cannot drift.
  `AGENT_TOOL_CONTRACT_VERSION` 1.1.0 → 1.2.0, fingerprint re-pinned.
  (3) LENGTH. `session.max_output_tokens` had never been set — the provider
  default is unbounded ("inf"). New `PIP_REALTIME_MAX_OUTPUT_TOKENS`
  (default `1536`, range 200-4096, fails startup outside that range, never
  clamped). Sized from live canary measurement: the largest LEGITIMATE reply
  the policy permits — an explicitly requested full 11-metric summary — cost
  832 and 865 output tokens, so 1536 is ~1.8x that and cannot clip a real
  answer. Deliberately not sized to cut the 761-token incident dump, which is
  fixed at its source by (1) and (2). `turnDetection`, `vadEagerness` and
  `vadSilenceMs` are unchanged — the evidence never implicated VAD.
  (4) TELEMETRY. Migration `20260819120000` (the `interaction_id` column) had
  never been applied, while Cloud Run revision `00015-b48` was already writing
  it, so every insert returned PostgREST 400 and `#persistResponseUsage`
  swallowed all of them: zero rows and no token evidence at all. The migration
  is now applied and verified against the deployed schema. Failures are now
  loud without being fatal — the first failure in a session logs at error
  level, later ones stay quiet, and a session where every attempt failed emits
  one terminal event — while the catch still swallows unconditionally so
  telemetry can never break a live call. A new schema-drift contract test
  derives the expected column set by PARSING the migration SQL, so the code
  cannot silently get ahead of the deployed schema again.
  (5) TRANSCRIPTION. `TRANSCRIPTION_PROMPT` was 100% English hatchery
  vocabulary with no language hint, producing hallucinated English captions
  ("Hello, world.", "I'm Elly.", "In Tamil") over Egyptian Arabic audio which
  then polluted stored conversation history. The prompt is now bilingual and a
  new `PIP_REALTIME_TRANSCRIPTION_LANGUAGE` (default `ar`, the SINGULAR
  `language` field, `''` omits it as a no-code-deploy rollback) is sent for
  every transcription model except `gpt-live-transcribe`, whose
  `languages`/`delay` shape is unchanged. A recorded probe
  (`tools/probe_transcription_quality.ts`) shows the old prompt transliterated
  "hatchability" into Arabic script — which silently poisons tool arguments —
  while the new configuration keeps it in Latin script and leaves a
  pure-English utterance transcribed identically.
  Evidence lives in three recorded probes under
  `services/pip-realtime-sideband/tools/`. Nine new canaries pin the
  behaviour, two of them added after review because the first
  report-vs-benchmark canary reused the incident sentence verbatim and so
  could not tell "applied the rule" from "parroted the calibration example".
  DEPLOYED 2026-08-19 in the required order: migration first, then the edge
  functions (`telegram-hatchery-agent`, `pip-realtime-tool-broker`,
  `app-hatchery-agent`), then Cloud Run revision
  `pip-realtime-sideband-00016-577`, whose startup log reports
  `instruction_version 2.3.0` / `tool_contract_version 1.2.0` with no
  warnings. Production telemetry recovered from 0 rows to live per-response
  token rows, every one carrying `interaction_id`. Env payload is now
  31146/32768 bytes — 95% of the Cloud Run cap, which is the binding
  constraint on further policy growth. Suites: telegram-hatchery-agent 228, app-hatchery-agent 82,
  pip-realtime-sideband 252, live canaries 77 — all 0 failed.

- 2026-08-19: fix(realtime): mint Realtime sessions with `cedar` from the start.
  `pip-realtime-session/config.ts` still defaulted `PIP_REALTIME_VOICE` to
  `marin`, so the ephemeral client secret was minted with `marin` and only
  became `cedar` when the Sideband's `session.update` (which has defaulted to
  `cedar` since 2026-08-17) landed. The Edge Function default is now `cedar`,
  matching the Sideband and what `LIVING_SPEC.md` already documented. Verified
  no override exists: `PIP_REALTIME_VOICE` is set neither in the Supabase
  function secrets nor in the Cloud Run service env, and the Flutter client
  never sends a voice. `config_test.ts` now pins the default and the hardcoded
  `marin` in `integration_test/realtime_attach_probe_test.dart` became `cedar`.
  Not deployed yet. No other voice or Realtime behaviour changed.

- 2026-08-19: docs(iot): design the IoT hardware API contract and backend plan.
  Added `docs/IOT_API_CONTRACT.md` (architecture, threat model, database model,
  and the self-contained `Firmware Integration Contract v1` for the hardware
  engineer) and `docs/IOT_BACKEND_PLAN.md` (phased backend build order). Design
  only — no code, schema, or Edge Function was added, so `LIVING_SPEC.md` is
  deliberately untouched: it describes behaviour that exists, and none of this
  exists yet. Decisions recorded: ingestion lives in a new `--no-verify-jwt`
  Supabase Edge Function rather than Cloud Run; devices authenticate with a
  per-hub secret exchanged for a 24 h bearer token, never a Supabase key;
  commands ride the heartbeat response instead of MQTT/WebSocket; telemetry is
  stored raw in a monthly-partitioned table with hourly/daily rollups shaped to
  match `govee_daily_captures`; and all production-threshold evaluation stays
  server-side, mirroring how `ScopeSeverity` already works client-side.

- 2026-08-19: fix(pip): natural entity names, and a deterministic end to every
  Pip response chain. A caller said `بدر`; the flock is stored decorated as
  `بدر - 25 Oct 2025 - Avian`, `resolve_customer_flock` compared the two with
  `===` after normalization, and the miss came back with no candidate IDs — so
  the model re-called the tool, and the Realtime sideband sent an unconditional
  `response.create` after EVERY `function_call_output`, including the
  `tool_limit_reached` refusal. `tool -> reject -> response.create -> tool ->
  reject` had no bound anywhere in the service: the tool budget stopped the
  tools running but never stopped the responses being generated, so the caller
  heard Pip repeat itself and the only thing that ever ended it was the model
  losing interest. Four fixes and an audit. (1) A new `agent_name_match.ts`
  folds the Arabic spellings that differ between typists (harakat, tatweel,
  zero-width marks, أإآٱ→ا, ى/ئ→ي, ؤ→و, ة→ه, Arabic-Indic digits) and matches
  on WORD TOKENS through a ladder — exact, then leading-word prefix, then a
  contained word run — where the first tier to match wins outright and every
  match in it is reported, so `بدر` resolves the decorated name while `ابر`
  still cannot match `صابر`. (2) Every non-resolved `resolve_customer_flock`
  status now carries candidate IDs with names, including `customer_not_found`,
  which returns the customers the caller may see; a fuzzy customer match
  spanning two customers is refused rather than settled by the flock name, so
  a partial name can never select another operator's records. Tool contract
  1.1.0 → 1.2.0. (3) The sideband gained a per-interaction CONTINUATION budget
  alongside the tool budget: a `tool_limit_reached` refusal force-finalizes with
  `response.create` carrying `tool_choice: 'none'` — a response the provider
  cannot answer with a function call, so the chain provably ends — and every
  continuation after that is suppressed and logged; a call refused for liveness
  is answered but never continued; tool events are now serialised in arrival
  order, so a response carrying `propose_intake` plus another tool can no longer
  land its catalogue upgrade AFTER the other tool's `response.create`, and when
  one response emits several tool calls all their names land on the single
  follow-up telemetry row they jointly caused; and the intake catalogue upgrade
  is now confirmed by its `session.updated` ack rather than assumed from the
  send, with one bounded retry, because a provider drops a rejected
  `session.update` WHOLE and the session would otherwise stay on the core
  catalogue for the rest of the call with nothing in the logs to say so.
  (4) The text runtime stopped
  answering a
  spent tool budget with `tool_limit_exceeded` (a 502 the caller could only
  retry into the same wall): the over-limit call is answered
  `tool_limit_reached` and one final pass runs with the catalogue withdrawn, so
  the model answers from what it already gathered. The broader audit closed
  three more dead ends: `select_audit_option` could never see an option list
  produced on a live call (realtime evidence carries a NULL
  `conversation_turn_id` by design), so the lookup now searches
  `agent_realtime_sessions` too and the newer snapshot wins; that tool's
  refusals became `audit_options_required` / `audit_position_out_of_range`
  instead of one null-payload `scope_denied`, while a real scope mismatch still
  answers identically to an unknown audit; and `turn_context_required` — which
  fires on EVERY realtime `propose_intake` because the broker omits the turn
  anchor by design — now carries `retryable: false` and a bilingual message
  naming the typed chat as the route. Also applied to production: the
  `agent_realtime_response_usage` migration, which had never been recorded in
  the migration ledger, so per-response token telemetry now has a table to land
  in, and a follow-up migration adds `interaction_id` to that table so the
  number of assistant responses one user utterance produced is a `group by`
  instead of a log search — that one is NOT applied yet and must land before the
  sideband revision that writes the column, because PostgREST rejects an insert
  naming an unknown column and the telemetry write swallows its own failures by
  design. `scripts/test_pip_realtime_backfill.sh` applies only migrations dated
  BEFORE the Realtime migration in its pre-state loop; it had been applying
  later ones too, which is why it was failing on `agent_realtime_calls does not
  exist`. NOT fixed, and still open: `propose_intake` remains unreachable on
  voice — anchoring a pending action on the realtime interaction instead of the
  turn index is its own design change.

- 2026-08-19: fix(pip): close the failure modes two adversarial review passes
  found around the repetition fix — this batch is about Pip going SILENT or
  taking the instance down with it, rather than looping. Critical: the tool
  broker was called with no timeout, and `fetch` has none by default, so a
  hung broker never settled — the `function_call_output` was never sent and,
  because tool events run on a serialized chain, every later tool call on that
  session queued behind it forever while the session still reported healthy;
  calls are now abandoned after `BROKER_TIMEOUT_MS` and reported as
  `broker_timeout`, kept distinct from `broker_unreachable`. Critical: provider
  events were dispatched with `void` onto a handler that re-throws, and the
  lease heartbeat with a `.then` and no `.catch`, so ONE transient PostgREST
  5xx killed the whole Cloud Run instance and every concurrent call on it —
  both now catch, a store error on renewal is treated as a lost lease, and
  `main.ts` carries a process-level `unhandledrejection` guard. High: losing
  the provider socket cleared a readiness gate and did nothing else, leaving a
  session that looked alive while it could no longer execute a tool, persist a
  turn or drive a response; it now stops and fails the client so it starts a
  fresh generation. High: a REFUSED `response.create` produced an error event
  and nothing else, so a rejected forced final left the caller in silence at
  the exact moment they were owed the answer — every frame now carries an
  `event_id`, an already-active-response refusal is correctly ignored, a
  rejected forced final is retried once without the `tool_choice` override, and
  anything else tells the client. Medium: `active_expires_at` had been stamped
  since the beginning and read by nothing, so a live call was bounded only by
  the caller hanging up; the sweep now terminalizes it, and each hangup got its
  own timeout so one unresponsive provider call cannot stall the sweep that is
  the only thing terminalizing anything. Entity resolution: the cross-door
  "newest snapshot wins" comparison used `localeCompare`, which is ICU
  collation and demonstrably inverts on timestamps whose fractional seconds
  differ in length — it is now a plain string compare; the same lookup ignored
  `context_epoch`, so a cleared conversation could still be selected from, and
  ordered turns by `created_at` across two runtimes' clocks rather than by
  `conversation_seq`. The matcher gained the guards its first version lacked:
  a bare number can no longer resolve a flock through the entry date in its
  decorated name, the Arabic definite article matches in both directions, the
  mark and format-character strips are category-based (U+061C in a mixed
  Arabic/Latin name used to split the word in half and silently kill the
  match), and Persian/Urdu keyboard letter forms fold like their digits already
  did. A second, fold-free key now guards the tenant bypass: `هانئ` and `هاني`
  collide once hamza is folded, and "exact tier" was being read as "the same
  name", so a unique flock could pick the wrong operator. `matchedBy` reports
  both tiers so a guessed customer cannot hide behind an exact flock, and every
  roster carries `truncated` — an admin is scoped to every customer, and past
  the hundred-row read cap "I can only see the first hundred" was coming out as
  "there is no such customer". The text runtime reserves a slice of the turn
  budget for its final pass, gives each awaited operation its own
  `AbortController` (one shared one meant a slow tool aborted the request meant
  to deliver the answer), reports an overrunning tool as `tool_timeout` with a
  recovery instead of failing the turn, and keeps sending the catalogue on the
  final pass since `tool_choice: 'none'` is what forbids the call. Also:
  `select_audit_option` validates its position as an integer rather than
  relying solely on the contract layer, an ambiguous breed prefix is reported
  as `breed_ambiguous` instead of being told to the user as "no such breed",
  the interaction tracker's maps are bounded, and one write-only map was
  deleted.

- 2026-08-19: perf(pip): cut Pip Realtime static context and add token
  telemetry. Measured live against production revision `00013-gpq`, a first
  turn cost 5,909 input tokens before the user said anything — 3,166 of it the
  32 tool schemas, 2,620 the voice policy, 123 provider baseline. Four changes,
  none of which touch the policy text: the model-facing tool schemas are now a
  PROJECTION of `AGENT_TOOL_CONTRACT` (`modelFacingContract`) that drops
  `minLength`/`maxLength` — pure length bounds the broker re-enforces anyway —
  and drops the 18-key `schemaKey` enum from `get_record_provenance`, the one
  station tool that structurally cannot be called cold because it needs a
  `recordId` from a prior `query_station_records` result; the intake write-path
  tools are no longer sent at session start but attached mid-session by a
  second `session.update` the first time the model attempts `propose_intake`;
  `load_station_schema` and `list_applicable_stations` stopped shipping
  `moduleKey` (always derivable from `schemaKey`) and now flatten and
  deduplicate their alias lists; and
  `resolve_customer_flock` returns the flock roster it had already fetched when
  exactly one customer matched, removing a whole follow-up inference. Every
  `response.done` now records its provider-reported token usage into the new
  `agent_realtime_response_usage` table (PK `(session_id, response_id)`, so a
  redelivery cannot double-count), including cached vs uncached input and
  whether the response followed a tool call. `agent_realtime_usage_seconds` and
  its settlement path are untouched. Server-side validation is unchanged:
  `AGENT_TOOL_CONTRACT` still carries every rule and `executeAgentTool` still
  enforces all of them, so a value the slimmed model-facing schema would accept
  is still rejected by the broker. Deliberately NOT changed: the voice policy
  (behaviourally load-bearing), `validation`/`explicitZero` in the station
  schema projection (`NATURAL_DATA_ENTRY` instructs the model to use them, and
  a rejected value costs a whole retry inference), and the `schemaKey` enum on
  `load_station_schema`, `start_intake`, `query_station_records` and
  `compare_station_metrics`, which the `inference-language` eval proves are
  called cold.
  An independent review then closed five defects in the above before it
  shipped: tool-call attribution in the new telemetry is keyed to the
  ORIGINATING response and cleared on the next user utterance, so a barge-in
  can no longer stamp `followed_tool_call` onto an unrelated later turn and two
  tool calls in one response land on one row together instead of being split;
  the usage parser coerces every token field to a non-negative integer, so a
  float can no longer be silently rejected by the column check and lose the
  row; `response.output_item.done` handlers are serialised, so a second tool
  call in the same response can no longer send `response.create` ahead of the
  intake `session.update`; an un-acked catalogue upgrade is now retryable once
  and logs `catalogue_unconfirmed` instead of silently stranding the session on
  the core catalogue; and both the startup line and every `session_config.sent`
  now carry a `tool_definitions_sha256`, because `AGENT_TOOL_CONTRACT_VERSION`
  does NOT move for a projection-only change and a Cloud Run revision running a
  stale rendered catalogue was otherwise indistinguishable from a fresh one.
  Measured on the deployed revision: a first turn fell from 5,909 input tokens
  to 4,620 (−21.8%), raising the ceiling under the account's 40k TPM cap from
  6.8 to 8.7 inferences per minute.

- 2026-08-18: fix(pip): review-hardening of the conversation redesign — a
  fourteen-finding review pass closed: `history`/`reset` no longer create
  conversation rows (only `send` and realtime `start` do, so an abandoned
  new-conversation tap leaves nothing behind); conversation previews are
  loaded per conversation instead of through one shared window a long thread
  could starve; every stored turn (both doors) bumps the conversation's
  `updated_at` so list order and day grouping follow real activity; the
  20-per-5-minutes send limit counts across all of a caller's conversations
  rather than per conversation; idempotency-replay lookups are scoped to the
  conversation; visible history orders by `conversation_seq` (immune to
  cross-runtime clock skew); realtime context injection became a READY
  precondition bounded by a 500 ms timeout and its query now excludes
  non-chat rows; the live-call error banner, retry, and clear-conversation
  controls are conversation-scoped (retry can no longer rebind a call to the
  wrong thread, and clear is disabled during that conversation's own live
  call); conversation titles, previews, live captions, and the chat header
  bypass the Arabic UI phrasebook so user text is never mistranslated; and a
  fresh conversation's header derives its title from the first message
  immediately.

- 2026-08-18: feat(pip): conversation-centric redesign — the Pip tab now roots
  at a day-grouped conversations list (Today/Yesterday/Earlier; title +
  last-message preview + time, FAB to start a new one) instead of a single
  chat screen; each conversation opens as its own persistent thread with its
  own history, and Live is now a mode reachable from inside a conversation
  rather than a separate destination. Server: `app-hatchery-agent`'s
  `send`/`history`/`reset` and `pip-realtime-session`'s `start` all accept an
  optional `conversationId` (`'app'` legacy or `'app:<uuid v4>'`), keying
  additional `agent_conversations` rows under the caller's existing app
  staff-link; a new `conversations` action lists them, and titles are derived
  server-side from each conversation's first message
  (`agent_conversations.title`, schema v60, migration
  `20260818090000_pip_conversation_titles.sql`). `history` turns now carry
  `source` (`'text'`/`'voice'`) so a realtime-call transcript renders with a
  mic glyph in the typed thread; opening a conversation's Live call now
  injects that conversation's recent finalized turns (up to 12, 600 chars/turn,
  4000 total) into the Realtime session on connect so a caller can pick up a
  typed thread by voice or vice versa. The Live call screen itself was
  redesigned: a minimal header (minimize chevron, "Pip", subtle state label),
  a refined breathing orb with glow/error tint, a collapsed-by-default
  transcript strip (latest turn per speaker, tap or toggle to expand), and
  three circular controls (mute, end call, transcript toggle) with
  Semantics/Tooltip labels; all previous widget keys were kept and one new key
  (`pip-live-transcript-toggle`) was added. New Arabic l10n entries cover every
  new string.
- 2026-08-18: fix(pip-live): answer-scope discipline after tool results — realtime policy 2.2.0 (voice-only "Tool results:" section + calibration examples + no "ثانية أشوف" filler for single lookups), get_breed_benchmark optional metrics arg returning {requested, context} (tool contract 1.1.0), and five new production-path canaries (single metric, two metrics, full summary, missing metric, filler). Root cause: post-tool synthesis existed but flat multi-metric tool payloads plus no answer-scope rule made the mini realtime model read every metric aloud. Post-review follow-up: the shaped path now also names null requested metrics in `unavailable`, a `metrics` arg with only unrecognized tokens returns `requested:[]` + `unknownMetrics` instead of silently falling back to the full row, a `shaped-null-metric` canary exercises the shaped payload directly, and the README/spec now document that edge functions must deploy before the sideband whenever the tool contract changes.
- 2026-08-18 (Pip Live production-path debug, Harness 2.1.0): the Harness v2
  deploy was verified end-to-end after the phone still behaved like the old
  agent. Evidence chain: Cloud Run revision 00009 held 100% traffic with the
  exact rendered 2.0.1 instructions (env SHA matched the local render), real
  sessions reached `ready.announced` (i.e. `session.updated` acked, no
  provider errors), and the failing screenshot turns were found in
  `agent_conversation_turns` on that same revision — so the instructions WERE
  applied and the failure was behavioral. Root cause of the eval gap: the
  47-case suite (`run_evals.ts`) talks to the model in TEXT modality, and
  gpt-realtime-2.1-mini follows the brevity/greeting rules in text mode but
  not in audio mode. Fixes: (1) new production-path canary suite
  (`evals/run_canaries.ts`) that sends the Sideband's exact `session.update`
  payload (audio output, reasoning effort, semantic VAD) and asserts on the
  audio transcript — it reproduced every phone failure; (2) voice policy
  bumped to 2.1.0: hard length rule (one short sentence, one question mark),
  explicit greeting protocol, single-question clarification (no restating, no
  option enumeration), banned assistant-service phrases, and literal
  calibration examples — the examples, not more rules, are what made audio
  mode comply (canaries went 24/24 then 23/24; before: systematic failures);
  (3) session fingerprinting in the Sideband: `session_config.sent` /
  `session_config.acked` log seq, revision, harness version, instructions
  SHA-256 + length, model, tool count, turn detection, eagerness, and an
  `instructions_match` verdict computed from the instructions the provider
  echoes back — every future session self-proves its harness identity;
  (4) deployed as revision 00011 (100% traffic, env version 2.1.0, SHA
  verified against the local render); (5) sideband README deploy recipe fixed
  (it named nonexistent secrets: real ones are `openai-api-key:1`,
  `supabase-service-role-key:1`, `pip-realtime-broker-secret:1`). All
  regression suites green: sideband 166, telegram-hatchery-agent 146,
  pip-realtime-session 59, app-hatchery-agent 50, pip-realtime-tool-broker 25.

- 2026-08-18 (Harness v2, runtime + evals): completed the realtime harness
  work. (1) Turn detection: a live probe
  (`services/pip-realtime-sideband/tools/probe_turn_detection.ts`) confirmed
  `semantic_vad` with `eagerness: low` is accepted by gpt-realtime-2.1-mini,
  so the sideband default moved from `server_vad` (500ms silence cutoff —
  the cause of Pip jumping in on short natural pauses) to `semantic_vad`
  low-eagerness, with new envs `PIP_REALTIME_TURN_DETECTION`,
  `PIP_REALTIME_VAD_EAGERNESS`, `PIP_REALTIME_VAD_SILENCE_MS` (800ms when
  server_vad is chosen) and a one-shot runtime fallback: if the provider
  rejects `turn_detection` before the config is acked, the sideband resends
  once with `server_vad` (logged `sideband.vad_fallback`). (2) Voice policy
  bumped to `2.0.1`: the no-narration line now explicitly forbids describing
  steps/tools, allowing at most a brief "ثانية أشوف". (3) New on-demand
  conversation-behavior eval suite
  (`services/pip-realtime-sideband/evals/`): 14 scripted Egyptian-Arabic
  conversations run against the real model over the Realtime WebSocket in
  text mode with stubbed tools, asserting word budgets, progressive
  disclosure, benchmark discipline, missing-data honesty, inference hedging,
  no stock phrases, and ask-before-acting. Final runs: 45–47 of 47
  assertions pass; the remaining failures are run-to-run wording variance, with no
  reproducible core-behavior failure. Sideband redeployed with the v2.0.1
  instructions and semantic VAD.

- 2026-08-18: refactored the ChickMark agent prompt
  (`supabase/functions/telegram-hatchery-agent/agent_prompt.ts`) into
  composable named sections (`AGENT_IDENTITY`, `CONVERSATION_TEXT_CHANNEL`,
  `EVIDENCE_AND_SCOPE`, `NATURAL_DATA_ENTRY`, `BENCHMARK_DISCIPLINE`,
  `TOOL_DISCIPLINE`) and added a voice-specific "Harness v2" realtime policy,
  `CHICKMARK_REALTIME_POLICY` (version `2.0.0`). `CHICKMARK_AGENT_POLICY`
  (version `1.1.0`, Telegram + typed Pip) is recomposed from the same
  sections and is pinned byte-for-byte identical to its pre-refactor value
  by a new snapshot test in `agent_prompt_test.ts` — Telegram and typed Pip
  behavior does not change. The realtime policy replaces the superseded
  `REALTIME_VOICE_ADDENDUM` in
  `services/pip-realtime-sideband/tools/render_agent_instructions.ts` (which
  now renders `CHICKMARK_REALTIME_POLICY` directly) with a full "Voice
  conversation" section: Egyptian colloquial Arabic on a live call, answer
  sizing matched to the question, no narrated tool lookups, and possibility-
  vs-fact framing for interpretation. It keeps the shared security lines
  (never expose internals, untrusted-data rule, no internal
  planning/narration) and drops the Telegram plain-text rule and the topic
  limiter so casual conversation is allowed on voice, and drops the
  customer/flock/station identifying-context line from `EVIDENCE_AND_SCOPE`
  (voice states that context only when ambiguous or asked instead).
  `services/pip-realtime-sideband/test/instruction_parity_test.ts` now
  checks for the voice section and the excluded Telegram/topic lines instead
  of the old addendum. No VAD config, sideband runtime behavior, or Flutter
  code changed.

- 2026-08-17 (after the bind fix, first working calls): two follow-ups from
  live use. (1) Every caption rendered twice — the terminal
  `.done`/`.completed` transcript frame carries the FULL text and the client
  appended it onto the line already accumulated from `.delta` frames; the
  final frame now REPLACES the open line (controller + screen tests updated
  to the real wire shape). Needs an app rebuild to take effect. (2) Pip
  Live's voice switched from `marin` to `cedar` (warm male), and the rendered
  Live instructions now append a voice-only delivery addendum after the
  shared typed-agent policy — warm tone, Egyptian colloquial Arabic when the
  user speaks Arabic, short spoken replies — versioned `1.1.0+voice.1` and
  pinned by the updated instruction-parity test. Sideband revision 00008.

- 2026-08-17 (fourth fix in the attach chain): every Pip Live call died at
  bind with 4400 `bind_frame_required` even though the client's first frame
  WAS the bind frame. Cloud Run logs showed the giveaway sequence
  `client.closed bind_frame_required` → `bind.succeeded` on the same
  connection: the server handled frames fire-and-forget, so the health frame
  the client sends right behind the bind was inspected while the bind was
  still awaiting the database, failed the "first frame must be bind" check,
  and killed the socket — after which the in-flight bind completed on the
  corpse, claimed the lease, and leaked it until `fence_lost`. The user then
  retried into the start-rate limit ("Too many voice sessions were
  started"). Fix: inbound frames are now serialized per connection (a promise
  queue, so the health frame waits for the bind to settle), and `#bind`
  aborts at its await checkpoints when the connection has already closed,
  releasing a just-claimed lease instead of leaking it. Both pinned by new
  server tests; sideband revision deployed.

- 2026-08-17 (third fix in the attach chain): with the socket finally
  attached, the provider rejected the whole `session.update` with
  `invalid_value` — `transcription.languages` and `transcription.delay` are
  `gpt-live-transcribe`-only parameters and the new default
  `gpt-4o-mini-transcribe` refuses them, silently leaving the session with no
  tools or instructions. Both are now sent only for `gpt-live-transcribe`
  (payload acked live via the macOS probe), `sideband.provider_error` logs
  now include the provider's `param` and message, and the Pip Live screen
  shows the failing stage + exception under the error status (the diagnostic
  line the chat banner used to have) plus the specific error message instead
  of always the generic one. Sideband revision 00006; app rebuilt.

- 2026-08-17 (later): Second attach fix, found by the new forensic logging on
  the first real phone call: the provider rejects even a correctly-headered
  standard API key on the call-attach WebSocket (404 `call_id_not_found` on a
  LIVE call — its own docs notwithstanding) and accepts only the ephemeral
  client secret that minted the call. Proven both ways with a real WebRTC
  call from the macOS integration harness
  (`integration_test/realtime_attach_probe_test.dart`), including a
  `session.update` → `session.updated` ack over the ephemeral attach. The
  provisioner now persists the secret on the service-role-only call row, the
  sideband uses it as the attach bearer (standard key only as legacy
  fallback), and the secret TTL rose from 30s to the full 60s setup window.
  Deployed as `pip-realtime-session` v7 and a new sideband revision.

- 2026-08-17: Fixed the outage that left Pip Live with no access to ChickMark
  data: the sideband's WebSocket attach to the live call authenticated via the
  `openai-insecure-api-key` subprotocol, which the provider rejects for
  standard keys (HTTP 401 on every bind, socket dead in ~500ms), so tools and
  the agent policy never reached the live model. The attach now uses `npm:ws`
  over http/1.1 with a real `Authorization` header (the provider also rejects
  h2 WebSocket upgrades, ruling out `WebSocketStream`), retries pre-open
  failures twice, and logs `sideband.attach_rejected` with HTTP status and a
  truncated body. Deployed as `pip-realtime-sideband-00004-fqs` with the
  rendered v1.1.0 policy and 32-tool catalogue confirmed in the startup log.

- 2026-08-17: The app now sends the wire contract's post-bind
  `{"type":"health","webrtc":true,"data_channel":true}` frame once per
  attempt, so the sideband's authoritative READY gate can actually be
  satisfied; the frame text is pinned byte-for-byte between the Flutter and
  sideband test suites. Live-call captions dropped from `gpt-live-transcribe`
  ($0.017/min) to `gpt-4o-mini-transcribe` ($0.003/min).

- 2026-08-17: Added `scripts/verify_pip_openai_models.sh` (checks the four
  pinned model aliases against the OpenAI account without printing the key; a
  static security test enforces no embedded credentials) — all four verified
  available. Production routing switched per the approved plan:
  `AI_PROVIDER=openai`, `OPENAI_TEXT_MODEL=gpt-5-nano`,
  `PIP_REALTIME_MODEL=gpt-realtime-2.1-mini`; the three affected Edge
  Functions redeployed. A Live start is now also test-proven to never touch
  the recorded-voice STT/TTS pipeline.

- 2026-08-17: Hardened Pip Live UI routing and recovery: all production Live
  opens now share the shell guard, the active banner reserves layout space
  instead of overlaying compact controls, active composer copy now reopens Pip
  Live, and reconnecting calls can be safely retried as a fresh attempt.

- 2026-08-17: Added the dedicated Pip Live call surface with a bounded
  state-driven orb, localized call status, display-only directional captions,
  mute/minimize/end controls, and a shell-wide active-call banner. The shell
  now owns exactly one Realtime controller, so minimizing or switching tabs
  preserves a Live call and reopening it never creates or stops a second call.

- 2026-08-17: Pip Live calls now have a lifecycle-only mobile background
  adapter. Android waits for its acknowledged, low-importance foreground
  notification before provisioning a Realtime session and routes its End action
  through the existing user-ended cleanup; iOS declares active audio background
  mode and uses flutter_webrtc's Apple audio helper around microphone use. The
  native lifecycle never receives call credentials, SDP, session data, audio,
  tools, captions, or RBAC state.

- 2026-08-17: Pip Live now receives the same versioned ChickMark agent policy
  as the typed agent through required rendered Sideband configuration. Startup
  fails closed on missing or blank policy values, every Realtime session update
  carries the policy, and logs record only its version. Both Pip Live deployments
  now default to `gpt-realtime-2.1-mini` through the shared model router.

- 2026-08-17: Centralized Pip model routing by workload. OpenAI conversations
  now use only the trimmed `OPENAI_TEXT_MODEL` override or the pinned
  `gpt-5-nano` default, leaving the existing `OPENAI_MODEL` extraction route
  untouched; this prevents a structured-extraction model from silently becoming
  the conversational model. The same router pins Pip Live to
  `gpt-realtime-2.1-mini`, recorded-note transcription to
  `gpt-4o-mini-transcribe`, and recorded-note speech to `gpt-4o-mini-tts`.

- 2026-08-17: fixed the second live-voice outage ("The live voice session
  could not be authorised"): the sideband's bind-time authorization computed a
  legacy `role:customerId` fingerprint while the provisioner stamps a SHA-256
  over (staffLinkId, accessRole, sorted allow-list, profileRole,
  profileStatus), so EVERY bind failed as `bind.fingerprint_changed` → close
  4401. The sideband now resolves authority the same way the provisioner does
  (`services/pip-realtime-sideband/src/authorization.ts`: profiles is the
  authorization record, allow-list from `customers`/`auditor_customers`,
  staff-link id derived as `app-<profileId>`) and derives the identical
  digest; `test/authorization_parity_test.ts` imports the provisioner's real
  fingerprint module and pins the two byte-for-byte. Deployed as Cloud Run
  revision `pip-realtime-sideband-00003-szf`.
- 2026-08-17: fixed the iOS live-voice outage (`acceptAnswer:
  setRemoteDescription: Error SessionDescription is NULL.`). Root cause: the
  signaling client `.trim()`ed OpenAI's answer SDP, stripping its terminal
  newline; darwin libwebrtc refuses to parse an SDP whose last line is
  unterminated (Chrome tolerates it, which is why the web console flow
  worked). `exchangeOffer` now preserves the body, guarantees a trailing
  newline, and rejects non-`v=` bodies with the first line quoted. Proven by
  a new macOS integration test (`integration_test/realtime_sdp_parse_test.dart`)
  that parses a captured production answer with the same darwin WebRTC build
  the iPhone ships: with the newline it parses, `.trim()`ed it reproduces the
  exact device error. Added `integration_test` dev dependency.
- 2026-08-17: `pip-realtime-session start` now REPLACES the caller's lingering
  session instead of refusing with 409 `session_active`, restoring the plan's
  race-table semantics ("second session starts → clean old generation, then
  provision replacement"). The refusal fought the user in practice — the
  on-screen diagnostics showed a real device retry blocked by its own failed
  predecessor, which sat in `provisioning` for up to the 60s setup deadline.
  Replacement terminalizes only the caller's OWN session
  (`ended`/`replaced`), hands every non-terminal generation to the sweeper as
  `cleanup_pending` (the OpenAI hangup is never dropped), and the partial
  unique index still decides a genuine concurrent race. Consequence made
  explicit in tests: two rapid concurrent starts from one profile may BOTH
  return 200, the later displacing the earlier — the invariant is "exactly
  one live session", not "somebody gets a 409".

- 2026-08-17: Live-voice failures now say WHERE they failed, on screen. The
  controller records which setup stage was in flight when an exception
  surfaced (`errorDetail`: stage, exception type, message — never tokens, SDP,
  or transcript text), keeps the ORIGINAL failure's detail across the single
  automatic recovery, and the chat screen renders it as a selectable
  monospace line under the error banner so a device failure can be reported
  verbatim instead of as "the button turned itself off". Driven by a real
  on-device failure that server-side evidence could not localise: sessions
  showed `register_call` succeeding and `binding_started_at` NULL, with zero
  requests reaching Cloud Run — consistent with several distinct client-side
  causes that only the on-screen stage can now tell apart.

- 2026-08-17: The orphan sweeper now records an already-closed OpenAI call as
  a hangup SUCCESS. Verified live: `POST /v1/realtime/calls/{id}/hangup` for a
  call the provider has already dropped returns 404 "No session found" — the
  ordinary outcome for an orphan, since the client is long gone. It was being
  recorded as `hangup_state: failed`, which made every routine sweep look
  broken. `makeHangup` had no tests at all; it now has five, pinning
  404→success, 200→success, 5xx→failure, network-throw→failure, and the exact
  REST path.

## Maintaining this file

This file is the dated history of the app: what changed, and when.

- Add an entry for every meaningful change, in the same commit as the change.
- Newest entry at the top. Use `- YYYY-MM-DD: ` and describe what changed and
  why, not which files moved.
- Entries are a record. Do not rewrite or delete a past entry because the
  behavior later changed; add a new entry describing the later change instead.
- This file records what happened. `LIVING_SPEC.md` records what is true now.
  A meaningful change updates both.

- 2026-08-16: Stopped sync from reporting a failed push as a successful run.
  Each table's push is isolated in its own try/catch, which is correct, but the
  failure was invisible: `SyncOutcome` carried no failure count, `pushed` simply
  excluded the rejected batch, and the run still ended on `Ready`. A user whose
  data could not reach the cloud saw a fully green sync — today that hides the
  fourteen performance-monitoring tables whose cloud counterparts do not exist
  yet, and it would equally have hidden any future breakage. `SyncOutcome` now
  carries `failed` (rows that did not reach the cloud) and `failedTables`, plus
  `hasFailures` / `fullySynced` / `failureSummary` / `statusMessage`. Both the
  push and the delete paths populate them, the final progress message says how
  many rows did not upload, the Sync Now snackbars say "Sync incomplete", the
  outcome is passed to `SettingsProvider.recordSync(error:)` so the cloud status
  turns to error, and the customers-screen delete confirmation now keys off
  `fullySynced` instead of only checking pending deletes. The dashboard's
  refresh-after-sync guard was narrowed to `lastSyncOnline` so a run that pulled
  fine but failed one push still refreshes.
  Also bounded the retry: failed rows stay `pending`/`failed` and so were
  re-uploaded on every single sync forever. A new `SyncRetryPolicy` skips a
  table for an exponentially growing window (1, 2, 4, 8, 16, then 30 minutes)
  after each consecutive failure and clears on the first success. It is
  process-local — no SQLite schema change, no version bump — so an app restart
  is an explicit "try again now". Skipped batches are still counted as failed,
  so backing off never re-hides the problem.

- 2026-08-16: Covered the Pip Realtime migration's backfills against real
  pre-existing data. `scripts/test_pip_realtime_persistence.sh` proves the new
  invariants hold, but it asserts them on empty agent tables — while the riskiest
  part of `20260816120000_pip_realtime_v1_persistence.sql` is the six backfills
  that run over the rows production already holds. Added
  `scripts/test_pip_realtime_backfill.sh` (and `test/security/
  pip_realtime_backfill_test.dart`), which replays every migration *except* that
  one, seeds legacy conversations, turns and tool events shaped the way the old
  code wrote them, applies the migration over them, and then asserts each
  backfill: `conversation_seq` unique and contiguous from 1 per conversation in
  `(context_epoch, created_at, id)` order, `source_channel` derived from the
  conversation's chat id, `completion_status` finalized, `next_conversation_seq`,
  `turn_index` counters seeded from the current epoch only, a post-migration
  allocation that does not collide with any legacy row, `owner_profile_id`, and
  the survival and continued immutability of existing tool evidence. The fixture
  is deliberately adversarial — created_at ordering disagrees with insertion
  order, with id order and with turn_index order; one epoch-2 turn predates every
  epoch-1 turn; two turns share a created_at; one conversation was reset into an
  epoch that has no turns yet. No backfill bug was found: all six produce the
  right answer on that data.

- 2026-08-16: Gave the Realtime sideband a bind deadline. `CLOSE_BIND_TIMEOUT`
  (4408) was declared and the Flutter client already handled it, but no timer
  ever emitted it: a client could upgrade the socket, send nothing, and hold a
  Cloud Run concurrency slot indefinitely — and with held WebSockets and a small
  max-instance count that is an availability cost, not untidiness. A socket that
  does not bind within `PIP_REALTIME_BIND_DEADLINE_SECONDS` (5s, validated to be
  shorter than the setup deadline, never clamped) is now told
  `{"type":"error","code":"bind_timeout"}` and closed 4408. The deadline is
  cleared the moment bind succeeds, so a long healthy session is never closed by
  it, and nothing durable has been claimed when it fires. Also wired the upgraded
  socket's message and close events to the connection, which the deadline
  assumes and which nothing had connected before.

- 2026-08-16: Turned voice tools on. The Realtime sideband and the tool broker
  both wrote `agent_tool_call_claims` and `agent_tool_events` for the same call;
  the unique indexes on the Realtime key make the second writer a violation, and
  the resulting throw would have left the model's `function_call_output` unsent
  and the call hanging — so `main.ts` shipped with `emptyToolRegistry()` and
  voice exposed no tools at all. The BROKER is now the declared owner: it is the
  only component that re-resolves authorization, enforces argument scope and
  knows the terminal result. `ToolCallCoordinator` takes a required,
  discriminated ownership argument, and in `ledger: 'broker'` mode writes neither
  table and treats the broker's answer — including a replayed duplicate — as
  authoritative, while keeping the per-interaction 5-call budget, a new liveness
  guard (stopped session, lost lease, superseded generation), and the guarantee
  that the model always gets a real result. Broker failures are surfaced
  honestly: unreachable, 5xx and unusable-200 are failures, 4xx are refusals, and
  none of them crash the session or invent a success. `main.ts` now wires the
  real broker executor over the catalogue rendered from `AGENT_TOOL_CONTRACT` and
  supplied as `PIP_REALTIME_TOOL_DEFINITIONS`; the broker URL, secret and
  catalogue are validated at startup and the secret is never logged. Added a test
  that enumerates every contract tool, forces an explicit mutating/non-mutating
  decision, and compares it against the broker's hand-maintained
  `MUTATION_TOOL_NAMES`, so a new write tool cannot silently settle as `failed`
  and become replayable.

- 2026-08-16: Reconciled the Flutter client and the Cloud Run sideband onto one
  wire contract. They were built concurrently and did not agree: the client sent
  a camelCase bind frame with an `openaiCallId` and no access token, and expected
  `ready`/`state`/`caption`/`error`/`ended`, while the server has always parsed a
  snake_case bind frame and sent only `ready`/`error`/`closing`. The SERVER's
  format is canonical — it matches the rest of the backend and it is the security
  boundary — so the client was changed, not the server. The client now sends
  exactly `{"type":"bind","session_id","generation","access_token",
  "binding_token"}` with the caller's Supabase JWT (read at bind time through a
  new `RealtimeSessionPort.accessToken`, so a refreshed session is never bound
  with a stale token) plus the one-shot binding token, both in the first
  application frame and never logged; parses only the three real notices with
  snake_case fields; and maps the WebSocket close code to a distinct cause and
  message so "bind rejected" (4401), "lease lost" (4409) and "bind timeout"
  (4408) no longer read alike. The dead `caption` and `state` branches were
  deleted: transcript deltas reach the app on its own WebRTC data channel
  directly from OpenAI, and the sideband never sent captions at all. The contract
  is written down once in `services/pip-realtime-sideband/WIRE_CONTRACT.md`,
  referenced from both implementations, and pinned by tests on each side that
  assert the same literal bind frame — an edit to one side now fails the other
  side's suite.

- 2026-08-16: Added `supabase/functions/pip-realtime-tool-broker/`, the internal
  tool-broker endpoint that lets the Cloud Run Realtime sideband execute
  ChickMark agent tools, and documented the sideband service itself
  (`services/pip-realtime-sideband/`, 88 tests) whose spec entry was still owed.
  The broker exists so the sideband never forks a second copy of the tool
  catalogue and never needs broad database privileges: it is a single
  authenticated POST that executes ONE tool call through the same shared runtime
  (`executeAgentTool`) the Telegram and in-app doors use. It authenticates the
  SIDEBAND, not an end user, with a constant-time shared-secret comparison
  (`PIP_REALTIME_BROKER_SECRET`, `x-pip-broker-secret`) that fails CLOSED when
  unconfigured — Google OIDC was rejected for this direction because a Supabase
  Edge Function has no Google trust anchor and verifying an ID token would put a
  JWKS fetch on the hot tool path. The fingerprint on the request is never
  trusted: the owner's current scope is re-resolved through `loadAppProfile` /
  `resolveAppAgentScope` and the fingerprint recomputed with the same derivation
  the session provisioner used, and the call is refused unless the caller's
  value, the value stamped on the session and the freshly derived value all
  agree. The generation must still be the live, non-terminal one. Idempotency
  uses `agent_tool_call_claims` on the Realtime key shape plus a canonical
  argument hash: same call id and hash returns the recorded terminal result with
  no second execution and no second evidence row, a different hash is rejected
  as a conflict, and a mutation that ends indeterminate is never auto-replayed.
  Exactly one immutable `agent_tool_events` row is written per call, with a NULL
  `conversation_turn_id`, the interaction id set, and a `tool_sequence` allocated
  per session and generation. The per-interaction 5-call cap is deliberately NOT
  duplicated here — it stays in the sideband's `InteractionTracker`, and a
  comment records that boundary. Also adds `pipRealtimeToolBrokerExecutor` to the
  sideband's `src/tools.ts` as the concrete client for this endpoint. Known gap:
  the sideband's `ToolCallCoordinator` still writes its own claim and evidence
  rows, which collide with the broker's under the tables' partial unique indexes,
  so `main.ts` continues to use `emptyToolRegistry()` until the coordinator gains
  a "broker owns claims and evidence" mode.

- 2026-08-16: Added the Flutter client for Pip Realtime V1 voice ("Pip Live"):
  `lib/services/realtime/` and `RealtimeVoiceController`, plus a live control in
  the assistant composer that is separate from the recorded-voice mic button.
  The security invariant — no microphone audio reaches the remote peer before
  the server declares an authoritative READY — is implemented as a null-track
  sender, not as `track.enabled`: the mic stream is acquired but never passed to
  `addTrack`, a `sendrecv` audio transceiver is added with **no** track
  argument, SDP is negotiated while that sender is empty, and only a validated,
  current-generation READY triggers `sender.replaceTrack(micTrack)`, which swaps
  the source without renegotiation. `track.enabled` is used only as a secondary
  UX mute. Assertions read `getStats()` filtered to `outbound-rtp`/`audio` off
  the peer connection (never `sender.getStats()`, which returns whole-connection
  stats when the track is null) and treat "no report at all" as proof of
  silence. Every setup step is generation-guarded, so navigating away,
  cancelling or logging out mid-setup tears the attempt down instead of turning
  the microphone on; a stale or duplicate READY is inert. Recovery is allowed
  exactly once per user-initiated start and always restarts non-transmitting,
  handing the failed session back to the control plane first so the one-session
  invariant cannot refuse the retry. Data-channel tool/function-call events are
  dropped without being executed, relayed or logged — only the Cloud Run
  sideband runs tools. A live call ORs into the assistant screen's `isVoiceBusy`
  gate so recorded voice and Realtime can never contend for the one iOS
  `AVAudioSession`. Adds `flutter_webrtc`, iOS `ONLY_ACTIVE_ARCH` and the
  Android audio/network permissions.

- 2026-08-16: Added `supabase/functions/pip-realtime-session/`, the
  authenticated control plane for Pip Realtime V1 voice. It carries no audio,
  runs no agent turn and grants no tool authority — it decides whether a voice
  session may exist and records that decision. Four actions: `start` (kill
  switch, then a 5-per-300s per-profile rate limit, identity, daily budgets,
  and the one-session invariant, then provision generation 1, mint an ephemeral
  OpenAI client secret and issue a one-shot binding token), `register_call`
  (writes `openai_call_id` onto the already-provisioned generation row and
  nothing else), `abort_setup` (marks the generation `cleanup_pending` for the
  sweeper) and `end`. Realtime reads `OPENAI_API_KEY` only: never
  `OPENAI_VOICE_KEY`, which belongs to the recorded-voice path, and never
  OpenRouter or the text provider resolver, since a voice session has no text
  provider to fall back to — a missing key means Realtime is unavailable, not
  degraded. Authorization reuses `app_agent_scope.ts` verbatim and is
  re-derived per action as a fingerprint over staff-link id, access role,
  sorted allowed-customer ids, profile role and status, so a demotion between
  `start` and `register_call` invalidates a live session; conversation id,
  context epoch and state version are deliberately excluded because they churn
  every turn. Budgets count settled seconds **plus in-flight** seconds of live
  sessions, clamped to the UTC day and to `ready_at + MAX_SESSION_SECONDS`,
  because usage settles only on end and a caller who never ends a session would
  otherwise never accrue anything; a session that never reached READY counts
  zero. The binding token is returned exactly once and stored only as a
  SHA-256 hash. 59 colocated Deno tests, no network.

- 2026-08-16: Every instant `pip-realtime-session` persists now comes from one
  read of the database clock (`public.realtime_now()`) taken at the top of the
  request, rather than from the Edge Function's own clock. Three hosts arbitrate
  a single Realtime deadline — the Edge Function writes `setup_deadline_at`, the
  Cloud Run sideband evaluates it, and the cleanup sweeper compares it against
  SQL `now()` — so host skew would silently move the deadline and let a session
  be swept while the sideband still believed it had time. A failed clock read
  refuses the request with `clock_unavailable` instead of falling back to the
  local clock, because a wrong clock is worse than a refused start.

- 2026-08-16: Split the agent's model-facing tool surface out into a stable,
  versioned contract (`agent_tool_contract.ts`) carrying
  `AGENT_TOOL_CONTRACT_VERSION` at `1.0.0`. `AGENT_TOOL_DEFINITIONS` is now
  derived from it, so the model, the runtime's known-tool set, and the
  gateway's argument validation all read one source of truth. The rule the
  split enforces: the contract is versioned and moves only when a business
  capability changes — a migration that renames a column or reshapes a table
  must not move it, only the tool handler's query. Behaviour, tool names, and
  parameters are unchanged; this is purely the boundary. A new
  `agent_tool_contract_test.ts` pins `contractFingerprint()` to
  `a8624598023a48fc` alongside a full inline snapshot of every tool name,
  parameter, required flag, and enum, and pins the flat
  `{type, name, description, parameters}` definition shape the OpenAI Realtime
  API requires (the nested Chat-Completions `{type, function:{…}}` form is
  rejected and was an easy regression).

- 2026-08-16: Both agent doors now share one conversation-context loader and
  the atomic turn allocator. The duplicated history-plus-intake load moved into
  `supabase/functions/telegram-hatchery-agent/agent_context.ts`, which both the
  Telegram webhook and the in-app chat function call; the history limit is now
  one constant instead of a named 40 in one door and a hardcoded 40 in the
  other. Context is ordered by `conversation_seq` rather than `created_at`, so
  turns written inside the same millisecond (or finalized out of order by a
  voice session) still read back in allocation order, and only
  `completion_status = 'finalized'` turns are replayed to the model — a
  half-heard Realtime turn is durable evidence but not context. Both doors also
  stopped scanning rows to guess the next `turn_index`: every durable turn now
  takes its slot from `chickmark_private.allocate_agent_turn_slot` via the
  service-role client, persists the returned `conversation_seq`, and records its
  `source_channel` and `completion_status`. The outbound-reuses-inbound
  `turn_index` convention is unchanged; the reply passes its inbound index as
  the allocator's override. Note the RPC lives in `chickmark_private`, which the
  project's PostgREST configuration must expose before either door can reach it.

- 2026-08-16: Added the Pip Realtime V1 shared persistence layer
  (`20260816120000_pip_realtime_v1_persistence.sql`, defined but **not yet
  applied to production**). It adds `conversation_seq` — a per-conversation
  chronological key across both directions that never resets on a context-epoch
  bump — alongside the existing `turn_index`, whose per-(epoch, direction)
  meaning is deliberately unchanged. Turn allocation moves into
  `chickmark_private.allocate_agent_turn_slot`, which locks the conversation row
  and hands out both keys from stored counters, replacing the client-side
  "max over the newest 40 rows" scans in the two Edge Functions. Counters are
  authoritative rather than derived from `MAX()`, because two allocations taken
  before either row is inserted must still get distinct indexes — the first
  version of the allocator failed exactly that case. `agent_tool_events`
  gains a nullable `conversation_turn_id` (its UNIQUE constraint becomes a
  partial index) so a Realtime tool call that fires before its transcript
  finalizes can be recorded without fabricating a placeholder turn; because the
  evidence row is immutable, the late turn link lives on the new mutable
  `agent_tool_call_claims` ledger instead. Also adds conversation summaries,
  owner-private memories, and the Realtime operational tables — sessions, calls,
  a per-(session, UTC day) usage ledger, start attempts and a kill switch — all
  on `timestamptz`, all server-only and deliberately unregistered in the sync
  layer so they never reach SQLite.

- 2026-08-16: Reconciled the Supabase migration ledger with the repository,
  which had diverged in both directions: of 22 local files and 32 deployed
  versions, only 5 matched. Thirteen files were renamed onto the versions they
  actually ran as, each justified by a normalized-hash comparison against the
  ledger's stored SQL rather than by assumption; the three that did not match
  exactly were resolved individually (a `begin;`/`commit;` wrapper the CLI
  strips, a CHECK whose effect was verified present in production, and a
  `shell_temp` column that exists only in the cloud copy). Fourteen
  production-only migrations — including the entire organizations/account-type
  stack, whose SQL existed nowhere in the repo — were recovered verbatim from
  `supabase_migrations.schema_migrations.statements`. Two applied migrations
  that had no ledger row were repaired into it, ledger-only, with no DDL. The
  repo and production now agree on 33 of 35 versions. Recovering
  `20260727214044_align_flocks_performance_columns.sql` also removed a latent
  lie: the local migration replay had been silently depending on the *unapplied*
  `0017` to supply `flocks.sector_key`.

- 2026-08-16: Added `supabase/migrations_unapplied/` and
  `supabase/migrations_archive/` for migrations that must not replay. `0009` and
  `0017` are genuinely unapplied; `20260418043712_create_hatchaudit_schema` is
  the pre-reset schema that `20260605115351` drops, and it cannot replay from
  empty because it forward-references `customers`.

- 2026-08-16: Added `20260816090000_profiles_username_column.sql` (**not yet
  applied**) for a live production defect: `handle_new_auth_user()` still
  carries the legacy branch from the never-applied `0009`, inserting a
  `username` column that does not exist. Since the client sends no
  `account_type`, every self-serve signup falls into that branch and raises
  `42703`, aborting the `auth.users` insert — and the client masks it with
  "Account created locally." `profiles` holds 2 rows, both `internal`; no
  self-serve signup has ever succeeded. Admin → Users is also broken, since
  `admin_repository.dart` selects `username`. The fix adds only the column,
  its partial unique index and its format check, and deliberately does not
  touch the trigger: applying `0009` wholesale would `create or replace`
  `handle_new_auth_user()` and delete the account-type routing added by
  `20260813172732`.

- 2026-08-16: Fixed 25 failing tests. Twenty-four shared one cause — the
  mocktail stubs for `pullFromSupabase` never listed
  `upsertBmkOperationalStandard`, so no stub matched and the unstubbed call
  returned null. The twenty-fifth was an untranslated `Replay` tooltip.

- 2026-08-16: Brought `docs/DATABASE_SPEC.md` back in line with the code. It had
  drifted badly: it claimed schema version 47 (actual 59), documented only 21 of
  the 61 tables, still listed the removed `egg_storage.shellTemp`, and published
  a scope-support table that no longer matched `PanelSampleSchema.allowedLayers`
  for any panel. The spec now covers the farm hierarchy, broiler daily records
  and objectives, performance monitoring, diagnostic visits, both agent
  generations, and the real push/pull ordering and pull-only/immutable table
  rules, and it records the panel column reconciliation that happens on every
  database open.

- 2026-08-16: Fixed app-channel staff links never reaching the local database,
  which broke the whole agent conversation pull. `telegram_staff_links` was
  created when Telegram was the only channel, so `telegramUserId` was
  `NOT NULL UNIQUE`; the cloud row for an in-app staff member carries no
  Telegram identity, and the pull's `INSERT OR IGNORE` dropped it without an
  error. Every `agent_conversations` row pointing at that link then failed its
  foreign key, aborting the conversation, turn, and tool-event pull on every
  sync cycle. Schema version 59 rebuilds the table with a nullable
  `telegramUserId`, a `channel` column, an `appUserId`, and partial unique
  indexes per identity. Pull now isolates row failures instead of discarding
  the rest of the table, and logs a row the local schema silently rejected.

- 2026-08-14: Pip's chat bubbles now render markdown (bold, numbered/bulleted
  lists) via `gpt_markdown` instead of showing raw syntax characters, and each
  bubble's text direction is detected per message from its own first
  strong-direction character instead of following the screen's locale, so an
  Arabic reply is right-to-left even in an English-locale screen and vice
  versa.
- 2026-08-14: Stopped the agent from leaking its internal reasoning ("We need
  to interpret the user's request…") into chat replies: the prompt now forbids
  outputting planning/deliberation text, and the per-call output token cap was
  raised from 1200 to 2400 so reasoning-heavy models no longer get truncated
  mid-reply.
- 2026-08-14: The agent now understands breed names spoken or typed in Arabic
  script (روس, كوب/كاب, هبرد): it transliterates them to the Latin breed name
  before the benchmark lookup, and when a name still misses it suggests the
  closest covered breed as a "do you mean Cobb 500?" question instead of
  claiming the system has no data for that breed.
- 2026-08-14: Improved voice reply quality and added playback controls.
  Server-side TTS moved from `tts-1`/voice `alloy` to `gpt-4o-mini-tts`/voice
  `ash`, with Egyptian Arabic pronunciation instructions for `ar`/`mixed`
  replies — `alloy` mispronounced Arabic badly. Voice-key resolution now
  falls back to `OPENAI_API_KEY` when no separate `OPENAI_VOICE_KEY` secret
  is set, so voice works immediately off the key already configured for the
  text brain. On the client, `ChatMessage` carries the reply's audio in
  memory (never persisted to history), and any assistant bubble with audio
  gets a play/pause toggle and a replay button; `AssistantProvider` gained
  `playMessageAudio`/`pausePlayback`/`resumePlayback` so only one message's
  audio plays at a time, and the auto-play-on-voice-reply behavior now routes
  through the same path as a manual tap.
- 2026-08-14: Fixed silent voice replies on iOS. The TTS reply audio was
  played via audioplayers' `BytesSource`, which iOS/macOS do not support; the
  resulting throw was swallowed by the deliberate best-effort playback
  handling, so voice questions came back as text only. The reply clip is now
  written to a temp file and played with `DeviceFileSource` (supported on all
  platforms), then deleted after playback.
- 2026-08-14: Upgraded voice recording from `record` 5.2.1 to 7.1.1 so
  Flutter 3.44 resolves a mutually compatible set of federated platform
  plugins. The previous lockfile paired `record_linux` 0.7.2 with
  `record_platform_interface` 1.6.0; that Linux implementation did not satisfy
  the newer interface and caused iOS release compilation to fail before Xcode
  could package the app. Since `record` 7 eagerly opens its platform channel
  from `AudioRecorder()` construction, the production recorder is now created
  lazily on the first voice action; opening text chat no longer initializes
  microphone infrastructure, and provider unit tests remain binding-free.
- 2026-08-14: Fixed two more findings from a re-review of the voice-chat
  final-cleanup pass. (1) Finding 3 (retry of a failed voice turn sending
  literal placeholder text) was only half-fixed: the message bubble's own
  Retry button was correctly gated on `AssistantProvider.canRetry`, but the
  error banner above the message list has a second, independent Retry
  affordance (`_retryLast` in `assistant_chat_screen.dart`) that still picked
  "the last failed turn" unconditionally — since a failed voice send always
  sets `error`, this banner was visible with a live-looking Retry button in
  exactly Finding 3's scenario, and tapping it silently no-op'd (via
  `canRetry`'s guard inside `retry()`) with no feedback; worse, if a
  retryable failed typed turn preceded a non-retryable failed voice turn,
  `failed.last` picked the voice one, making the typed turn unreachable via
  the banner. `_retryLast` now filters to `provider.canRetry` before picking
  the last one, falling back to `provider.load()` when none qualify, same as
  the already-existing no-failed-turn case. (2)
  `AudioplayersAssistantAudioPlayer._playAndAwaitCompletion`
  (`lib/services/audio/assistant_audio_player.dart`) had an orphaned-completer
  bug: when a second `play*` call interrupted a still-pending first one (e.g.
  the reply audio cutting off the filler chime), it called `_player.stop()`
  and overwrote `_pendingCompletion` with a fresh `Completer` without first
  completing the one it replaced — `audioplayers` never emits
  `onPlayerComplete` for a programmatic `stop()`, so the interrupted call's
  `Future` stayed permanently pending (harmless today since the chime call
  site is `unawaited()`, but a leak worth closing since the machinery was
  already there). Fixed by completing any existing `_pendingCompletion`
  before creating the new one; the identical overwrite pattern in
  `test/features/chat/fake_assistant_audio.dart`'s
  `FakeAssistantAudioPlayer._awaitCompletion` is fixed the same way, for
  consistency with the real implementation's contract. Verified the
  completer fix with a new fast, pure-`dart test` suite,
  `test/services/audio/assistant_audio_player_completion_test.dart`, that
  mirrors `_playAndAwaitCompletion`'s exact control flow against a minimal
  fake player (confirmed to genuinely time out without the fix, and pass
  with it) — a full integration test against the real `audioplayers`
  `AudioPlayer` via `flutter test` was attempted but repeatedly hung in this
  sandbox for reasons unrelated to the fix's correctness and was abandoned
  in favor of the faster, reliable pure-Dart proof. `test:` was added as an
  explicit dev dependency in `pubspec.yaml` (it was already resolved
  transitively via `flutter_test`) since the new test imports it directly.
- 2026-08-14: Localized Pip chat action tooltips and their accessible labels in
  Arabic, including the voice recording states, and documented Pip as the
  shell destination with text and voice turns. Arabic chat layout regression
  coverage now verifies Pip's avatar and reply bubble occupy reading-start
  while the user's turn remains at reading-end.
- 2026-08-14: Introduced Pip as the in-app assistant identity, retaining the
  Latin-script name in Arabic so the product name remains consistent across
  interfaces. A static clean ChickMark avatar now anchors the chat header,
  empty state, assistant messages, and thinking state; user messages remain
  unbadged, and the logo treatment intentionally omits sparkles, badges, and
  other generic AI-brand symbols.
- 2026-08-14: Fixed a batch of findings from the final whole-branch review of
  the voice-chat feature (7 items, all in `lib/features/chat/`,
  `lib/services/audio/assistant_audio_player.dart`,
  `lib/services/supabase/assistant_chat_service.dart`, and
  `supabase/functions/app-hatchery-agent/`). (1) Retrying a failed voice turn
  used to resend the literal placeholder text "Voice message" to the agent,
  since the recorded clip is discarded the moment it is sent and there is
  nothing left to actually retry; `AssistantProvider.canRetry()` now hides the
  Retry action for voice-originated failed turns instead. (2) `clear()` was
  reachable mid-voice-send (it only checked `isSending`, not `isRecording`/
  `isAwaitingVoiceReply`), so confirming clear while a voice reply was still in
  flight could empty the conversation and then have the late reply land in the
  now-cleared list; `clear()` and the app-bar clear button now guard on all
  three flags, matching what `startRecording()` already checked. (3) Three
  unguarded async gaps around the recorder/player: the filler chime's
  `unawaited()` call did not swallow errors (only skipped the await), so a
  chime failure could become an unhandled zone error — it is now wrapped in
  its own try/catch; `_audioRecorder.stop()` in `stopRecordingAndSend()` sat
  outside any try/catch, so a platform/file-read throw escaped uncaught — it
  now surfaces through `error` ("Could not save that recording. Please try
  again."); `startRecording()` only caught `AssistantAudioException` — it now
  also has a generic catch-all fallback, mirroring the two-tier pattern
  already used in `send()`/`_deliver()`. (4) `dispose()` only set a disposed
  flag; if the user navigated away mid-recording the microphone stayed open
  and the temp clip was never cleaned up — `dispose()` now best-effort stops
  an in-progress recording and any in-flight playback. (5) `isSpeaking` was
  reset almost immediately after `playBase64()` returned, because
  `audioplayers`' `AudioPlayer.play()` Future resolves once playback *starts*,
  not once it finishes — the mic was re-enabling while the reply was still
  audibly playing. `AudioplayersAssistantAudioPlayer` now listens to the
  underlying player's `onPlayerComplete` stream and only resolves its own
  Future once playback genuinely finishes (or `stop()` cuts it short); the
  `AssistantAudioPlayer` interface doc now states both `playAsset` and
  `playBase64` resolve on completion, and `FakeAssistantAudioPlayer` gained an
  opt-in `manualCompletion` mode so a test can hold a "playback" open to
  observe `isSpeaking` mid-flight. (6) The audio ceiling (8,000,000 base64
  chars, roughly tens of minutes of speech) was far more generous than "a few
  seconds of speech," which combined with the 20-sends/5-minute rate limit
  could burn through the OpenAI voice budget quickly; both
  `MAX_AUDIO_BASE64_CHARS` (server) and `assistantAudioMaxBase64Chars`
  (client) are lowered to 1,500,000, kept numerically equal, and
  `AssistantProvider.startRecording()` now arms a 60-second
  `maxRecordingDuration` timer that auto-stops and sends the clip, cancelled
  on manual stop or `dispose()`. (7) Added
  `supabase/functions/app-hatchery-agent/voice_contract_fixture.json`, a
  single physical JSON fixture pinning the voice `send` request/response
  field-name lists; one Deno test in `index_test.ts` and one Dart test in
  `assistant_chat_service_test.dart` each read it and assert their side's
  actual keys match, so a field rename on either side of the client/server
  boundary without updating the fixture now fails a test in that language.
- 2026-08-14: Landed voice input/output for the in-app assistant chat. On the
  server, `app-hatchery-agent`'s `send` action now accepts an `audioBase64`
  clip in place of `message`: it transcribes the clip via OpenAI Whisper
  using a new `OPENAI_VOICE_KEY` secret (kept separate from the text brain's
  `OPENAI_API_KEY`), runs the transcript through the same unmodified agent
  brain used for typed messages, stores it as an ordinary turn `text`, and
  attempts to synthesize the reply via OpenAI TTS, returning `audioBase64` on
  success; a transcription failure returns `agent_unavailable` rather than
  `invalid_request` since it is an audio-quality problem, and a TTS failure
  degrades the call to a text-only reply instead of failing the turn. On the
  phone, `AssistantChatScreen` gained a mic button that starts and stops
  recording through the `AssistantAudioRecorder`/`AssistantAudioPlayer` ports
  landed for `AssistantProvider` earlier the same day. While recording, the
  text field is disabled but the mic remains enabled as the Stop control;
  during a send or while awaiting or playing a voice reply, both controls are
  disabled so the two input modes cannot race. This closes out the mic-control
  gap noted in the two entries below.
- 2026-08-14: The v58 upgrade no longer stamps pre-existing user edits to operational BMK standards as `synced`. It now re-marks any row with a non-null `updatedAt` or `hatcheryId` as pending, so edits made before this table joined the sync path still push instead of being silently dropped from sync forever.
- 2026-08-14: Writing a global operational BMK standard now requires an approved admin, matching the cloud admin-only policy. Previously any auditor could create a global row that RLS rejected on every push, and because the operational push marks the whole dirty batch failed on any error, that one row blocked every legitimate hatchery override indefinitely.
- 2026-08-14: Added direct column-level coverage for the v58 migration (`bmk_operational_sync_migration_test.dart`) and corrected the schema-parity net's docs, which wrongly claimed no migration alters a v41-baseline table; v57 and v58 both do, so that net cannot see them.
- 2026-08-14: The benchmark block auto-attached to audit reads now carries the coverage payload on a miss (`availableBreeds`, or `breed` plus `coveredWeeks`) instead of only the reason code, so the agent can say what is covered without a second tool call.
- 2026-08-14: The agent prompt now requires benchmark figures to come from the BMK tools, with the breed and age week always stated.
- 2026-08-14: Audit summary and selected-breakout reads now carry the matching breed and breakout benchmark, or an explicit reason it is unavailable.
- 2026-08-14: Fixed `compare_selected_audit_to_benchmark` to match its stated sibling contract: it now returns `fresh_audit_selection_required` (not `audit_selection_required`) when no audit is selected, and now also treats a stale `flockId` in the conversation's remembered selection as requiring fresh selection, instead of silently comparing against the wrong audit's benchmark.
- 2026-08-14: The agent can compare the selected audit against breed and egg-breakout standards, with deltas computed server-side and unmatched metrics reported rather than dropped.
- 2026-08-14: The agent can read operational standards, merging global rows with the requesting hatchery's overrides and rejecting hatcheries outside the caller's scope.
- 2026-08-14: The agent can look up breed and egg-breakout benchmarks from bmk_breeds / bmk_egg_breakout, with structured misses instead of guessed values.
- 2026-08-14: Sync now pulls BMK operational standards from the cloud, behind the same dirty-row guard as the other reference tables.
- 2026-08-14: Sync now pushes dirty BMK operational standards to the cloud, after hatcheries so the hatchery FK resolves.
- 2026-08-14: BMK operational standards are now dirty-tracked on edit and can be applied from a cloud row.
- 2026-08-14: Added the cloud `bmk_operational_standards` table with split RLS — global rows read-all/write-admin, hatchery rows scoped through the owning customer.
- 2026-08-14: Fixed two review findings on the voice-turn state added to
  `AssistantProvider` earlier the same day. (1) A playback failure of the TTS
  reply audio (bad codec, no output device, decode failure) was being caught
  by the same try/catch as the network send and reported through
  `_failMessage`, setting a misleading "could not send" `error` even though
  the send had already succeeded and both turns were already delivered.
  `stopRecordingAndSend()` now attempts reply-audio playback in its own
  try/catch *after* the send's try/catch completes, so a playback failure is
  swallowed instead of touching `error` or the message list. (2) The earlier
  fix for eager `AudioPlayer()` construction breaking plain-constructor unit
  tests had modified `lib/services/audio/assistant_audio_player.dart`
  (`AudioplayersAssistantAudioPlayer`), a file outside this feature's scope,
  changing that class's construction contract for every caller.
  `assistant_audio_player.dart` is reverted to eager construction as originally
  shipped; instead `AssistantProvider` itself now lazily constructs its
  *default* `AudioplayersAssistantAudioPlayer` only on first actual use when no
  player was injected, confining the fix to the provider. `RecordAssistantAudioRecorder`
  needed no equivalent change — `record`'s `AudioRecorder()` constructor only
  generates a uuid and does not touch a platform channel.
- 2026-08-14: Added voice-turn state to `AssistantProvider`: `startRecording()`
  and `stopRecordingAndSend()` drive an injectable `AssistantAudioRecorder`/
  `AssistantAudioPlayer` pair, tracked via new `isRecording`,
  `isAwaitingVoiceReply`, and `isSpeaking` flags. A voice turn plays a filler
  chime while waiting, sends the clip through `AssistantChatPort.sendVoice`,
  swaps the optimistic "Voice message" placeholder for the server transcript,
  and auto-plays a TTS reply when the server returns one; a failed send marks
  the turn `failed` the same way a text send does. This is provider-only —
  `AssistantChatScreen` has no mic control yet. Also made
  `AudioplayersAssistantAudioPlayer`'s underlying `AudioPlayer` lazy (created
  on first use instead of in the constructor init list): eager creation
  touched a platform channel and broke every plain `AssistantProvider()`
  construction in unit tests, which have no Flutter binding.
- 2026-08-14: Broke up the two largest files and added a database migration
  safety net. `AuditProvider` (~4,900 lines) was split into pure value-parsing
  utilities, meaningfulness predicates, panel and egg-breakout value builders,
  and an `AuditPanelSaveCoordinator` holding the save/delete/prune cluster;
  the provider is now ~2,500 lines. `stub_sections.dart` (2,837 lines) became
  one file per dashboard section plus a shared helpers file. Both splits are
  move-only: no schema, JSON shape, written-column or repository-call-order
  changes. A new schema-parity test proves a v41-baseline database upgraded
  through the real v46–v56 chain is structurally identical to a freshly
  created v56 database; it calls the upgrade hooks directly because the
  on-open surgical schema repair otherwise masks exactly that class of
  regression. The parity net can catch a migration that adds or drops a whole
  table, but not one that alters an existing baseline table's columns. Also
  removed a weight-sample-size rule that had been duplicated verbatim across
  three files, and made the setter/hatcher context ids required arguments so
  a forgotten id is a compile error rather than a silently wrong answer.
- 2026-08-14: Opened a second door into the existing hatchery agent so staff
  and customers can talk to it inside the app instead of only through Telegram.
  A new Assistant tab, available to every approved role including customers,
  holds one text conversation per user backed by a new `app-hatchery-agent`
  Edge Function. That function is deployed with JWT verification and reuses the
  Telegram brain verbatim — same turn runner, prompt, and tool catalog, no new
  agent tools — but resolves the caller's customer scope per request from
  `profiles` and `auditor_customers` rather than trusting the client or a
  stored allow-list, and refuses anyone not approved. App turns are stored as
  ordinary agent conversation evidence, so admins review the same tables no
  matter which door a message came in through. Sends carry a client idempotency
  key so a retried or replayed request returns the stored reply instead of
  paying for a second model call, clearing the conversation bumps the context
  epoch and keeps the old turns as evidence, and a rolling per-user send limit
  bounds cost. To make one link table serve both doors, staff links now record
  their channel and may anchor to an Auth user instead of a Telegram user. This
  bite is text only; voice, photo attachments, and conversational data entry
  are not part of it.
- 2026-08-14: Stabilized offline cold starts and resumes. Remembered users
  entering through the 30-day offline grace now go directly from the login
  gate to the existing main shell instead of visiting the animated startup
  sync route. One app-lifetime network monitor now supplies explicit unknown,
  online, and offline state to auth revalidation, automatic sync, Settings,
  and the persistent shell indicator. Automatic shell-start, local-write,
  resume, and reconnect sync requests are held while offline/unknown, coalesce
  into one pass after a verified reconnect, and back off boundedly after an
  uncertain failure; reachability probes the Supabase host so an active but
  captive/uplink-less interface is not assumed usable. Home now distinguishes
  uninitialized/loading from a completed empty result, preventing temporary
  `0 / 0 / — / No recent audits` output before SQLite queries finish. The
  duplicate Home offline SnackBar was removed in favor of the monitor-backed
  top-shell indicator.
- 2026-08-13: Split the documentation in two. The dated change history moved
  out of `LIVING_SPEC.md` section 9 into this file, leaving a pointer in its
  place, so the spec describes only current behavior and history lives here.
  Both files gained a "maintaining this file" header, and `CLAUDE.md` and
  `AGENTS.md` now carry the rule that a meaningful code change updates both in
  the same commit. `AGENTS.md` was also refreshed: dead `001-dashboard-
  intelligence` scaffolding removed, and a repo map, commands, schema-change
  checklist, sync model, and gotchas added.
- 2026-08-13: Removed the unused LTTB chart downsampler. `LttbDownsampler` and
  its test were deleted and the Govee saving-state label no longer mentions
  LTTB. Govee captures already stored every valid reading in
  `chartPointsJson`, and the downsampler had no call site, so this removes
  dead code without changing behavior. Saving the full valid-reading set is
  the intended behavior; sections 4, 5, 6, and 7 were corrected to match, the
  stale `DiagnosticEngine.evaluate` debt item was dropped, and the Home app
  bar, Home section order, and Audits-tab session-tap descriptions were
  corrected against the code.
- 2026-08-13: Split app-startup authentication into an unchanged login gate
  and a new, connectivity-tolerant usage gate. `UserRepository
  .getRememberedUser()` replaced `getCachedUser()` and no longer requires an
  unexpired `tokenExpiry`. `SupabaseService.restoreSession()` asks Supabase to
  validate or refresh the session and classifies transient/ambiguous failures
  (including 5xx `AuthRetryableFetchException`) as `offline` rather than a
  rejection, so a flaky or absent connection can never by itself cause a
  logout. A new Keychain-backed `SessionTrustStore` records the last proven
  online login per user; the pure `decideStartupAuth()` function combines the
  remembered user, the restore outcome, and that trust record into one of
  three outcomes — enter app, enter app pending re-validation (device offline
  but within the 30-day `AuthSessionPolicy.offlineGrace` window), or go to
  login (never verified, grace lapsed, or a definitive online rejection).
  `AuthProvider.checkCachedToken()` now drives this decision and rejects a
  restored session or trust record that belongs to a different account than
  the one remembered on-device. A new `SessionRevalidationTrigger` calls
  `AuthProvider.revalidateSession()` silently on app resume and on
  `connectivity_plus` reconnect events, clearing the pending flag on success
  and signing out only on a definitive rejection. Local-only (`local-` id)
  accounts are unaffected and keep their existing 30-day `tokenExpiry` rule.
  The intended companion Supabase Dashboard session settings (JWT expiry
  3600s, refresh-token rotation with a 10-second reuse interval, session
  time-boxing disabled, 90-day inactivity timeout) are project configuration,
  not code, and are recorded in §2 as the target configuration rather than
  something this change verifies.
- 2026-08-13: Made Agent Monitor pause/resume cloud-authoritative. The control
  keeps the prior confirmed state visible and remains disabled during a
  targeted, verified Supabase write; only the returned cloud row is mirrored
  to SQLite and published as running/paused. Cloud failures preserve the prior
  state and surface an error, and repeated taps cannot create overlapping
  transitions. Telegram now follows successful pause and resume actions
  immediately without requiring an app restart.
- 2026-08-13: Unfroze the Agent Monitor header on narrow screens. The header
  panels were fixed children of a Column, so on a phone they consumed the
  viewport and left the workspace a few unusable pixels. Narrow layouts now
  render as one scrolling page with a shrink-wrapped workspace list and
  pull-to-refresh reload, while wide layouts keep the pinned header and
  side-by-side panes. The same pass made the health and Telegram users cards
  collapsible, with health keeping a one-line summary when collapsed, gave
  health chips a bold value and a border, made staff tiles dense with
  ellipsis, and stacked the pending-access tile's Approve/Reject actions
  under 420px.
- 2026-08-12: Healed cross-branch SQLite drift and surfaced flock save
  failures. Builds from other branches leave their triggers in the shared
  database file, where `breeder_cycle_*` triggers aborted legitimate flock
  edits and sync pull upserts after a branch switch. Surgical repair now
  drops triggers matching foreign prefixes and restores
  `flocks.depletionAgeWeeks` and `flocks.soldAt`. `AddFlockSheet` had
  swallowed repository failures, so Save appeared to do nothing; errors now
  render in-sheet, the button disables while saving, and a missing customer
  reports inline instead of through a SnackBar.
- 2026-08-11: Corrected reference-table sync. Customers, hatcheries, and
  flocks push only dirty rows instead of the previous full-table bulk push on
  every sync, which clobbered unsynced remote edits. Each reference push is
  isolated in its own try/catch, so a failing table marks its own rows failed
  and the run continues to the pull instead of aborting. Pull-side upserts
  for these tables skip rows that are locally pending or failed, so a cloud
  row cannot overwrite an unsynced local edit. The dirty-read cutoff pattern
  was extended to the six repositories that already dirty-track — audit
  session, panel sample, Govee capture, performance sync, dashboard action,
  and lab analysis — so an edit landing while a push is in flight stays
  pending instead of being stamped synced and dropped; `mark*Failed` stays
  unconditional. Local `updatedAt` is stripped at the flocks push call site
  because cloud `flocks` has no `updated_at` column and sending it made
  PostgREST reject the whole dirty batch. Customer-role devices, which never
  push, bypass the pull-side dirty guard so version 57's `pending` default
  cannot freeze their pulled updates. `uploadPhoto` and `deleteRows` now
  throw when offline instead of allowing photos and tombstones to be marked
  synced.
- 2026-08-11: Added database version 57. `customers` and `hatcheries` gained
  `syncStatus`, `dirtyAt`, `lastSyncedAt`, and `syncError`, and `flocks`,
  which has had the other three since version 51, gained `lastSyncedAt`. New
  columns default `syncStatus` to `pending`, so existing rows push once on
  the next sync and then settle into incremental pushes. The upgrade, the
  surgical-repair `_criticalColumns` map, and the fresh-install `CREATE
  TABLE` definitions were kept in parity, and four schema tests' hardcoded
  `PRAGMA user_version` expectation moved from 56 to 57. `CustomerRepository`,
  `HatcheryRepository`, and `FlockRepository` gained `getDirtyRows`,
  `markRowsSynced`, `markRowsFailed`, and `getRowSyncStatus`; local writes
  stamp rows pending and pull-path upserts stamp them synced.
- 2026-08-08: Hardened two database upgrades against divergent development
  lines. Apple's system SQLite enables `legacy_alter_table` by default, so
  the version 56 shadow rebuild's renames left the new tables' foreign-key
  clauses pointing at dropped shadow names and the post-rebuild
  `foreign_key_check` aborted the upgrade; `PRAGMA legacy_alter_table = OFF`
  is now set before the rebuild. Separately, branches that shipped
  `agent_conversations`, `agent_conversation_turns`, and `agent_tool_events`
  without the columns version 54's partial indexes and backfills reference
  crashed the upgrade with `no such column: turnIndex`, because `CREATE TABLE
  IF NOT EXISTS` preserves the old shape; those columns are now ensured
  first, mirroring the version 56 repair.
- 2026-08-07: Carried the `0017_performance_monitoring.sql` Supabase
  migration into the repository so the cloud migration chain stays coherent
  with the performance-monitoring tables the app already uses.
- 2026-07-31: Fixed Telegram audit-summary confirmation after a single audit
  result. Single results remain numbered, a legacy affirmative confirmation
  selects persisted option 1 without re-resolving stale customer/flock IDs,
  and `get_audit_summary` now reads only the server-selected audit context
  instead of accepting a model-supplied audit ID. Scope guards remain
  fail-closed for missing, changed, or unauthorized selections.
  `telegram-hatchery-agent` v19 is active with the existing custom Telegram
  webhook authentication.
- 2026-07-30: Hardened the unified Telegram agent with explicit
  customer/flock/audit context invalidation, registry-only station schemas,
  safe missing-sector errors and a conservative additive sector backfill,
  `/new` context generations, ordered assistant/tool diagnostics, and an
  admin health/context view. Added a real `AuthProvider` approved-admin harness,
  Telegram-evidence-to-monitor integration coverage, and a scrollable compact
  macOS drawer. The SQLite v55-to-v56 path now performs a checked,
  row-preserving shadow-table rebuild so upgraded installations receive the
  same context/order checks and selected-context/reply foreign keys as fresh
  installations. The production-compatible migration is recorded on the
  ChickMark Supabase project as `20260730111832_agent_hardening`; it preserved
  all affected row counts, classified nine evidence-backed legacy flocks as
  Breeder, and left two ambiguous flocks unassigned.
  `telegram-hatchery-agent` v18 introduced these hardening changes with its
  existing custom webhook authentication and the current dependency bundle;
  that version also prevents pre-reset in-flight context writes, enforces full
  audit identity on summary reads, and bounds provider diagnostic metadata.
- 2026-07-30: Made the SQLite v54 unified-agent migration re-establish its
  additive v52/v53 table prerequisites before creating intake-session indexes.
  This preserves existing local data while repairing databases whose schema
  version 53 came from the former flock-monitoring development line. Surgical
  repair now adds that line's missing indexed farm and flock-placement columns
  before rebuilding current indexes. Normal app startup no longer injects the
  rejected dashboard demo fixture into the user's local database.
- 2026-07-29: Hardened the SQLite v55 agent-intake rebuild by temporarily
  removing unified-agent guards before replacing the session table, then
  restoring them once the schema is stable. Added missing flock sync columns
  required by the v51 poultry hierarchy repository and completed Arabic
  coverage for the generic Agent Monitor review workflow.
- 2026-07-28: Fixed selected-audit Hatch Analysis follow-ups in the Telegram
  agent. Infertile-egg and breakout questions now read the three breakout
  panel tables by the exact persisted audit session and authorized customer,
  instead of falling back to the audit header or an unsafe date-range search.
- 2026-07-28: Exposed scoped audit browsing to the unified Telegram agent.
  Authorized users receive numbered choices from a bounded page of recent
  audits (default 10, maximum 20); `truncated` signals either a larger valid
  result or that the 500-row bounded scan could not prove exhaustion. The
  selected audit is retrieved in a second opaque-ID summary call. Name text
  remains forbidden in ID arguments, while list/detail denials stay
  indistinguishable for unknown and out-of-scope records.
- 2026-07-28: Added scoped customer/flock name resolution to the unified
  Telegram agent. Duplicate customer names can now be disambiguated by an exact
  flock-name match, internal IDs are no longer injected into the model prompt,
  and the policy requires one clear question per reply, safe handling of
  ambiguous yes/no answers, flock resolution before hatchery/machine context,
  and consistent Arabic hatchery vocabulary.
- 2026-07-28: Completed the registry-driven agent implementation for all 18
  hatchery modules. Generic Dart/TypeScript adapters now validate nested and
  scalar values, calculate derived fields, map allowlisted panel columns, and
  drive the generic Agent Monitor review UI. Added SQLite v55 scope support and
  an authenticated admin-only Edge/RPC approval boundary with exact summary
  versions and atomic operational writes. The RPC verifies the active database
  role directly and does not depend on deprecated JWT-role helpers.
- 2026-07-28: Clarified the unified agent policy so questions about existing
  flock information stay on scoped read tools instead of being mistaken for
  data entry, and normalized final Telegram replies to plain text so Markdown
  markers never appear to customers.
- 2026-07-28: Removed the dormant fixed greeting/Pasgar conversation router.
  Every authorized Telegram turn now reaches only the unified AI runtime;
  registry catalogs include localized aliases and valid layers, adversarial
  tests enforce scope/confirmation boundaries, and assistant delivery is
  persisted as pending then marked delivered/failed so retries cannot rerun the
  model.
- 2026-07-28: Exposed old draft questions only through explicit scoped AI tools
  and added scope plus optimistic-state metadata to protected tool evidence.
  Legacy answers require both submission and question identity; ordinary chat
  never auto-binds to an old draft.
- 2026-07-28: Routed every authorized Telegram text and attachment through the
  unified AI runtime. Update receipts are checked before mutable writes,
  inbound turns receive a conversation-unique index, attachment bytes reach
  provider-native image/file inputs, and the exact model reply is delivered
  without a second phrase router or Pasgar controller. Provider failures use
  only the bounded infrastructure retry at the webhook boundary.
- 2026-07-28: Added the bounded unified AI provider/runtime loop. It supplies
  behavior policy, trusted scope/state, recent chat, attachments, and typed
  tools to one natural conversation turn, feeds tool results back to the model,
  and enforces serial execution, five-call/20-second limits, malformed-call
  rejection, and provider-safe failure statuses.
- 2026-07-28: Added the generic durable station-intake state machine and tools.
  Natural data-entry intent now creates an expiring proposal, explicit
  confirmation opens a registry schema, multi-field messages validate in any
  order, and one complete versioned summary is confirmed only at the end.
  Corrections use optimistic concurrency and submissions stop at admin review;
  legacy Pasgar row readers remain compatibility-only.
- 2026-07-28: Added customer-scoped AI read tools for customer/flock context,
  registry-allowlisted station records, deterministic metric aggregation, and
  record provenance. Reads retain missing values as null, cap and sort results,
  verify customer/flock ownership in depth, and share canonical calculation
  parity vectors with Flutter.
- 2026-07-28: Added the unified agent's server-side scope resolver and typed
  tool gateway. Every configured AI path now fails closed unless the Telegram
  staff link resolves to its enforced customer/admin scope; unknown and
  out-of-scope entities share the same denial shape. Tool calls use bounded
  JSON contracts, server-injected scope, five-call/100-row/366-day limits, and
  sanitized evidence without database credentials or raw table access.
- 2026-07-28: Replaced direct Telegram-user approval with an admin-only scope
  assignment sheet. Customer access now requires one selected customer;
  agent-admin access is an explicit all-customer grant. Agent Monitor lists
  allowed users with their enforced scope and supports reassignment or
  revocation, with bilingual labels and repository/provider validation.
- 2026-07-28: Added the v54 unified-agent persistence boundary. Telegram staff
  links now enforce customer/admin scope, conversations preserve turns and
  immutable tool evidence, visits group sequential station intakes, and intake
  sessions carry visit and optimistic-version references. Existing Pasgar
  sessions are backfilled without deletion. The admin app pulls server-authored
  evidence read-only, while RLS limits it to approved admins and service-role
  Edge execution.
- 2026-07-28: Added the canonical versioned AI station registry and deterministic
  Dart/TypeScript generator. Registry contracts now cover 18 Breeder hatchery
  modules across every active panel table, with localized vocabulary,
  validation metadata, completion requirements, read measures, and persistence
  mappings. Pasgar retains its seven explicit sample-bound inputs.
- 2026-07-28: Kept Telegram greetings and ordinary mission chat conversational
  when a legacy hatchery draft still has open questions. The bot no longer
  responds to greetings such as "Hi", `صباح الفل`, or `الو` by dumping the
  pending numbered form; the draft remains untouched and later data-bearing
  answers still use the existing safe router.
- 2026-07-28: Hardened OpenAI/OpenRouter Responses API parsing so Telegram
  mission chat and Pasgar interpretation accept only assistant `message`
  `output_text` content. Reasoning items are ignored and can no longer be sent
  to staff as customer-facing bot replies.
- 2026-07-28: Added schema-driven conversational Pasgar intake for approved
  Telegram staff. The bot accepts natural Arabic, English, and mixed-language
  measurements in any order, asks focused clarification when uncertain, saves
  valid progress silently, and requests confirmation only once after presenting
  the complete summary. Corrections create a new summary version. Added v53
  local/remote persistence and sync, idempotent admin approval into Chick
  Quality, and a full Agent Monitor review/edit/approve/reject/evidence
  workspace.
- 2026-07-28: Hardened local sync tombstones against older browser database
  shapes by detecting camelCase versus snake_case tombstone columns at runtime.
  Manual/background sync now keeps working when an IndexedDB cache still has
  `synced_at`/`deleted_at`, allowing Telegram agent drafts pulled from Supabase
  to appear in Agent Monitor.
- 2026-07-28: Added bounded Arabic mission chat for approved Telegram staff
  greetings/help messages without creating drafts, kept unapproved senders in
  the access flow, made pending-question greetings return a friendly reminder,
  and accepted relaxed numbered answers such as `1 30`.
- 2026-07-27: Added Telegram staff self-registration for unknown bot senders.
  Unknown senders now become pending staff links with Telegram ID, chat ID,
  username, and display name metadata; Agent Monitor shows pending requests to
  approved admins, and admin approve/reject decisions mark staff links allowed
  or revoked for future Telegram messages.
- 2026-07-27: Hardened Telegram staff-link defaults so newly inserted staff
  links default to `pending`, and added deterministic labeled-text extraction
  for routine Telegram messages so structured hatchery text can become a draft
  without an AI provider call.
- 2026-07-27: Switched testing-mode OpenRouter extraction to default to
  `openrouter/free` and retry paid-model 402 credit failures once with the free
  router.
- 2026-07-27: Cleaned Telegram staff prompts to Arabic-only messages that hide
  draft references and internal field keys for normal one-draft flows, add
  numbered choice lists for resolvable flock/customer/hatchery questions, and
  accept option-number replies.
- 2026-07-27: Fixed Supabase upsert payload preparation so local sync metadata
  is removed before snake_case conversion; manual/background sync no longer
  falls back to rejected camelCase fields such as `customerId` on remote tables.
- 2026-07-27: Fixed local debug-bypass sign-out so the development auditor is
  cleared for the current session, later cached-token checks do not immediately
  recreate it, and `/login` uses the real login route instead of the main shell.
- 2026-07-27: Aligned Agent Monitor navigation, data loading, and Telegram
  pause/resume controls with admin-only agent-table RLS. Auditors and customers
  no longer receive the Agent destination, and provider guards prevent
  unauthorized agent reads and local pending-sync writes.
- 2026-07-27: Resolved Telegram hatchery draft customer/flock IDs through
  unique normalized hierarchy matches, retained missing or ambiguous
  identities as bilingual review warnings/questions, linked sole customer
  hatcheries, and replaced raw Agent Monitor UUID entry with scoped hierarchy
  selectors that also repair uniquely matched existing drafts.
- 2026-07-27: Wired Telegram draft ingestion to count-derived historical
  hatchability warnings, unique exact customer/flock resolution, the configured
  3-point default threshold, nearest-age BMK context for rising results, and
  bilingual missing-flock-age questions. Warning enrichment is server-owned;
  pulled rows retain its evidence without local rewrite.
- 2026-07-27: Routed authorized Telegram staff replies to same-chat open
  hatchery-agent questions, added deterministic numbered/row answer matching
  with bilingual clarification, persisted question answers, copied validated
  values into related draft fields, kept completed replies in admin review,
  and added backend-only update receipts for answer-replay idempotency.
- 2026-07-27: Added admin-only hatchery draft row editing, rejection with an
  audited reason, atomic approval into final hatchery daily records,
  batch-status recalculation, and startup push/pull coverage for the
  hatchery-agent operational tables.
- 2026-07-27: Added the admin-only Agent Monitor tab with persisted Telegram
  pause/resume control, responsive submission and draft evidence review,
  question/answer and audit-history display, separate confidence and warning
  presentation, bilingual copy, and role-gated navigation.
- 2026-07-27: Added the Telegram hatchery-agent Edge Function with verified
  webhook ingestion, allowed-staff enforcement, idempotent update handling,
  Telegram text/photo/document loading, strict OpenAI structured extraction,
  multi-row draft creation, hatchability calculation, confidence routing,
  bilingual missing-data questions, and durable failure status. All backend
  tests use injected fakes.
- 2026-07-27: Added the v52 hatchery-agent data foundation with additive local
  and Supabase tables, immutable storage models, atomic draft-graph repository
  writes, settings and historical comparable queries, operational sync
  allowlisting, admin-only remote RLS, tenant-scope validation, and
  Telegram-token-shaped secret scanning.
- 2026-07-24: Added customer poultry-structure management for concurrent
  Breeder, Broiler, and Layer membership, single-sector farms, nested houses,
  and the Breeder-only hatchery gate. Added Performance as a staff main-shell
  destination while preserving the customer-role navigation boundary.
- 2026-07-24: Added localized diagnostic visit and corrective-action workflow
  screens. Daily evidence remains read-only during visits; investigations,
  findings, staff explanations, explicit cause decisions, action ownership,
  implementation confirmation, and before/after KPI decisions are editable.
- 2026-07-24: Added the responsive Broiler Performance workspace with
  customer/farm/flock/date scope, multi-house SQLite aggregation, current KPI
  cards, daily trend charts, active concerns, visits/actions, provenance and
  verification badges, exact objective-source labels, and a daily quick-entry
  path.
- 2026-07-24: Added corrective-action KPI follow-up with immutable baseline and
  evaluation windows, implementation confirmation, valid scoped observations,
  all four effectiveness outcomes, explicit reasons, and persisted evaluator
  identity/time.
- 2026-07-24: Added the diagnostic farm-visit evidence layer for performance
  concerns: immutable pre-visit briefing snapshots, selected houses, suggested
  and manual investigations, measurements and observations, staff explanations,
  attachment references, and explicit suspected/probable/confirmed/ruled-out
  cause assessment states.
- 2026-07-24: Added the Home `Incomplete Visits` section. It lists every
  customer-visible in-progress visit with station progress, remaining stations,
  and an explicit completion reminder. `Complete now` resumes the first
  unfinished station directly, and Home reloads the list after the workflow
  closes.
- 2026-07-21: Stabilized Dashboard background refresh and scrolling. Overlapping
  refresh requests are now serialized/coalesced, existing Lab Analysis content
  remains mounted while refreshed data is queried, stale filter-scope loads are
  ignored, and the Dashboard keeps one scroll controller so refreshes no longer
  make the reader jump between Lab Analysis and adjacent sectors.
- 2026-07-21: Completed Arabic localization coverage for the new Lab Analysis
  report workflow, bacterial-culture interpretations, and longitudinal trend
  labels.
- 2026-07-19: Restored mobile multi-customer sync by removing the obsolete
  production trigger that silently cancelled every non-`الغريب` customer
  insert. Parent uploads now verify returned Supabase rows, and local customer,
  hatchery, flock, audit-session, and panel writes automatically request a
  debounced sync that also retries on connectivity changes and app resume.
- 2026-07-19: Added admin-issued, username-based customer accounts. Admins can
  create an approved read-only Supabase Auth identity and assign it to one
  existing customer through Settings > User access; the privileged user-create
  operation lives in a caller-verified Edge Function. Customer accounts see
  only Dashboard plus account/sign-out Settings, are locked to their assigned
  customer/hatcheries/flocks, cannot create dashboard actions, and run both
  startup and background sync in pull-only mode. Added admin-assisted password
  reset for username accounts and fail-closed clearing of dashboard state when
  the active identity or assigned tenant changes.
- 2026-07-19: Hardened Supabase authorization by moving RLS helpers out of the
  exposed API schema, requiring approved admin status, revoking anonymous table
  and trigger-function grants, and tenant-scoping deletion tombstones with a
  server-derived immutable customer and snapshotted audience. Explicit offline
  login no longer accepts a cached Supabase profile as proof of an entered
  password; remembered valid sessions still resume during startup. Strengthened
  live Auth and registration rules to 12 characters with lowercase, uppercase,
  digit, and symbol requirements, plus recent-session and current-password
  checks for password changes. Registration counts user-perceived Unicode
  characters consistently, and disposable PostgreSQL integration checks verify
  the effective helper, policy, and function-grant state across migrations.
- 2026-07-20: Reorganized Lab Analysis entry into test-aware report, result, and
  source-document sections; replaced known specimen, scope, analyte/target,
  kit-manufacturer, antigen, organism, antimicrobial, and interpretation text
  fields with controlled choices while leaving the actual laboratory name
  editable; made ELISA specimen rows explicitly
  optional; and added ELISA longitudinal GMT/CV/positivity charts, pooled-repeat
  separation, latest snapshot callouts, and a house/date heatmap to Dashboard.
  Dashboard alert/watch KPIs now count result groups instead of every sample
  row. Extended the private photos-bucket RLS policy so customer-authorized Lab
  Analysis report rows can open their attached PDF and new uploads can use the
  standard customer-scoped lab-report path.
- 2026-07-20: Split bacterial culture from antibiotic sensitivity in Lab
  Analysis. Sensitivity now records antimicrobial S/I/R results only, while the
  new Bacterial Culture tab records the isolation method, tested organisms, and
  positive/negative or isolated/not-isolated findings, based on the supplied
  Salmonella isolation report.
- 2026-07-19: Aligned the iOS Runner deployment target with the Podfile's iOS
  15.5 minimum and disabled parallel CocoaPods framework code signing for
  Release builds so local device release builds complete reliably before
  installing fresh provisioning profiles.
- 2026-07-16: Redesigned saved Lab Analysis results as compact ChickMark cards.
  ELISA opens with sample size, mean, GMT, CV%, positive/negative counts, and
  minimum/maximum titers; large numbers use thousands separators, while full
  specimen rows are collapsed under an expandable Sample details control.
- 2026-07-11: Resumed Chicks visit sessions now prefer the live Flock Manager
  breed and age over stale session snapshots, and Chick Weights recalculates and
  persists BMK age plus BMK chick weight from the matching breed benchmark.
- 2026-07-05: Added a destructive delete action to each editable Customers-list
  card. The action confirms the named customer, runs the existing local cascade,
  immediately attempts foreground Supabase tombstone sync, and reports whether
  the cloud delete synchronized or remains pending for a later sync.
- 2026-07-05: Made dashboard comparisons BMK-age-first and data-aware. Each
  scoped sector now defaults to a separate-age table with an equal-age average,
  supports House/Machine trends across ages, starts pooled when one age is
  selected, and exposes only sibling-valid House, Machine, Trolley, or Tray
  controls. Added missing-data handling, multi-level comparisons, and matching
  table/chart state; applied the same one-house rule and age table to the bespoke
  Egg Quality sector.
- 2026-07-05: Moved Hatch Analysis breakout photo capture into every Fresh,
  Candled, and Residue metric row; saved photos with metric-specific JSON and
  SQLite identities; kept thumbnails editable in-row; cleaned replaced/removed
  photo rows through sync tombstones; and kept the dashboard breakout photo
  grid loading both item-scoped and legacy evidence.
- 2026-07-05: Refreshed an already-mounted Dashboard after successful sync so
  downloaded breakout photos replace stale in-memory paths without requiring a
  manual pull-to-refresh or filter change.
- 2026-07-05: Preserved the dashboard Govee sector's collapsed state when it is
  disposed off-screen and recreated during scrolling.
- 2026-07-04: Preserved dashboard station-card collapse state while scrolling
  and through pull-to-refresh loading during the current Dashboard visit.
- 2026-07-04: Repaired stale evidence-photo paths after iOS app-container path
  changes by reconciling filenames against the current documents directory,
  and allowed cloud pull/download to recover rows whose local file is missing.
- 2026-07-03: Added the selected flock's name, current age, breed, and entrance
  date to the dashboard filter card and moved that card into the scrolling
  dashboard content so it no longer stays frozen while the user scrolls.
- 2026-07-03: Completed the Arabic UI copy audit across administration, auth,
  customers, visits, poultry audit stations, BMK, Dashboard, Govee, Home, and
  Settings; localized input decorations, validators, tooltips, semantics, and
  dynamic operational messages while preserving entered names and values;
  corrected directional RTL spacing/alignment and the navigation drawer shape;
  added Arabic font fallbacks and prevented the Home last-audit date from being
  truncated; and added regression tests for RTL, static strings, dynamic copy,
  tooltips, fonts, and the long Arabic date layout.
- 2026-06-26: Added English/Arabic app localization, Settings language
  selection, local persistence for the selected language, Flutter localization
  delegates, automatic Arabic RTL directionality, and a central Arabic
  translation catalog for shared user-facing text.
- 2026-06-26: Expanded the Arabic catalog for Home and Dashboard operational
  labels, dashboard filter labels, triage alerts, and rich text spans.
- 2026-06-28: Expanded the Arabic catalog for remaining Home focus, sync,
  conflict, Dashboard scope, and Govee labels, including dynamic count/name
  messages.
- 2026-06-23: Added root auth-state navigation so logout resets the app back to
  `/login`, and covered Remember me loading, saved-email persistence, clearing,
  remember-session forwarding, and phone-width Remember me row layout with login
  screen tests.
- 2026-06-23: Simplified guided EST/CVT capture to a serial photo-first flow
  with one Take photo action, Done-only footer navigation, display-only
  photo-backed station grid cells, and tapped-cell edit routing through the
  attached-photo capture screen.
- 2026-06-24: Moved guided temperature capture completion to a top-right Done
  action, changed the footer primary action to Capture, and fixed Retake so a
  saved point returns to capture-ready state. Added a recorded-photo strip,
  per-cell photo badges, retaking state text, and automatic manual-entry focus
  after capture.
- 2026-06-24: Added startup photo download sync for pulled Supabase photo rows
  and remote storage-object cleanup for synced photo deletes, so evidence can
  appear on other devices and deleted photo rows remove their backing bucket
  objects.
- 2026-06-22: Added `bmk_operational_standards` with seeded global operational
  BMKs, hatchery-specific overrides, an Operational BMKs reference sector, and
  an Admin editor with global/hatchery scope selection.
- 2026-06-25: Organized the Operational BMKs reference sector into Egg, Chicks,
  Hatch Results, Setters, and Hatchers categories and added a source citation
  dialog from the sector header.
- 2026-06-25: Added per-item Operational BMK citation actions and source URLs
  to the `bmk_operational_standards` model, schema, and seed data.
- 2026-06-25: Moved Operational BMK citation icons beside each metric label and
  added per-metric citation photo attachment through `sourcePhotoPath`.
- 2026-06-25: Removed Operational BMK category/header citation actions, made
  external source links open from each metric dialog, stopped showing internal
  links for ChickMark operational defaults, and added cloud-backed source photo
  replace/delete plus zoom preview.
- 2026-06-25: Persisted EST/CVT readings with their selected `°F`/`°C` unit,
  preserved legacy unit fallbacks, and made dashboard EST evidence display the
  saved unit instead of assuming Celsius.
- 2026-06-25: Changed dashboard Egg Quality to one Pool-plus-house comparison
  sector with default-selected Pool/house chips and a chart/table toggle, instead
  of separate selected-house cards plus a nested `Compare houses` reveal.
- 2026-06-25: Tightened the dashboard Egg Quality chart layout with wrapping
  metric chips, compact Act-vs-BMK paired bars for normal house counts, and a
  dashed average reference line.
- 2026-06-23: Added Hatch Analysis breakout sample photo capture, saving new
  captures under the active breakout panel and showing recorded breakout photos
  in the dashboard Scopes grid. The dashboard Hatch breakout area now shows only
  breakout types with real recorded rows instead of always showing Fresh,
  Candled, and Residue tabs.
- 2026-06-22: Added a `°F`/`°C` toggle to the dashboard Govee Environmental
  Readings sector and made its cumulative temperature metric follow the shared
  app temperature unit.
- 2026-06-22: Removed thermometer OCR from EST/CVT capture, deleted the unused
  ML Kit OCR service/tests/dependency, and converted Egg EST, Setter EST,
  Chicks CVT, and Hatcher CVT to a guided manual photo capture flow that saves
  typed readings plus evidence photos, shows photo-backed station grid cells,
  and reopens tapped cells in the attached-photo edit flow.
- 2026-06-22: Scoped debug seed data to `الغريب` plus one dashboard test
  customer, removed older dummy customer seeds, and added deterministic
  five-reading Govee captures for the dashboard places.
- 2026-06-22: Gated the app-wide floating Govee shortcut on entering the main
  app shell so it remains hidden during login, registration, pending approval,
  and startup sync even when the user already has Govee permissions.
- 2026-06-13: Tuned thermometer OCR for the red seven-segment device by
  isolating the large display row, adding red/inverted/adaptive preprocessing,
  preserving detected units, warning on selected-unit mismatches, and adding
  Fahrenheit-default `°F` / `°C` controls to Egg EST, Setter EST, Chicks CVT,
  and Hatcher CVT without changing their canonical stored units.
- 2026-06-13: Restored the in-app ChickMark keypad for adaptive native iOS
  audit numeric fields after the focus-preservation and stable-station fixes,
  while leaving ordinary text fields on the native iOS keyboard.
- 2026-06-13: Kept the narrow audit-session footer actions in one compact row
  with protected space for the floating Govee action, and changed the Hatch
  Analysis Breakout Type and metadata cards from fixed heights to matching
  minimum heights so wrapped content can expand without overflow or infinite
  layout constraints.
- 2026-06-12: Preserved the mounted audit station subtree while keyboard focus
  hides session chrome, preventing active numeric fields and modal sheets from
  rebuilding with station-owned focus nodes that were already disposed.
- 2026-06-12: Changed audit keyboard dismissal from raw pointer-down handling
  to resolved background taps, preventing iOS text fields from losing focus
  during the same press that opens the native keyboard.
- 2026-06-12: Switched adaptive native iOS audit numeric fields from the
  in-app overlay keypad to the system numeric keyboard, preventing focused
  fields from scrolling into view without presenting an input surface while
  preserving Android custom-keypad and desktop physical-keyboard behavior.
- 2026-06-12: Registered audit photo buttons across Egg, Chicks, Hatch
  Analysis, Setters, and Hatchers with explicit panel field keys, and mapped
  Hatch Analysis breakout photos to the active breakout table so saved captures
  enter the same local photo-sync queue as their screen JSON paths.
- 2026-06-12: Hardened shared debug-log sanitization for JWTs, Supabase
  publishable/secret keys, and token/password/API-key values in query/form and
  JSON-style messages while preserving debug-build-only logging.
- 2026-06-12: Added a shared keyboard-aware audit station scroll wrapper and hid
  fixed visit chrome, including the Govee readings card and Next Station footer,
  while station inputs are being edited on phone layouts.
- 2026-06-12: Fixed Hatch Analysis Machine scope activation from pooled House
  scope so the machine row no longer opens the House entry or House remove
  controls; the House card stays visibly pooled until House scope is explicitly
  added.
- 2026-06-12: Made the Egg and Chicks weight-entry modal sheets reserve
  scrollable bottom space for the in-app numeric keypad so lower weight cells
  remain fully reachable instead of sitting partly behind the keypad, and kept
  the keypad open while users touch or drag within the sheet. Active lower rows
  now scroll above the keypad overlay after entry or keypad navigation.
- 2026-06-11: Made the Govee Records tab merge completed floating-panel saves
  into its open list immediately and sort visit-day groups by latest update
  time, so newly recorded current-date captures are not hidden behind
  future-dated demo records.
- 2026-06-11: Hardened mobile UI responsiveness by truncating long shared
  gradient app-bar titles and status badges, stacking the audit-session footer
  actions on narrow phones, ellipsizing Select Stations row labels, and keeping
  audit/Govee filter dropdown labels constrained inside their fields.
- 2026-06-11: Hid the read-only Govee capture date field from the active scope
  picker while keeping the provider-owned capture date behavior unchanged.
- 2026-06-11: Gated the live Govee card and preview charts on latest-reading
  freshness so sensors with no live update for more than 30 seconds show empty
  Temp/RH metadata and no stale chart trend even if BLE/GATT flags lag, added an
  inline scan/connect activity spinner, and kept Customer and Hatchery controls
  visible for Setter/Hatcher Govee measure scopes.
- 2026-06-11: Refactored the compact Govee live-card settings sheet into a
  private part, shared the device-name and connection-status display helpers
  between the card and sheet, disabled duplicate compact-card scan taps while a
  scan is already active, and capped diagnostics text to prevent overflow.
- 2026-06-04: Enhanced thermometer OCR with primary-first fallback
  preprocessing, confidence-scored reading consensus, a shared lower-CPU
  auto-scan cadence, and testable OCR-reader injection while leaving correction
  telemetry out of scope.
- 2026-06-03: Debounced Chicks weight-sheet calculation commits so keypad entry
  updates the draft after a short pause or sheet close instead of rebuilding the
  full Chicks station on every tap.
- 2026-06-03: Changed Hatch Analysis Trolley scope so adding a trolley attaches
  it to the pooled breakout sample and keeps the Tray scope on `Pool`. The Tray
  scope only enters tray comparison when Tray scope `+` is pressed, and the first
  tray inherits the active trolley. Removing a trolley drops its pooled sample
  when other trolleys remain, or reverts to plain `Pool` when it is the last one.
- 2026-06-03: Tightened Egg panel persistence so `egg_storage` rows are created
  only after EST data is entered, and `egg_quality` rows are created only after
  Egg Weights & Uniformity or Egg Shell Quality UV data is entered.
- 2026-06-03: Fixed Chicks machine-scope panel forms so switching setter/hatcher
  machine chips reloads that machine's own Pasgar, YFBM, CVT, PM Necropsy, and
  Culled Chicks Analysis draft values instead of leaving stale form-controller
  values from the previously selected machine visible.
- 2026-06-03: Changed Hatch Analysis Machine scope additions so the first
  machine stays prefix-only `SH`, while later machines in the same house or
  pooled context default to numbered `S1H1`, `S2H2`, etc. chips with matching
  numeric Setter/Hatcher fields.
- 2026-06-03: Added a bottom `Clear` action to visit station footers. Confirmed
  clears delete that station's saved panel rows for the active session, reset
  fields/scopes/samples, and remove the station from completion progress.
- 2026-06-03: Deferred audit-session provider clearing and station-selection
  loading reset until after the route-pop frame so backing from a station to the
  main station-selection screen does not mutate active `LayoutBuilder` layout.
- 2026-06-12: Allowed a blank/default Hatchers station to save as an
  explicitly incomplete station, while still clearing metadata-only
  `hatcher_optimizing` panel rows and leaving the visit in progress.
- 2026-05-26: Kept Hatch Analysis `Trolley scope` independent from House and
  Machine scope, so users can leave both pooled and start comparison at trolley.
- 2026-05-26: Counted Hatch Analysis `Total eggs set` as meaningful panel data
  so Scope Grain Expansion writes open house and machine paths instead of
  discarding them until a hatched/cull/dead count is entered.
- 2026-05-26: Kept Hatch Analysis station completion separate from panel
  persistence so the default `Total eggs set` alone does not complete the
  station.
- 2026-05-26: Removed the Egg Quality `Machine scope` card from the Egg station
  screen so Egg quality sampling exposes only the House scope control.
- 2026-05-26: Fixed Hatch Analysis / Egg Breakouts panel persistence to use
  Scope Grain Expansion in the database: pooled saves one blank-hierarchy row,
  house saves one row per house, machine saves one row per house-machine path,
  trolley saves one row per house-machine-trolley path, and tray saves only full
  leaf paths while pruning parent aggregate rows.
- 2026-05-26: Changed Hatcher Chick Panting so blank samples no longer
  preselect No, unanswered model values remain null, and either explicit Yes or
  No counts as core data for station completion.
- 2026-05-26: Stopped Hatch Analysis Trolley and Tray scope chip selection from
  auto-scrolling to the tray entry fields; chips still switch the active
  trolley or tray in place.
- 2026-05-25: Aligned Egg Breakout panel persistence with the Egg Quality
  hierarchy model. Breakout rows now save at the deepest active scope
  (`Pool`, `House`, `Machine`, `Trolley`, or tray leaf), Candled/Residue schema
  includes Trolley as a real layer, and tray saves prune stale parent aggregate
  rows from the same session/table.
- 2026-05-25: Added a Hatch Analysis Trolley scope card under Machine scope.
  Trolleys are owned by the active machine, added trays inherit the selected
  trolley, and Candled/Residue tray cards now keep trolley out of the tray-local
  header fields.
- 2026-05-25: Added station-specific completion validation to the visit exit
  path. Incomplete stations can be skipped after confirmation without being
  marked complete, and blank/default-only station rows are removed instead of
  implying progress.
- 2026-05-25: Restored Hatcher multi-machine resume so all saved Hatcher rows
  reopen as machine-scope chips and can be edited independently, including
  machine-specific CO2 and incubation values.
- 2026-05-25: Kept Hatch Analysis House, Machine, and Tray scopes explicit:
  adding Machine or Tray scope no longer creates synthetic parent scope.
- 2026-05-25: Fixed Egg Breakout tray-row persistence so explicit saved tray
  hierarchy is written to the breakout panel tables, while hidden draft
  hierarchy still remains blank until the matching scope is active.
- 2026-05-25: Cleaned the Setters incubation-age sample selector with `Pool` /
  `Day N` chips, duplicate-day disambiguation, compact icon actions, and active
  EST sample payload sync; Hatcher incubation age/hour controls now use numeric
  fields.
- 2026-05-23: Changed the visit-session progress strip so the active station
  circle uses a small white dot marker on blue, leaving green checks for
  completed/reached past stations.
- 2026-05-23: Changed Hatch Analysis / Egg Breakouts Tray scope comparison to
  render only the active tray entry panel under the tray chips instead of
  stacking every tray card in the scroll view.
- 2026-05-23: Updated Hatch Analysis / Egg Breakouts scope controls so House
  scope starts as prefix-only `H`, Machine scope starts as prefix-only `SH`,
  both active hierarchy cards expose remove actions that return to pooled mode,
  and Breakout Samples uses a dedicated Tray scope where `Pool` stores aggregate
  counts while tray comparison still saves one panel row per physical tray.
- 2026-05-23: Removed persisted `bmkAgeDays` from panel tables. BMK day values
  are still calculated in memory for benchmark lookups, while stored panel
  context keeps current flock age weeks, storage period, and rounded BMK weeks.
- 2026-05-23: Fixed Chick Weights House scope so newly added or blank house
  samples no longer inherit the previous active house's entered weight grid,
  sample size, average, uniformity, or C.V. Saves now keep each `chick_weights`
  row tied to that house sample's own entered values.
- 2026-05-23: Fixed Chick Weights House scope removal so the first active `H`
  sample exposes the remove action and removing it returns the weights card to
  pooled `Pool` state.
- 2026-05-22: Fixed panel row upserts when a Chicks/Egg scoped sample returns to
  the pooled hierarchy while an older pooled row already exists. Saves now merge
  into the existing hierarchy row and queue a tombstone for the stale scoped row
  id, avoiding `idx_chick_quality_unique_row` unique-index failures.
- 2026-05-22: Replaced the shared in-app ChickMark logo asset with the
  cap-and-glasses chick mark, removed the checkerboard/white square background
  by saving it with PNG transparency, regenerated web/Android/iOS/macOS launcher
  icons from the same mark, and added optional bob-and-glint motion for large
  auth/startup logo placements.
- 2026-05-22: Restored the visit-session progress strip on Hatch Analysis &
  Egg Breakouts so its station check marks appear like the other station
  screens.
- 2026-05-23: Added the station removal button to saved rows on the resumed
  Select Stations visit-order list while preserving row taps for review/edit.
- 2026-05-23: Kept visit-session footer navigation on `Next Station` for
  non-final completed/review stations, reserving `Save` for the final station.
- 2026-05-20: Added same-context visit resume for station selection. Matching
  in-progress sessions now reopen with saved station badges, unsaved stations
  can be added before continuing, Home and Audits route active visits through
  station selection, and completed visits open station screens first with a
  separate final-results action.
- 2026-05-23: Fixed resumed Egg stations so `egg_quality` house and
  setter/hatcher hierarchy rows hydrate the House/Machine scope chips even when
  `egg_storage` is only a pooled row. Egg sample synchronization now applies
  generated house labels only to house samples and generated machine labels only
  to machine samples, preventing machine children from being reassigned or
  relabeled during resume/save.
- 2026-05-23: Fixed Egg Quality Machine scope removal from a selected House
  scope. Visible machine children now expose the remove action even when the
  house chip is active, and removal deletes that machine child while preserving
  the selected house.
- 2026-05-23: Fixed Egg Quality parent scope selection so selecting a house with
  machine children activates the first machine child instead of leaving
  setter/hatcher null, and saving now prunes parent-only house rows once machine
  leaf rows exist under that house.
- 2026-05-23: Fixed Egg Quality active machine removal so deleting `S1H1` under
  `H1` returns to the `H1` context instead of falling through by list position
  to the next house such as `H2`.
- 2026-05-23: Changed first Egg Quality scope activation to use the same
  prefix-only placeholders as later scope rows. Converting pooled Egg Quality to
  House scope now creates only `H`, converting pooled Egg Quality to Machine
  scope now creates only `SH`, and removing the only active scope returns the
  station to `Pool`.
- 2026-05-23: Changed newly added Egg Quality scope rows to start as prefix-only
  placeholders. New House rows show `H` with a blank House field, new Machine
  rows show `SH` with blank Setter/Hatcher fields, and entering values updates
  the chip labels such as `H2` or `S3H4`.
- 2026-05-23: Stabilized Egg Quality House/Setter/Hatcher identity fields so
  entering a House number keeps the field active during provider rebuilds, while
  idle fields still sync metadata changes back into the visible input.
- 2026-05-23: Deleted removed scope sample panel rows before re-saving retained
  scopes, preventing reindexed House/Machine labels from reusing a deleted
  scope's saved row id.
- 2026-05-23: Fixed Egg Quality House-field edits while a Machine child is
  active. Renaming the selected House now updates the parent House sample and
  cascades the new house key to its Machine children instead of orphaning the
  active Machine scope.
- 2026-05-23: Aligned first Chicks scope activation with Egg placeholder scope
  behavior. Chick Quality Machine scope now starts with a single `SH`
  placeholder, and Chick Weights House scope starts with a single `H`
  placeholder instead of adding generated `S1H1`/`H1` rows beside them.
- 2026-05-23: Fixed Chick Quality Machine scope removal so the first active
  `SH` sample exposes the remove action and removing it returns the card to
  pooled `Pool` state.
- 2026-05-23: Restyled the embedded Chicks Pasgar form to remove nested card
  boxes, group defect rows in one divided list, and show the final score as a
  compact summary row.
- 2026-05-23: Removed the embedded Chicks CVT inline °F/°C toggle. CVT grid
  entry now stays in °F while retaining the 103-105°F / 39.4-40.6°C target
  reference and guided capture action.
- 2026-05-23: Moved the Chicks PM Necropsy fixed Gizzard Erosions row to the
  end of the built-in lesion checklist before custom Others rows.
- 2026-05-23: Made Setter/Hatcher panel-table hierarchy machine-first:
  `setter_optimizing` now uses only `setter -> trolley -> tray`, and
  `hatcher_optimizing` now uses only `hatcher -> trolley -> tray`; existing
  current databases drop the old unrelated house/opposite-machine/position
  hierarchy columns and rebuild the unique-row indexes.
- 2026-05-23: Updated Hatch Analysis Candled/Residue hierarchy controls to use
  Egg/Chicks-style `House scope` and `Machine scope` cards. The House card owns
  the House field, while the Machine card owns the Setter and Hatcher fields.
- 2026-05-20: Replaced Chicks Quality sampling/Machine ID controls with an
  Egg-style `Machine scope` card. Adding machine scope now generates
  setter/hatcher samples such as `S1H1` and `S2H2`, and Chick Quality panel
  saves persist `setter_hatcher` scoped rows with generated setter/hatcher
  hierarchy values instead of UI-only labels.
- 2026-05-20: Stopped Egg storage upside-down tray totals, Quality Storage Days,
  and auto BMK age/weight values from creating Egg Quality rows by themselves.
  Explicit clean UV inspections still persist by marking the UV tray as
  quality-entered when the quality controls are edited.
- 2026-05-19: Prevented untouched Egg station saves from creating metadata-only
  `egg_storage` or `egg_quality` rows. Blank storage defaults still feed draft
  and sample metadata for BMK calculations, and auto BMK age/weight can still be
  displayed, but panel persistence now skips and clears Egg panel rows when no
  corresponding storage or quality field has been entered.
- 2026-05-19: Redesigned the BMK reference screen into a denser operational
  dashboard with compact Reference/Admin mode controls, custom breed and
  breakout type selector bars, labeled age controls, and responsive benchmark
  metric tiles. Phone-width BMK sectors now use two-column metric grids and
  one-row breakout type controls so the whole sector can be scanned without
  long vertical scrolling; per-metric decorative symbols were removed from
  Breed Benchmarks and Egg Breakout BMK value cards, the Egg Breakout selector
  is text-only, and the Egg Breakout sector header now uses the standard egg
  symbol.
- 2026-05-19: Split Egg Storage and Egg Quality storage periods. Egg Storage
  keeps its own storage-room days for storage/EST persistence, while Egg Quality
  now has a dedicated Quality Storage Days entry that drives Egg Quality BMK age,
  BMK egg-weight lookup, mapper patches, and `egg_quality.storagePeriodDays`.
- 2026-05-19: Defaulted blank storage-day values to `0` for Egg, Chicks, and
  Hatch Analysis / Egg Breakout station metadata, plus saved rows that have
  other meaningful panel data, so BMK age continues calculating when storage is
  left untouched or missing in older rows.
- 2026-05-19: Added Hatcher machine temperature and RH setpoint fields, storing
  them in the hatcher audit draft and `hatcher_optimizing` panel row.
- 2026-05-19: Removed the Setters `Setter settings` title and changed Turning
  Angle and CO2 Level to always show larger blue labels on the field outline.
- 2026-05-23: Added a Setters Turning Angle camera action aligned beside the
  entry field.
- 2026-05-23: Changed the Setters selector to the existing Egg-style `Machine
  scope` card with circular icon actions while keeping its chips S-only, such
  as `S1` and `S5`, without any `H` suffix.
- 2026-05-23: Moved the Setters setter-number entry into the Machine scope card
  and defaulted blank first/new setter machine samples to `S`.
- 2026-05-25: Removed the Setters machine-screen actual temperature and actual
  RH entry fields from the setup card, leaving only the Fahrenheit and RH
  setpoint fields.
- 2026-05-23: Removed the Setters EST sample breed picker so samples only show
  incubation age, incubation hours, readings, photos, average, and CV inputs.
- 2026-05-23: Replaced the Setters EST sample tabs with an incubation-age
  selector that shows one sample as `Pool`, manages samples with plus/minus
  icon actions, and keeps EST grids isolated per incubation-age sample.
- 2026-05-23: Changed the Hatchers selector to the Setters-style `Machine
  scope` card, moved Hatcher number into that card, and defaulted blank
  first/new hatcher machine samples to `H`.
- 2026-05-23: Restyled Hatcher Chick Panting from a full-width segmented
  control to compact Yes/No chips with the photo action in the card header.
- 2026-05-23: Changed Hatch Analysis / Egg Breakouts House scope chips from
  `House 1` wording to compact `H1`, `H2`, etc. labels.
- 2026-05-23: Changed Hatch Analysis / Egg Breakouts hierarchy controls to show
  `Pool` in House scope and Machine scope until activated, and kept unactivated
  pooled tray rows from saving hidden House/Setter/Hatcher hierarchy.
- 2026-05-19: Added Setters machine-screen relative humidity setpoint and
  actual entry fields, storing them in the audit draft and setter panel
  persistence beside the existing Fahrenheit setpoint/actual readings.
- 2026-05-19: Removed the Short beak item from Chicks Culled Chicks Analysis.
  The defect catalogue no longer renders it in the UI, encodes it into
  `culledChicksAnalysisJson`, or decodes older saved `head_short_beak` rows.
- 2026-05-22: Changed Chicks Culled Chicks Analysis to use total egg set
  (default 19,200) as the denominator and persist defect percentages only in
  `culledChicksAnalysisJson`, with no saved defect row counts.
- 2026-05-22: Standardized user-facing app dates to left-to-right
  `dd-MM-yyyy` labels while preserving ISO date keys for persistence, search
  fallback, and Govee capture queries.
- 2026-05-23: Renamed the Hatch Analysis & Egg Breakouts row summary delta from
  Diff to Gap and removed the `pp` suffix from the displayed value.
- 2026-05-22: Combined Hatch Analysis & Egg Breakouts row percentage, BMK, and
  delta metrics into one readable summary field instead of three narrow tiles.
- 2026-05-19: Removed the Weak / inactive chick item from Chicks Culled Chicks
  Analysis. The defect catalogue no longer renders it in the UI, encodes it into
  `culledChicksAnalysisJson`, or decodes older saved
  `small_weak_weak_inactive_chick` rows.
- 2026-05-19: Moved Egg quality comparison sample chips and add/remove controls
  into the Sampling scope card so the active house sample applies visibly to UV
  tray inspection, weights/uniformity, and future Egg quality items rather than
  appearing inside only the Egg Weights & Uniformity card.
- 2026-05-19: Reworked panel persistence to use explicit nullable hierarchy
  columns (`house`, `setter`, `hatcher`, `trolley`, `tray`, `position`) plus
  storage/BMK context columns instead of the old generic mode/scope/sample
  identity fields. Reopened station edits now update rows by that hierarchy
  identity, and breakout BMK age is saved from the Fresh/Candled/Residue
  formulas.
- 2026-05-19: Normalized duplicate Hatch Analysis breakout tray ids before
  rendering so tray inputs keep independent field state and persist corrected
  ids on the next tray edit.
- 2026-05-19: Replaced Dashboard Egg EST yellow/orange warning surfaces with
  calmer red alarm panels, neutral summary metric highlighting, and light
  blue evidence photo placeholders.
- 2026-05-19: Made panel row saves tolerate orphaned hatchery references from
  older or repaired visit sessions by omitting the nullable panel `hatcheryId`
  when the local hatchery record is missing. This keeps station autosave working
  while Home continues to flag the missing hatchery setup item.
- 2026-05-18: Added minus/plus stepper buttons to Chicks Culled Chicks
  Analysis Count fields while preserving direct numeric entry.
- 2026-05-18: Moved Culled Chicks Analysis Dehydrated / burned chick from
  Sticky into a standalone Dehydrated group.
- 2026-05-18: Removed the Wet chick item from Chicks Culled Chicks Analysis
  Sticky defects.
- 2026-05-18: Removed the Albumen on feathers / glued down item from Chicks
  Culled Chicks Analysis Sticky defects.
- 2026-05-18: Moved Culled Chicks Analysis residual yolk / large abdomen from
  Navel into a standalone Belly group displayed immediately after Navel.
- 2026-05-18: Trimmed Chicks Culled Chicks Analysis counting rows to defect
  subtype plus Count field, keeping descriptions/causes/references for
  Dashboard interpretation instead of the active station entry screen.
- 2026-05-18: Removed deleted legacy Chicks PM lesion columns from fresh
  `chick_quality` schema and current save maps while keeping existing local
  database compatibility.
- 2026-05-18: Changed Hatch Analysis & Egg Breakouts panel persistence so
  Fresh, Candled, and Residue tray samples save as separate tray-scoped rows
  with per-tray counts and percentages instead of one summed breakout row.
- 2026-05-18: Added current-versus-BMK Diff tiles to breakout item rows and
  persisted per-category percentage-point differences on Fresh, Candled, and
  Residue breakout panel rows for dashboard use.
- 2026-05-18: Added Chicks Culled Chicks Analysis after PM Necropsy, with
  grouped defect data entry, guide-based descriptions/causes/references,
  persisted summary fields, and Dashboard Culled interpretation inside the
  Chick Quality sector.
- 2026-05-18: Rebuilt the Dashboard Egg sector around Egg Storage & Handling:
  a 9-point EST temperature grid with evidence thumbnails and AVG/CV summary,
  an Upside Down Egg card, and organized storage checklist metadata. The Egg
  sector does not show Egg uniformity, UV, or CO2 tabs.
- 2026-05-18: Restyled the Dashboard Egg EST card into an evidence-first layout
  with the 9-point grid beside a blue Average/Target/CV summary, alarm text for
  out-of-range average or CV above `AppThresholds.cvAlertPct`, smaller summary
  metric type, a separate Upside Down Egg row, and one combined Storage Info row
  for storage and handling metadata.
- 2026-05-19: Combined the Dashboard Egg Storage Checklist and Handling Metadata
  rows into one `Storage Info` card and removed the storage status recorded tile.
- 2026-05-18: Fixed Dashboard mobile layout by making the Customer/Flock/Age
  filter responsive, constraining dropdown labels, compacting the Egg EST
  summary into a single mobile row above the grid, keeping EST readings on one
  line, and removing Chicks content from Dashboard so the current screen shows
  only Egg plus saved Govee sectors.
- 2026-05-17: Moved the Home ChickMark icon mark into the main gradient app bar
  before the `ChickMark` title and removed the standalone body logo slot.
- 2026-05-17: Changed the Govee live capture card to the ChickMark blue brand
  gradient and adjusted its controls, metric tiles, metadata, and unit toggle
  to white/translucent-white foreground styling.
- 2026-05-17: Hid the Chicks weight active house editor while House scope is in
  One sample mode; Multisamples mode still shows house chips, add/remove
  controls, and the house field for comparison rows.
- 2026-05-17: Limited the Dashboard to the Egg station sector and saved Govee
  Environmental Readings while future sectors are rebuilt. Removed the
  dashboard Egg CO2 tab to match the current Egg station screen, moved saved
  Govee history out of the Govee screen, and grouped saved Govee records by
  place on Dashboard.
- 2026-05-17: Removed the Chicks PM Necropsy Gasping and Deformities sectors
  from the active UI, fresh `chick_quality` schema, save mapping, legacy
  `AuditModel` serialization, and PM dashboard/detail summaries.
- 2026-05-16: Renamed the Chicks PM Necropsy visible lesion label from
  Omphalitis (Yolk Sacculitis) to Omphalitis.
- 2026-05-16: Added Urolithiasis (Urate Deposits) as a fixed Chicks PM
  Necropsy lesion field with count and severity.
- 2026-05-16: Removed Pulmonary Granuloma, Swollen Joints, and Stunted Organs
  from the active Chicks PM Necropsy visible lesion list while leaving legacy
  storage fields intact.
- 2026-05-16: Added editable custom Others lesion rows to Chicks PM Necropsy,
  persisted as `pmOtherLesionsJson`.
- 2026-05-16: Simplified the YFBM entries bottom sheet into a clean entry form
  and moved rows complete, average, CV, and target range details into the main
  YFBM panel.
- 2026-05-16: Changed the Egg Upside Down Score header symbol to an inverted egg
  with the pointed end up.
- 2026-05-16: Redesigned the YFBM entries bottom sheet from a hard-bordered
  table into a draggable card-based entry list with compact progress, target,
  average, and CV summary chips.
- 2026-05-16: Kept the Chicks Active machine Setter and Hatcher fields on one
  equal-width row in narrow visit-session layouts.
- 2026-05-16: Reduced the completed/reached visit progress check glyphs so the
  station nodes read lighter inside their existing circles.
- 2026-05-16: Made the New Visit customer picker dismiss when users tap the
  dimmed backdrop outside the bottom sheet.
- 2026-05-16: Changed the New Visit flock summary card from the Material egg
  glyph to a custom chick icon.
- 2026-05-16: Changed the Select Stations Chicks row from the Material
  `cruelty_free` glyph to the shared chick icon.
- 2026-05-16: Extended visit progress strip connector lines so the line reaches
  the adjacent station circles instead of stopping short between steps.
- 2026-05-16: Added a photo action to the Hatcher Meconium Assessment card.
- 2026-05-16: Revised the Chicks PM Necropsy lesion list to use Omphalitis,
  Gizzard Erosions, Air Sac Caseations, Urolithiasis (Urate Deposits),
  Nephritis, and General Septicemia, and added matching `chick_quality`
  backend fields with on-open column backfill for existing local databases.
- 2026-05-16: Consolidated Chicks quality persistence into one
  `chick_quality` panel table with prefixed Pasgar, YFBM, CVT, and PM fields,
  while keeping Chick Weights & Uniformity in the separate `chick_weights`
  table.
- 2026-05-16: Changed the stable web preview shortcut to default to a profile
  web-server build with local Flutter web resources, fixing the black side
  browser preview caused by the debug web-server handshake.
- 2026-05-16: Replaced the shared ChickMark logo asset and platform launcher
  icons with the cheerful chick-over-check mark inside an egg-shaped blue
  outline.
- 2026-05-16: Updated Android and iOS native launcher display metadata from
  Hatchaudit/hatchaudit to ChickMark while leaving internal package and storage
  identifiers unchanged.
- 2026-05-16: Routed audit `Govee readings` actions and the global Govee
  shortcut into the floating Govee capture panel, and removed the separate
  Govee shell tab so new recordings use only the floating panel surface.
- 2026-05-16: Removed unrelated decorative Pasgar symbols from Sample Size,
  Defect Counts, defect rows, and the score card so the Pasgar panel relies on
  text labels plus functional stepper/photo controls.
- 2026-05-16: Tightened the embedded Chicks Pasgar defect-count layout so
  station panel labels, percentages, count inputs, steppers, and photo buttons
  use compact sizing instead of full-page audit typography.
- 2026-05-16: Removed the redundant embedded Chicks Pasgar Defect Counts card
  heading so the defect rows start directly under the card surface.
- 2026-05-16: Removed the redundant embedded Chicks Pasgar Sample Size card
  heading so the sample-size input starts directly under the card surface.
- 2026-05-16: Added the ChickMark logo mark to the top of Home, wired Recent
  Audits and active-home counts to `audit_sessions`, and removed the Home Audit
  Type Breakdown/stat/action sector.
- 2026-05-16: Made Home Today's Focus metric cards actionable: Continue opens
  the first active visit, Attention opens the first setup/action item, and Ready
  starts a new audit when a ready customer setup exists.
- 2026-05-16: Calmed the shared app typography by lowering the global heading,
  section-title, title, body, badge, metric, app-bar, pending-approval, and
  major station hero text sizes while leaving dedicated numeric capture displays
  large enough for data entry.
- 2026-05-16: Tightened the Home preview and floating Govee capture panel
  styling: Home KPIs now render as a compact strip at browser-preview widths,
  quick actions use primary/secondary hierarchy, and the Govee panel uses light
  bordered surfaces with smaller headers and metric values.
- 2026-05-16: Made Govee Start recording trigger the same scan/reconnect path as
  the manual Scan action when the device is not already GATT connected.
- 2026-05-16: Seeded fresh Egg Shell Quality and Upside Down Score tray sections
  with a default Tray 1 editor before their add-tray action.
- 2026-05-16: Compact Govee live cards now show RSSI, battery, unit switching,
  and a settings sheet for connection details, available devices, read/scan,
  select-device, and disconnect controls; same-day saved captures moved from the
  sticky bottom strip into an expandable card.
- 2026-05-16: Live Govee preview charts now appear as soon as a connected sensor
  has a valid current Temp/RH reading, before recording starts.
- 2026-05-16: Live Govee preview charts now keep a capped connected-reading
  buffer before recording so repeated sensor reads form a trend, while active
  recording still uses a separate windowed buffer for save fallback data.
- 2026-05-16: Live and saved Govee temperature charts now follow the app
  `°F`/`°C` setting for plotted values, rail labels, summaries, and tooltips.
- 2026-05-16: Calmed live and saved Govee Temperature/RH charts for narrow
  variation by enforcing a minimum visual Y range, drawing straight trace
  segments to avoid spline loops, and reducing chart typography for mobile.
- 2026-05-16: Consolidated Egg station quality persistence so Egg weights,
  uniformity, shell UV quality, and notes save into `egg_quality`, removed the
  active `egg_weights` panel table, and moved upside-down score persistence onto
  `egg_storage`.
- 2026-05-16: Prefixed Egg shell UV database columns in `egg_quality` with
  `uv` (`uvTrayEggCount`, `uvAffectedPct`, etc.) to avoid name collisions with
  similar panel metrics.
- 2026-05-16: Added per-type Egg shell UV percentage columns
  (`uvCuticleDamagePct`, `uvWashedPct`, and `uvDirtyPct`) to `egg_quality` and
  surfaced a matching UV Summary card at the top of the Egg Shell Quality
  section.
- 2026-05-16: Prefixed Egg weight and uniformity database columns in
  `egg_quality` with `egg` (`eggWeightsJson`, `eggAvgWeight`,
  `eggUniformityPct`, etc.) so they stay distinct from Chick weight panel
  columns.
- 2026-05-16: Removed Chicks optional panel result pills from Pasgar, YFBM,
  Chick Vent Temperature, and PM Necropsy headers so those rows show only the
  panel title and expand chevron.
- 2026-05-16: Removed the `Uniform`/`Review` result pill from the Chick Weights
  & Uniformity hero card title row.
- 2026-05-16: Restyled the Egg Weights & Uniformity summary to match the Chicks
  weight card row design and metric order, removing the old two-column metric
  tile grid and moving BMK Age out of the weights summary.
- 2026-05-16: Replaced the Egg Sampling scope default segmented button with a
  compact text-only custom pill using a neutral track and subtle selected chip.
- 2026-05-16: Added regression coverage that Egg Weights & Uniformity, Egg
  Shell Quality, and Notes do not render `EW`, `UV`, or `NT` workbench mark
  badges.
- 2026-05-16: Removed the Egg Weights & Uniformity and Egg Shell Quality header
  status pills, including `0/100` and `Avg affected 0.0%`.
- 2026-05-16: Replaced the Chicks Quality sampling and House scope segmented
  buttons with text-only custom pills, removing the selected check and gradient
  segment icons.
- 2026-05-19: Added the Machine Scope title above the Chicks setter/hatcher
  sample chip row in Multisamples mode.
- 2026-05-19: Removed the Chicks weight-panel House scope selector so the
  flock card flows directly into metrics unless house comparison samples are
  already active.
- 2026-05-19: Renamed the Chicks weight comparison chip card to House scope and
  changed its first blank house sample to `Pool`; typed house numbers derive
  labels such as `H1`, while added houses keep automatic serial labels.
- 2026-05-19: Changed blank Chicks machine-sample chips to display `Pool` until
  both Setter and Hatcher values are entered, then derive labels such as
  `S1H1`.
- 2026-05-19: Replaced the Egg Quality One sample / Multiple samples selector
  with House scope and Machine scope cards. Both default to `Pool`; House scope
  activates sequential `H1`, `H2` comparison rows and Machine scope activates
  sequential setter/hatcher rows such as `S1H1`, `S2H2`, while Egg Storage stays
  pooled.
- 2026-05-21: Changed Chick Weights & Uniformity to use an Egg-quality-style
  House scope card. The card is visible in pooled state, add switches to
  generated `H1`/`H2` house comparison samples, the separate Active house editor
  is removed, and saved `chick_weights` panel rows carry house hierarchy values.
- 2026-05-21: Added active scope identity fields: House fields for Egg Quality
  and Chick Weights house scopes, and Setter/Hatcher fields for Egg Quality and
  Chick Quality machine scopes. Entered values update chip labels and persist
  through the panel sample hierarchy columns.
- 2026-05-21: Pruned stale scoped panel rows after station saves so deleting
  House or Machine scope samples removes their database rows and queues
  tombstones for sync.
- 2026-05-22: Fixed Egg Quality scope hierarchy so Machine scope is added under
  the active House scope instead of replacing it. House chips stay visible as
  the parent level, machine chips are filtered to the selected house, houses
  without machine samples show pooled machine scope, and adding House scope after
  Machine-only scope resets the lower machine samples.
- 2026-05-22: Kept generated Egg Quality scope chip labels while leaving their
  House/Setter/Hatcher input fields blank until the user enters real numbers,
  and made House scope removal cascade-delete nested Machine scope samples.
- 2026-05-22: Removed the inherited House field from the Egg Quality Machine
  scope card; Machine scope now relies on the selected House scope and only asks
  for Setter and Hatcher values.
- 2026-05-22: Kept generated Egg Quality scope serials local to each visible
  scope list, so machine samples under a selected house start at `S1H1` even
  when house scope already contains `H1`/`H2`.
- 2026-05-22: Made Egg Quality House-scope removal target the selected parent
  house even when a nested machine sample is active, so one House `-` press
  removes the house and all machine samples beneath it.
- 2026-05-22: Tightened the v41 destructive cutover and current-schema tests so
  obsolete audit/sample repositories remain inert, current panel relationship
  cascades are verified, and legacy Govee/temperature tables are dropped during
  reset.
- 2026-05-19: Made Egg storage-period, EST/storage handling, Egg Quality storage
  period, and Egg Quality BMK age/weight fields shared across Egg Quality
  house/machine scope samples so the second sample keeps the same BMK lookup
  instead of showing blank benchmark weight.
- 2026-05-19: Started the Egg Quality BMK egg-weight lookup from the default
  Quality Storage Days value when the Egg screen opens, so the BMK Egg Weight row
  does not stay blank until storage days are manually edited.
- 2026-05-16: Removed the leading thermometer icon from the station-level
  `Govee readings` card and removed compact PG/YF/CVT/PM mark badges from
  Chicks optional panel headers.
- 2026-05-16: Removed Egg station hero icons, shortened the visit progress
  label for Hatch Analysis to one line, changed Hatch Results subtitles/groups
  from Batch to Hatch wording, made Setters chips text-only, aligned the CO2
  camera with its field, removed the Setters EST range helper strip, and
  changed Chicks weight metrics to a compact summary list.
- 2026-05-15: Cut persistence over to panel-only storage. Fresh v36 databases
  no longer create `audits`, `sample_records`, sample detail tables, or
  `{panel}_samples` child tables. Station saves, dashboard reads, Supabase
  sync, tombstones, and photo identity now use `audit_sessions` plus panel
  rows.
- 2026-05-15: Added an end-to-end panel smoke test for the full audit workflow:
  customer/flock/hatchery/session creation, all five stations, save/reopen/edit
  persistence, pool and comparison row behavior, legacy-table absence, and
  dashboard loading from panel tables. Reopened panel saves now update by panel
  row identity when the in-memory draft ID differs, and filtered Egg dashboard
  queries qualify their panel-table aliases.
- 2026-05-15: Restyled live and saved Govee Temperature/RH charts back to a
  light Govee-original-style card with dark titles, light dashed grid lines,
  inside time ticks, cyan traces, and no visible zoom controls below the chart.
- 2026-05-16: Removed the decorative `EST`, `UD`, and `CHK` mark badges and the
  right-side status pills from the EST, Upside Down, and Storage Checklist Egg
  workbench headers.
- 2026-05-15: Allowed Scan to connect to nameless Govee advertisements that
  expose Govee manufacturer or service identity even before live Temp/RH bytes
  are present, while keeping non-Govee sensor-shaped advertisements ignored.
- 2026-05-15: Renamed the Egg Shell Temperature target summary labels to
  Storage duration and EST target, kept Egg quality flock/breed/BMK Age tiles in
  one equal-width row, and refined the Sampling scope choices.
- 2026-05-15: Made Egg EST, Upside Down, Storage Checklist, Egg Weights &
  uniformity, and Egg Shell Quality into expandable cards, removed their helper
  phrases, and renamed the house-sample weights area to Egg Weights & Uniformity.
- 2026-05-15: Kept Hatch Analysis & Egg Breakouts metadata in one equal-width
  row so long flock or breed names wrap inside their tile instead of moving BMK
  Age to a second row.
- 2026-05-15: Equalized the Hatch Analysis Breakout Type and metadata card
  heights, restyled the Storage Days card as a shorter teal-blue card without an
  Entry Fields heading, renamed Batch Results to Hatch Results, removed the
  redundant tray-card title, and aligned tray label/position/size fields in one
  equal-width row.
- 2026-05-16: Changed the Hatch Analysis Storage Days entry card from the
  teal-blue treatment to a light-grey surface with a white input tile and dark
  field text.
- 2026-05-16: Removed the leading analytics icon from the Residue / Hatch Day
  Hatch Results card header.
- 2026-05-19: Changed Hatch Analysis Candled/Residue hierarchy entry to shared
  house tabs followed by setter/hatcher machine tabs, moved House/Setter/Hatcher
  out of tray cards, and kept tray cards scoped to Trolley, Tray, Position, and
  Tray size.
- 2026-05-15: Moved Storage Days out of the expandable Egg Shell Temperature
  card so it appears immediately before that card.
- 2026-05-15: Hid the app-wide floating Govee shortcut while modal sheets are
  open, preventing it from covering Egg station entry sheets such as egg-weight
  capture.
- 2026-05-15: Fixed Chicks station panel persistence so Pasgar, YFBM, CVT, and
  PM save only to setter/hatcher quality rows, while Chick Weights saves only to
  house-scoped `chick_weights` rows using each house sample's own weights,
  sample size, average, uniformity, CV%, and custom house label.
- 2026-05-15: Fixed Hatcher add/remove sample persistence so removing back to a
  single hatcher saves pooled `hatcher_optimizing` rows and clears comparison
  group metadata while preserving the edited hatcher number in sample metadata.
- 2026-05-14: Simplified the Egg station cards by reducing the Egg storage hero
  to the room name plus hatchery, converting Egg quality to a matching gradient
  hero with flock/breed/BMK age, renaming sample modes to One sample/Multiple
  samples, and removing helper explanations from the selected Egg panels.
- 2026-05-14: Extended manual Govee Scan/rescan discovery from 8 seconds to 30
  seconds and made discovery-timeout diagnostics report the actual scan window.
- 2026-05-14: Tightened Govee BLE device detection so raw H5051-shaped
  advertisement bytes are accepted only from devices with Govee/H50/GVH naming
  or Govee manufacturer/service identity, preventing unrelated nearby BLE
  devices from appearing as connected sensors.
- 2026-05-14: Restyled live and saved Govee Temperature/RH charts to use a
  dark Govee-app-style card with centered white titles, cyan traces, dashed grid
  and average line, filled chart area, endpoint labels, and zoom controls.
- 2026-05-14: Made the app-wide floating Govee shortcut draggable and
  side-tuckable so it can be moved out of the way or hidden partly off the left
  or right edge while remaining tappable.
- 2026-05-14: Removed the large green completion check overlay from
  intermediate station saves; it now appears only when the final selected station
  completes the visit.
- 2026-05-14: Added setter-style Hatcher comparison controls with Add/remove
  hatcher chips, generated H-labels, hatcher comparison sample metadata, and no
  generic Sample Mode, hatcher type, or turning-angle controls.
- 2026-05-14: Moved Hatchers incubation age/hour controls into a CVT sample
  card, reused the setter-style guided OCR sample grid for Chick Vent Temp.,
  removed Transfer Day from the Hatcher screen, and changed Meconium options to
  Normal, Dark greenish, Water, and Excessive.
- 2026-05-14: Added the v35 additive Setter machine-field migration for screen
  readings, machine-screen photo evidence, batch totals, and nested age/breed EST
  sample JSON without clearing existing audit data, and removed flock-derived
  breed identity from Setter/Hatcher machine station rows/screens. This
  pre-cutover dual-write path was superseded by the v36 panel-only schema.
- 2026-05-14: Restored Govee Start/Stop saving without a warmup discard window,
  showed the current recording length while recording, restored live preview
  charts from current readings, saved active live readings when recent H5051
  history returns an empty stored window, and made missing H5051 history
  characteristics fail into the retryable sync path instead of returning an
  empty saved dataset.
- 2026-05-13: Added a formula registry and centralized shared calculation
  behavior for BMK age conversion, Pasgar scoring, sample SD/CV, percent
  validation, residue hatchability/fertility/HOF, and egg-breakout dashboard
  guards. Invalid count-over-total percentages are suppressed except where HOF
  intentionally allows values above 100.
- 2026-05-13: Added the v34 relationship-integrity migration, foreign keys, FK
  cleanup tests, cascade/delete tests, invalid-parent insert tests, and safer
  insert-or-update repository upserts for parent tables with children.
- 2026-05-13: Hardened the highest-risk local persistence paths: V26 now
  preserves existing Govee daily captures during schema cleanup, V31 verifies
  legacy station-sample copies before dropping `station_samples`, station sample
  upserts run as one transaction, and legacy audit metadata patches write
  storage/BMK/incubation values only to the matching station fields.
- 2026-05-13: Split database lifecycle, schema builders, and migration helpers
  into focused database helper files while preserving the same SQLite upgrade
  behavior and test-only migration entrypoints.
- 2026-05-13: Hardened async/save recovery by guarding stale audit-session
  loads, coalescing duplicate station completion and save work, isolating final
  save side-effect failures from local persistence, preserving Govee synced
  readings for save retry, capping long-recording preview memory, and logging
  recoverable photo/OCR failures.
- 2026-05-13: Hardened production safety by requiring an explicit debug-mode
  compile flag for auth bypass, disabling local fallback auth by default in
  release builds, upgrading local fallback passwords to PBKDF2-HMAC-SHA256,
  gating Supabase access on initialization, storing non-public photo references
  by default, and reducing sensitive debug logging.
- 2026-05-13: Defined earlier dashboard/source-of-truth rules for the
  transition-era dual-write schema. This was superseded by the v36 panel-only
  schema, where dashboard queries read panel tables directly.
- 2026-05-13: Lifted the floating Govee shortcut from `MainShell` to the app
  Navigator overlay so it remains available on pushed audit station screens
  while continuing to open the standalone Govee workflow.
- 2026-05-13: Added an active-recording visual state to the floating Govee
  shortcut: the launcher changes from the idle blue circle to a red rounded
  stop-style button while Govee capture is recording.
- 2026-05-13: Fixed the Govee no-valid-readings recovery path so an empty sync
  returns the recorder to idle instead of leaving Stop/save active, and added
  diagnostics for long recordings whose synced readings land outside the valid
  recording window.
- 2026-05-13: Added dedicated Setters multi-setter tabs in one audit session,
  with setter-number labels such as `S5`, restored saved setter station samples
  on resumed visits, and changed Setters EST to the storage-style guided OCR
  grid workflow using 99.5-102.0°F allowed and 100.0-101.0°F optimum ranges.
- 2026-05-13: Removed the generic Sample Mode controls from Hatchers; Hatchers
  stays as one machine record for the selected visit context.
- 2026-05-13: Added Residue / Hatch Day batch tabs below Entry Fields,
  generated from setter and hatcher numbers, per-batch Batch Results cards
  before tray breakout samples, residue hatchability/fertility/HOF/culled/dead
  calculations, breed benchmark comparison for Hatchability/Fertility/HOF, and
  fixed culled/dead percentage limits. Residue no longer enforces the legacy
  100-percent hatch budget.
- 2026-05-13: Added an internal BMK admin mode on the BMK screen. Approved
  internal users can switch from Reference to Admin, edit the selected breed
  benchmark row and selected egg-breakout benchmark row, validate numeric
  percentages/weights, and save back into the same local BMK tables consumed by
  audit and dashboard benchmark lookups.
- 2026-05-09: Hardened the v24 Govee migration so iPhones with legacy v23
  `govee_daily_captures` tables can open and continue through the v25 schema
  rebuild instead of crashing on missing `stationKey` columns.
- 2026-05-09: Fixed Select Stations returning from a visit-session route with
  Start Visit stuck in its loading/disabled state.
- 2026-05-09: Reduced visit station opening work by mounting only the current
  station initially and keeping previously opened stations mounted. Refined the
  embedded Govee entry point and Egg quality panel with a compact card button,
  normal workbench header, neutral sample context, segmented Sampling scope
  control, and lighter metric cards.
- 2026-05-09: Set new Egg station Storage Days to default to `0` and clear the
  default zero on field focus to speed numeric entry.
- 2026-05-09: Added 0-23 hour sliders beside the Setter and Hatcher incubation
  day sliders, storing the hour offsets in SQLite v30 audit columns.
- 2026-05-09: Added audit-station draft autosave for Egg, Chicks, Hatch
  Analysis & Egg Breakouts, Setters, and Hatchers. Station edits now debounce
  into local `draft` audit rows and linked station samples, show compact
  autosave status, retry before leaving when needed, and only publish active
  audit rows through Save/Next or startup sync.
- 2026-05-08: Fixed Hatch Analysis & Egg Breakouts count inputs so loaded zero
  counts remain visually blank like untouched fields, including cleaned residue
  Early Dead values migrated from legacy early-stage counts.
- 2026-05-08: Cleaned Hatch Analysis & Egg Breakouts BMK fields: Fresh Egg now
  uses Infertile, 24 hours, 48 hours, and Blood Ring; Candled Egg adds Black
  Eye; Residue / Hatch Day uses Infertile, Early Dead, Mid Dead, Late Dead,
  External Pip, Cracked, and Contaminated. SQLite v29 rebuilds
  `bmk_egg_breakout` to only those benchmark columns and reseeds 25-65 week BMK
  rows, reusing the 51-60 week values for ages above 60.
- 2026-05-08: Removed legacy generic Temp/RH persistence by dropping
  `temperature_sessions` and `temperature_readings` in v28, removing their
  startup sync path, and leaving `govee_daily_captures` as the saved chart
  source.
- 2026-05-08: Removed obsolete Govee schema leftovers by making
  `govee_daily_captures` the only active Govee table and dropping legacy
  audit-level Govee fields from the audits schema/model.
- 2026-05-08: Simplified Govee capture storage to one row per saved
  place/machine/date by moving LTTB chart points into
  `govee_daily_captures.chartPointsJson`, dropping the local
  `govee_place_readings` table on v26, and syncing only the capture row.
- 2026-05-08: Fixed Hatch Analysis & Egg Breakouts BMK age display so zero
  session flock age falls back to flock entry date and unresolved age displays
  as `--` instead of `0 wks`.
- 2026-05-08: Set Hatch Analysis & Egg Breakouts Storage Days to default to
  `0`, clear that zero on focus for faster entry, and display it in a separate
  entry card below the read-only metadata card.
- 2026-05-08: Removed the `REQUIRED` badge from the Hatch Analysis & Egg
  Breakouts Entry Fields card while keeping Storage Days as a separate entry
  field.
- 2026-05-08: Hid the breakout sample position selector for Fresh Egg entries;
  Candled Egg and Residue / Hatch Day continue to capture position.
- 2026-05-08: Set new Fresh Egg breakout tray samples to default to 30 eggs
  while keeping Candled Egg and Residue / Hatch Day tray samples at 150 eggs.
- 2026-05-08: Temporarily detached login/register in debug builds by enabling
  a development auditor auth bypass and routing auth screens back to Home while
  the app is under active build-out.
- 2026-05-08: Cleaned up the Govee capture UI: same-day saved stations now stay
  pinned in a bottom strip across new recordings, and saved/live charts use a
  Govee-style Max/Avg/Min rail with dashed grid, average line, and zoom controls.
- 2026-05-08: Hardened Govee history sync startup so it waits for in-flight GATT
  connect/discovery work and rediscovers services when a connected sensor only
  has the live `2011` characteristic cached before the `2012`/`2013` history
  characteristics.
- 2026-05-08: Matched H5051/H5179 epoch-minute history status handling to the
  captured device traffic: single-byte `0x00` accepts a request, `0x03` is
  progress, and `0x02` completes the sync after `2013` data packets arrive.
- 2026-05-14: Fixed H5051/H5179 epoch-minute history requests to avoid the
  still-open current minute, preserve completed minute-bucket boundaries for
  filtering, and pin packet parsing to the observed reverse-minute packet
  layout from captured device traffic.
- 2026-05-14: Hardened Govee history sync retry so a disconnect during `2012` or
  `2013` history notification setup waits for reconnect and reissues the
  original Start/Stop history request instead of failing the recorder
  immediately.
- 2026-05-07: Split Govee history sync by device family: H5051/H5179 names now
  use the 10-byte epoch-minute request on `2012`, older H507-style names keep
  the `0x3301` minute-back request, live `0x0A` reads stay on `2011`, and the
  sync window avoids the not-yet-stored current minute.
- 2026-05-07: Reworked Govee capture persistence to one manual place-level
  Start/Stop window, added Temp/RH SD and CV% summaries, replaced bucketed spot
  readings with LTTB-selected place-level chart points, migrated old spot
  readings into place-level rows, removed spot labels/boundaries from Dashboard
  Govee charts, and synced the new Govee data through startup Supabase sync.
- 2026-05-07: Hardened native Govee Scan on iOS/macOS by using adapter-state
  readiness instead of the FlutterBluePlus Darwin `isSupported` preflight that
  can emit duplicate native method responses, and by avoiding duplicate
  first-start adapter state reads while CoreBluetooth is still initializing.
  The macOS build also injects the Bluetooth usage descriptions into the
  embedded FlutterBluePlus framework to satisfy TCC when the framework touches
  CoreBluetooth.
- 2026-05-07: Tightened the visit-session station shell with a default-height
  station app bar, compact progress strip, smaller station icons/labels, and a
  shorter bottom navigation footer. Progress labels wrap to avoid hidden station
  names in five-station visits.
- 2026-05-06: Added the Dashboard `Govee Environmental Readings` section with
  local place/machine filters, timestamp-based Temperature and RH charts, and
  detailed chart touch tooltips loaded by selected hatchery/date.
- 2026-05-06: Bumped SQLite to v24 for machine-aware Govee capture scope and
  renamed Govee setter places.
- 2026-05-06: Updated an intermediate Govee recording provider iteration; the
  active behavior is now the standalone Govee place-level Start/Stop flow.
- 2026-05-06: Redesigned the active Govee entry screen with the gradient live
  header, station room/inside-machine picker, and Temp/RH preview charts.
- 2026-05-03: Scoped the floating Govee shortcut to `MainShell` so the launcher
  does not rebuild the root navigator or retrigger startup background sync.
- 2026-05-03: Restored the scoped floating Govee shortcut on the authenticated
  main shell as a hardware-validation entrypoint while keeping the standalone
  Govee capture workflow unchanged.
- 2026-05-03: Restored H5051 live Scan/Read controls and the stored-history
  `0x3301` sync path needed to validate device history before redesigning the
  visit-based Govee model.
- 2026-05-02: Replaced the Measures tab/launcher with standalone Govee daily
  captures, added Govee persistence and sync tables, exposed station deep links,
  and moved saved Govee charts to dashboard/visit surfaces.
- 2026-04-28: Replaced placeholders with a code-derived map of current
  navigation, audit workflow, station screens, data hierarchy, provider state,
  persistence, sync, measures, OCR, and known technical debt.
- 2026-04-28: Created living spec placeholder and reset documentation source of
  truth to the implemented Flutter codebase.
