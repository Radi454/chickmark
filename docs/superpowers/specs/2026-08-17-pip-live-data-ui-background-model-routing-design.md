# Pip Live Data, UI, Background Audio, and Model Routing Design

## Status

Approved in conversation on 2026-08-17. This document records the agreed
design before implementation planning. It does not authorize changes to Pip's
tool catalogue, RBAC rules, broker ownership, Sideband architecture, or product
behavior outside the parity, presentation, background-audio, and model-routing
changes described here.

## Goal

Make Pip Live use ChickMark's existing server-side data tools as reliably as
typed Pip, present a dedicated live-conversation screen with captions and
animation, keep an active mobile call running while the app is minimized or the
screen is locked, and reduce model cost through explicit workload routing.

## Current-State Findings

### Typed and recorded-voice Pip

Typed chat sends turns through `app-hatchery-agent` and the shared agent
runtime. The runtime supplies the complete ChickMark policy, recent
conversation history, the unified tool catalogue, and server-resolved scope.
The policy explicitly requires the BMK tools for benchmark facts.

Recorded voice is a separate request/response path. It transcribes one clip,
sends the transcript through the same text-agent runtime as typed chat, and
synthesizes the final reply. It currently uses `whisper-1` for transcription
and `gpt-4o-mini-tts` for speech.

### Pip Live

Pip Live sends and receives audio directly through OpenAI Realtime over WebRTC.
The Flutter client owns only presentation and transport. Tool calls are ignored
on the client and executed exclusively through the Cloud Run Sideband and the
Supabase tool broker.

The deployed Sideband advertises all 32 unified tools, including
`get_breed_benchmark`, `get_egg_breakout_benchmark`, and
`get_operational_standards`. The broker re-resolves authority, validates the
authorization fingerprint, enforces argument scope through the shared runtime,
and records tool evidence. Therefore the observed BMK failure is not caused by
missing tools, missing BMK rows, RBAC, or broker wiring.

The confirmed parity defect is that production Live supplies no ChickMark agent
instructions. Typed Pip receives the full policy, including BMK discipline,
breed transliteration, age requirements, terminology, and evidence rules; Live
receives only tool descriptions. Production Realtime sessions have not produced
any persisted Realtime tool calls.

The Realtime controller already collects user and assistant captions and
exposes listening, user-speaking, thinking, assistant-speaking, reconnecting,
ending, and error states. The current chat screen does not render the captions
or an animated Live surface; it exposes only a small start/stop icon.

### Cost and routing

Live does not call the standalone recorded-voice transcription or speech
endpoints. It uses Realtime audio directly and separately enables the Live
caption transcription configured on the Realtime session. There is no
`gpt-4o-mini-transcribe` plus `gpt-4o-mini-tts` plus Realtime triple pipeline.

Production typed Pip is currently routed through OpenRouter's rotating free
pool because `AI_PROVIDER` is `openrouter`. An OpenAI fallback constant alone
does not change production routing.

The production OpenAI key returned model metadata successfully for every model
selected by this design. A synthetic English and Arabic BMK request also
completed the existing Responses function-call loop with `gpt-5-nano`.

## Architecture

### 1. Shared Live instruction parity

The versioned `CHICKMARK_AGENT_POLICY` remains the source of truth for agent
behavior. Deployment tooling renders a `PIP_REALTIME_INSTRUCTIONS` value from
that policy in the same manner that it currently renders
`PIP_REALTIME_TOOL_DEFINITIONS` from the unified tool contract.

The Sideband validates that the rendered instructions are present and nonempty,
then passes them through the existing chain:

`main.ts -> RealtimeServer -> SidebandSession -> session.update.instructions`.

Startup diagnostics record only an instruction version or fingerprint, never
the policy text. Parity tests compare the rendered value with the shared policy
and prove that a production-style server configuration sends nonempty
instructions in `session.update`.

This is configuration parity, not a new Sideband architecture. The existing
Sideband remains the sole Realtime control path; the broker remains the sole
tool-execution boundary; and the current tool catalogue, RBAC, fingerprints,
limits, persistence, and ledger ownership remain unchanged.

The Live instructions do not embed BMK table rows, customer data, raw IDs,
authorization claims, or client-supplied scope. Data remains tool-fetched at
request time through the broker.

### 2. Dedicated Live conversation screen

Starting Live opens a dedicated full-screen route while using the existing
shell-owned `RealtimeVoiceController`. The route does not create or own a
second controller, WebRTC peer, or backend session. Leaving the route therefore
minimizes the presentation without ending the call.

The screen contains:

- A Pip identity header and concise connection/state label.
- A central animated orb or waveform driven only by the existing controller
  state. Listening is calm, user speech reacts to input state, thinking uses a
  restrained pulse, and assistant speech uses an active waveform.
- A vertically scrolling, RTL-aware caption transcript. Interim text updates
  in place and finalized turns remain visible for the current call.
- Mute, minimize, and end controls. End is visually distinct and always
  releases the Realtime session.
- Reconnecting and error states using the controller's existing bounded
  diagnostics and retry behavior.

The animation is implemented with Flutter primitives and existing ChickMark
design tokens. It does not add a remote visual dependency. Captions are
presentation-only and do not write a second copy of durable conversation turns.

When a call is minimized inside the app, the shell shows a compact persistent
Live indicator that returns to the dedicated screen and offers an explicit end
action. Typed input and recorded voice remain disabled while Live owns the
mobile audio session, preserving the current mutual-exclusion behavior.

### 3. Mobile background and lock-screen audio

#### iOS

The Runner declares `UIBackgroundModes` with `audio`. The active Realtime call
uses an `AVAudioSession` appropriate for two-way voice communication:
`playAndRecord` with `voiceChat` mode. The session is activated only for an
active call and released when that call ends.

Interruption and route handling distinguishes a temporary interruption from a
user-ended call. The app may resume only a call that was active before the
interruption and still has a valid controller/backend generation. Bluetooth,
wired-headset, speaker, and receiver route changes must not create a second
peer connection.

This design does not claim the iOS `voip` background mode, add incoming-call
behavior, or introduce CallKit. It supports the user-initiated, already-active
audio conversation. It cannot guarantee survival after force quit, OS process
termination, expired session limits, or severe resource pressure.

#### Android

Starting Live while the activity is visible starts a foreground service for
microphone capture and audio playback. The manifest declares the base
foreground-service permission, the microphone service permission required by
modern Android, and the service's actual types. The service immediately posts
an ongoing, low-priority notification that identifies the active Pip call and
provides an End action.

The foreground service is stopped on explicit End, logout, authorization
failure, unrecoverable call failure, controller disposal, or backend session
termination. It is never started from a background-only state, because modern
Android restricts foreground microphone service creation when the app is not
visible.

The first implementation keeps WebRTC ownership in the existing Flutter
controller and uses the foreground service to keep the user-initiated process
eligible while backgrounded. If the real-device verification matrix shows an
OEM suspends that Flutter engine despite the foreground service, moving WebRTC
ownership into a service-hosted engine is a separate architecture task and is
not silently folded into this change.

#### Platform limits

Background support does not bypass Pip's configured session duration, usage
budgets, authorization changes, provider disconnections, or network loss. Web
browsers cannot guarantee locked-screen or background-tab continuity and are
not included in the mobile background guarantee.

### 4. Model routing

Model routing is explicit by workload:

| Workload | Default model | Notes |
| --- | --- | --- |
| Typed text reasoning | `gpt-5-nano` | OpenAI Responses API with the existing policy and tools |
| Live Voice | `gpt-realtime-2.1-mini` | Replaces `gpt-realtime-2.1` |
| Recorded voice-note STT | `gpt-4o-mini-transcribe` | Replaces the currently implemented `whisper-1` |
| Recorded voice-note reasoning | `gpt-5-nano` | Same runtime and route as typed text |
| Recorded voice-note TTS | `gpt-4o-mini-tts` | Unchanged |

Production text routing switches from the rotating OpenRouter free pool to the
explicit OpenAI model. Both in-app and Telegram/shared-runtime OpenAI defaults
use the same text-model constant or an equivalently tested single source, while
provider-specific OpenRouter fallback behavior remains intact for an operator
who explicitly chooses OpenRouter later.

`gpt-5-nano` is selected because it is the lowest-cost account-accessible model
that supports the current Responses, function-calling, image-input, and
structured-output requirements and passed the existing two-step function-call
shape with English and Arabic BMK prompts. Acceptance and end-to-end tests are
release gates; if the model fails the full ChickMark policy/tool suite, the
change stops for review rather than silently falling back to a different model.

The Realtime provisioning default and Sideband model metadata/default use the
same `gpt-realtime-2.1-mini` alias. Recorded voice reasoning is not assigned a
second model because it already enters the normal text-agent runtime after
transcription.

### 5. No-double-pipeline invariant

The two voice modes remain separate:

- Live: Realtime client-secret provisioning, WebRTC audio, Sideband tools, and
  Live caption transcription. It makes no standalone `/audio/transcriptions`
  or `/audio/speech` request.
- Recorded note: exactly one standalone STT request, one normal text-agent
  reasoning/tool loop, and at most one standalone TTS request.

Tests enforce these endpoint boundaries through injected request counters or
transport fakes. Logging may record model aliases, request identifiers, and
outcome codes, but never audio, transcripts, prompts containing customer data,
API keys, or tool results.

## Error Handling

- A missing or malformed rendered Live policy fails Sideband startup instead of
  launching a healthy-looking session with no operational behavior.
- A rejected or failed broker tool call is returned to the Realtime model using
  the current tool outcome protocol; no client fallback executes it.
- A Live UI route may be dismissed without ending the call, but an explicit End
  always tears down transport, Sideband binding, foreground/background audio
  ownership, and the backend session.
- If Android foreground-service startup or iOS audio-session activation fails,
  Live fails before background eligibility is claimed and shows a retryable,
  bounded diagnostic.
- Existing one-recovery-per-start network behavior remains unchanged.

## Verification

### Backend and routing

- Unit-test the rendered policy and its version/fingerprint against
  `CHICKMARK_AGENT_POLICY`.
- Test the full `main.ts` configuration chain through the emitted
  `session.update.instructions` field.
- Retain the 32-tool catalogue parity test and verify the BMK definitions remain
  present.
- Assert the exact defaults for `gpt-5-nano`,
  `gpt-realtime-2.1-mini`, `gpt-4o-mini-transcribe`, and
  `gpt-4o-mini-tts`.
- Run the shared agent acceptance, BMK, provider, app-agent, and Realtime
  Sideband suites.
- Run English and Arabic BMK smoke tests that produce a persisted
  `get_breed_benchmark` event and state both breed and age in the answer.
- Verify a missing-age request asks one focused question and does not invent a
  benchmark.

### Pipeline isolation

- Prove Live makes zero standalone STT/TTS calls.
- Prove a recorded note makes one STT call, uses the normal text model, and
  makes at most one TTS call.
- Confirm Live captions do not create duplicate durable turns.

### Flutter

- Widget-test every Live state, caption delta/final replacement, Arabic RTL,
  scrolling, mute, minimize, return-to-call, end, reconnect, and error state.
- Preserve recorded-voice/Realtime mutual exclusion.
- Verify switching tabs or dismissing only the Live route does not dispose the
  controller or end the call.
- Run focused chat and Realtime tests, then `flutter analyze`.

### Real devices

- iPhone: Home, lock screen, foreground return, wired and Bluetooth route
  changes, interruption, and Wi-Fi/cellular handover for the configured
  ten-minute maximum session.
- Android API 31, 34, and 35: Home, lock screen, ongoing notification and End
  action, microphone indicator, network handover, and foreground-service
  teardown on every terminal path.
- On both platforms, verify two-way audio, captions, one successful BMK tool
  call, and clean microphone/resource release.

## Deployment

Implementation is not complete until code and production configuration agree.
Deployment work therefore includes:

- Deploying the updated `app-hatchery-agent` and shared runtime defaults.
- Setting production text routing to OpenAI with `gpt-5-nano`.
- Deploying `pip-realtime-session` with
  `gpt-realtime-2.1-mini` as its default.
- Rendering and supplying the versioned Live policy and existing tool
  definitions to a new Sideband revision.
- Keeping secrets in their existing secret stores and never embedding them in
  Flutter or deployment documentation.
- Performing the model-access preflight and the English/Arabic BMK smoke tests
  before directing production traffic to the new revision.

## Non-Goals

- Changing the tool catalogue or adding a BMK-specific duplicate tool.
- Changing RBAC, authorization fingerprints, broker scope enforcement, tool
  budgets, or ledger ownership.
- Replacing Sideband speech-to-speech with an STT/text/TTS hybrid.
- Adding incoming-call behavior, CallKit, Android Telecom, or an always-on
  listening service.
- Guaranteeing Live survival after force quit, OS process termination, or past
  the configured Realtime session limit.
- Adding a user-facing model selector.
- Embedding database rows or authorization scope in Realtime prompts.

## Risks and Assumptions

- Switching production text from a rotating free OpenRouter pool to an explicit
  paid OpenAI model improves determinism and follows the requested OpenAI
  routing, but it can increase text-model spend from the current free route.
- `gpt-5-nano` passed targeted tool-loop probes; the full multilingual agent
  suite remains the capability gate.
- Live captions carry a transcription cost inside the Realtime session. They
  are retained because visible conversation text is an explicit requirement.
- Reliable background microphone use requires visible platform disclosure,
  including Android's persistent notification and system microphone indicator.
- Real-device background behavior cannot be proven by unit and widget tests
  alone.
