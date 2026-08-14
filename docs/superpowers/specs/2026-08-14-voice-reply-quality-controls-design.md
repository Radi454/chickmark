# Voice Reply Quality + Playback Controls — Design

**Status:** Approved
**Follows:** `2026-08-14-assistant-voice-chat-design.md` (voice chat, shipped)

## Goal

Two refinements to the shipped voice chat: (1) better, correctly-pronounced
TTS — especially for Arabic; (2) play/pause/replay controls on voice replies.

## Server — TTS quality

- `supabase/functions/app-hatchery-agent/voice.ts`:
  - Model `tts-1` → `gpt-4o-mini-tts`; voice `alloy` → `ash`.
  - `synthesizeSpeech(text, config, language?)` gains an optional
    `language: 'en' | 'ar' | 'mixed'` param mapped to the API's
    `instructions` field: `ar` → speak natural, clear Egyptian Arabic;
    `mixed` → both languages naturally; `en`/absent → no instructions.
- `supabase/functions/app-hatchery-agent/index.ts`: pass the reply's
  already-computed `language` into the TTS call (via the injected
  `synthesizeSpeech` dep, whose signature gains the optional param).
- No app-facing contract change: response still `audioBase64` (mp3 base64).

## Client — playback controls

- `ChatMessage` gains a nullable `audioBase64` field. Memory-only: never
  parsed from `history` JSON, so reloaded conversations have no audio; only
  replies received this session are replayable.
- `AssistantProvider`:
  - Attaches the reply's audio to the assistant message it appends.
  - New API: `playMessageAudio(ChatMessage)`, `pausePlayback()`,
    `resumePlayback()`. Exposes `playingMessageId: String?` and
    `isPaused: bool`. Playing one message stops any other. Playback state
    resets when playback completes or `stop` cuts it.
  - Auto-play after a voice send unchanged (routes through the same
    message-playback path so the bubble's controls reflect it).
- `AssistantAudioPlayer` interface gains `pause()` and `resume()`
  (audioplayers `AudioPlayer.pause()`/`.resume()` natively).
- UI (`assistant_chat_screen.dart`): an assistant bubble whose message has
  audio renders a small control row under the text — play/pause toggle and
  a replay button. WhatsApp-voice-note style, reusing existing app colors.

## Out of scope

- Persisting reply audio across sessions / into history.
- Speed control, scrubbing, waveforms.
- Localizing the new control tooltips (matches the mic button's current
  hardcoded-English state; localization is a separate pass).

## Testing

- Server: `voice_test.ts` — instructions present for `ar`/`mixed`, absent
  for `en`; model/voice fields correct. `index_test.ts` — language passed
  through to the synth dep.
- Client: provider tests for play/pause/resume/replay state transitions and
  one-at-a-time playback; widget test for the control row appearing only on
  audio-bearing messages.

## Docs

`docs/LIVING_SPEC.md` voice sections updated; dated `docs/CHANGELOG.md`
entry. Same commit as the code.
