# Assistant Voice Chat — Design

**Status:** Approved
**Source:** `chickmark-voice-plan.md` (user-authored plan, "Bite 2: Voice Chat")

## Goal

Add voice input/output to the existing in-app assistant chat (`AssistantChatScreen` /
`app-hatchery-agent`). The phone records and plays audio only; all speech
processing happens server-side. The agent brain itself is untouched — voice is
a new transport, not a new capability.

## Loop

1. Phone records audio → sends it to `app-hatchery-agent` as base64 in the
   existing JSON `send` action.
2. Server decodes → OpenAI Whisper (`whisper-1`) → transcript.
3. Transcript runs through the **existing** `handleSend` path unchanged
   (same idempotency, rate limiting, history, tool calls, storage).
4. Server calls OpenAI TTS (`tts-1`, voice `alloy`) on the reply text →
   base64 audio in the response.
5. Phone plays the returned audio.

Voice turns are stored identically to typed turns: the stored `text` is the
Whisper transcript, so history reads the same regardless of how a turn
originated. No DB schema change.

## Secrets

- New Edge Function secret `OPENAI_VOICE_KEY` (distinct from the existing
  `OPENAI_API_KEY`, which the agent brain already uses via `AI_PROVIDER=openai`).
  This preserves the plan's $5 spend cap in isolation from brain billing.
- Key is read only in `app-hatchery-agent`; never sent to or stored on the
  phone.

## Server (`supabase/functions/app-hatchery-agent`)

- `hasAttachmentField` currently rejects any `audio`/`voice` field with a 400.
  Replace with: accept a new explicit field `audioBase64` (not in the
  blocked-field list) on the `send` action only. `history` and `reset` are
  unaffected.
- New `handleSend` entry path: when `audioBase64` is present and `message` is
  absent, decode → Whisper → use the transcript as `message`, then continue
  through the exact same code path a typed message takes (idempotency key,
  rate limit, turn storage, `runAgentTurn`, reply storage).
- After a successful reply, if the request was voice-originated, call TTS on
  `result.reply` and add `audioBase64` (mp3) to the JSON response. Typed
  requests never trigger TTS — no audio is generated for text-in turns.
- Whisper/TTS calls use `OPENAI_VOICE_KEY`, read via a small dedicated config
  block parallel to the existing `readAiConfig()`.
- Errors from Whisper/TTS map to the existing `agent_unavailable` (502)
  failure shape — no new error codes on the client contract.
- Reasonable payload ceiling on incoming `audioBase64` (reject oversized
  clips before decoding) — exact bytes ceiling picked during implementation,
  generous enough for a several-second question.

## Phone (Flutter)

- Add `record` (recording) and `audioplayers` (playback) packages.
- `_AssistantComposer` gets a mic button beside the send button. Tap-to-start
  / tap-to-stop (not hold-to-talk, consistent with tap-to-send elsewhere in
  this screen).
- Recording flow, owned by `AssistantProvider` (extended, not forked):
  1. Tap starts recording (request mic permission if needed).
  2. Tap again stops recording, immediately plays a bundled short chime
     asset via `audioplayers` (the "filler" cue) while the request is in
     flight.
  3. Sends base64 audio via a new `AssistantChatPort.sendVoice(...)` method,
     parallel to `sendMessage`.
  4. On reply, the chime is replaced by auto-playing the returned TTS audio.
  5. The transcript appears as a normal user chat bubble; the reply appears
     as a normal assistant bubble — no distinct "voice message" bubble type.
- UI states added to the existing idle/sending model: `recording`,
  `awaitingVoiceReply` (chime + thinking indicator), `speaking`. Reuses the
  existing `_AssistantThinkingIndicator` visual pattern where possible.
- Errors (mic permission denied, network failure, oversized clip) surface
  through the existing `_AssistantErrorBanner` / retry mechanism — no new
  error UI.

## Out of scope (per plan)

- Photos, conversational data entry.
- Streaming playback / faster model swap (listed as later polish).
- Hold-to-talk.
- Per-language filler audio — one chime, language-agnostic.

## Testing

- Server: extend `index_test.ts` for the new `audioBase64` path (decode →
  transcribe → existing send path → TTS → response shape), with fake
  Whisper/TTS deps injected the same way `runAgentTurn` is already faked.
- Phone: widget/provider tests for the new recording states and
  `sendVoice` port method, following the existing `AssistantProvider` test
  patterns (fake port, no real audio I/O in tests).

## Docs

Per `CLAUDE.md`, this change updates `docs/LIVING_SPEC.md` (assistant chat
section gains voice) and adds a `docs/CHANGELOG.md` entry, in the same
commit as the code.
