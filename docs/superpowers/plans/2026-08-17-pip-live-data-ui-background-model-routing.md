# Pip Live Data, UI, Background Audio, and Model Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Pip Live the same ChickMark data discipline as typed Pip, route
each Pip workload to its approved low-cost model, add a dedicated captioned Live
screen, and keep a user-started mobile call eligible to run while minimized or
locked.

**Architecture:** A shared Supabase `_shared` module owns workload model
defaults. The existing shared ChickMark policy crosses into Cloud Run as
validated, rendered configuration, just like the existing tool contract. The
Flutter `RealtimeVoiceController` remains the single call owner; a platform
background port and a dedicated route are presentation/lifecycle adapters around
it, not new audio or tool paths.

**Tech Stack:** Dart/Flutter, Provider, `flutter_webrtc`, Android Kotlin
foreground service, iOS `UIBackgroundModes`, Deno/TypeScript Supabase Edge
Functions, Deno Cloud Run Sideband, OpenAI Responses and Realtime APIs.

## Global Constraints

- Preserve the existing 32 tools, tool arguments, RBAC, authorization
  fingerprints, broker scope enforcement, Sideband ownership, tool budgets,
  ledgers, and conversation behavior.
- Keep Live speech-to-speech. Never route Live audio through standalone STT,
  text reasoning, or standalone TTS.
- Workload defaults are exactly: text/voice-note reasoning `gpt-5-nano`, Live
  `gpt-realtime-2.1-mini`, voice-note STT `gpt-4o-mini-transcribe`, voice-note
  TTS `gpt-4o-mini-tts`.
- Do not use the generic `OPENAI_MODEL` setting to change Pip chat because it
  also controls unrelated extraction. Introduce `OPENAI_TEXT_MODEL` as the
  optional operator override for the Pip conversational runtime.
- Keep web behavior working, but make no locked-screen/background guarantee for
  browsers.
- Preserve all unrelated dirty and staged changes. Before every edit, inspect
  the target's current diff. Never reset, restore, or overwrite user changes.
- Every meaningful implementation commit must include the matching current-state
  update to `docs/LIVING_SPEC.md` and a new top-of-file `2026-08-17` entry in
  `docs/CHANGELOG.md`. The orchestrator, not an implementation subagent, creates
  commits after reviewing exact staged hunks so the user's pre-existing staged
  migration renames remain untouched.
- User-facing English copy must receive an Arabic entry in the hand-written map
  in `lib/l10n/app_localizations.dart` in the same change.
- Do not mark the product task complete until the human reviewer explicitly
  approves the implemented result.

---

## File Map

### Shared backend routing

- Create `supabase/functions/_shared/pip_model_routing.ts`: one typed map of Pip
  workload defaults and the text-model environment resolver.
- Create `supabase/functions/_shared/pip_model_routing_test.ts`: exact default and
  override tests.
- Modify `supabase/functions/telegram-hatchery-agent/agent_provider.ts`: consume
  the shared text default.
- Modify `supabase/functions/telegram-hatchery-agent/index.ts`: prefer
  `OPENAI_TEXT_MODEL` only for conversational agent responses.
- Modify `supabase/functions/app-hatchery-agent/index.ts`: use the same text
  resolver for in-app typed and voice-note reasoning.
- Modify `supabase/functions/app-hatchery-agent/voice.ts`: use the shared STT/TTS
  defaults.
- Modify the neighboring provider, app-agent, and voice tests.

### Live policy and Realtime defaults

- Modify `supabase/functions/telegram-hatchery-agent/agent_prompt.ts`: add a
  policy version exported with `CHICKMARK_AGENT_POLICY`.
- Create
  `services/pip-realtime-sideband/tools/render_agent_instructions.ts`: render the
  shared policy and version for deployment.
- Modify `services/pip-realtime-sideband/src/config.ts`: require and validate the
  rendered instructions/version; default Realtime metadata to
  `gpt-realtime-2.1-mini`.
- Modify `services/pip-realtime-sideband/src/session_config.ts`: require nonempty
  instructions in every `session.update`.
- Modify `services/pip-realtime-sideband/src/server.ts`, `src/sideband.ts`, and
  `main.ts`: make instructions required across the existing chain.
- Create `services/pip-realtime-sideband/test/instruction_parity_test.ts` and
  update config/session/server tests and deployment documentation.
- Modify `supabase/functions/pip-realtime-session/config.ts` and its tests to use
  the shared Live default.

### Mobile background lifecycle

- Create `lib/services/realtime/realtime_background_service.dart`: injectable
  platform-neutral port plus MethodChannel implementation.
- Create `test/services/realtime/realtime_background_service_test.dart`.
- Modify `lib/features/chat/providers/realtime_voice_controller.dart` and its
  tests: activate once after mic permission, retain across the single recovery,
  stop on every terminal path, and honor Android notification End requests.
- Modify `lib/services/realtime/webrtc_realtime_transport.dart` and its tests:
  configure/release iOS `playAndRecord` + `voiceChat` through the existing
  `flutter_webrtc` API.
- Create
  `android/app/src/main/kotlin/com/hatchery/hatchaudit/PipRealtimeForegroundService.kt`.
- Modify Android `MainActivity.kt` and `AndroidManifest.xml` for the foreground
  service bridge, permissions, service type, and notification End action.
- Modify `ios/Runner/Info.plist` to declare background audio.

### Dedicated Live UI

- Create `lib/features/chat/screens/realtime_voice_screen.dart`.
- Create `lib/features/chat/widgets/realtime_voice_orb.dart`.
- Create `lib/features/chat/widgets/realtime_live_banner.dart`.
- Modify `lib/features/chat/screens/assistant_chat_screen.dart`: open/reopen the
  Live route instead of using the composer icon as an end button.
- Modify `lib/features/home/widgets/main_shell.dart`: shell-own the Realtime
  controller and display the compact return/end banner across tabs.
- Add widget tests and Arabic localization entries.

### Documentation, verification, and deployment

- Modify `docs/LIVING_SPEC.md`, `docs/CHANGELOG.md`,
  `docs/PIP_REALTIME_DEPLOYMENT.md`, and
  `services/pip-realtime-sideband/README.md`.
- Create `scripts/verify_pip_openai_models.sh` and a wrapper test under
  `test/security/` that checks the script contains no embedded credential and
  validates the four exact aliases supplied through `OPENAI_API_KEY`.

---

### Task 1: Add the internal workload model router and recorded-note defaults

**Files:**

- Create: `supabase/functions/_shared/pip_model_routing.ts`
- Create: `supabase/functions/_shared/pip_model_routing_test.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/agent_provider.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/agent_provider_test.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/index.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/index_test.ts`
- Modify: `supabase/functions/app-hatchery-agent/index.ts`
- Modify: `supabase/functions/app-hatchery-agent/index_test.ts`
- Modify: `supabase/functions/app-hatchery-agent/voice.ts`
- Modify: `supabase/functions/app-hatchery-agent/voice_test.ts`
- Modify: `docs/LIVING_SPEC.md`
- Modify: `docs/CHANGELOG.md`

**Interfaces:**

- Produces:

```ts
export const PIP_MODEL_DEFAULTS = Object.freeze({
  text: 'gpt-5-nano',
  live: 'gpt-realtime-2.1-mini',
  voiceNoteTranscription: 'gpt-4o-mini-transcribe',
  voiceNoteSpeech: 'gpt-4o-mini-tts',
})

export type PipModelEnvReader = (name: string) => string | undefined

export function resolvePipTextModel(
  env: PipModelEnvReader,
): string
```

- `resolvePipTextModel` returns trimmed `OPENAI_TEXT_MODEL` when set and
  otherwise `PIP_MODEL_DEFAULTS.text`. It never reads `OPENAI_MODEL` or
  `OPENROUTER_MODEL`.

- [ ] **Step 1: Write the shared routing tests**

```ts
Deno.test('Pip model defaults are pinned by workload', () => {
  assertEquals(PIP_MODEL_DEFAULTS, {
    text: 'gpt-5-nano',
    live: 'gpt-realtime-2.1-mini',
    voiceNoteTranscription: 'gpt-4o-mini-transcribe',
    voiceNoteSpeech: 'gpt-4o-mini-tts',
  })
})

Deno.test('text routing accepts only its workload-specific override', () => {
  const values = {
    OPENAI_TEXT_MODEL: '  account-approved-text  ',
    OPENAI_MODEL: 'unrelated-extraction-model',
  }
  assertEquals(resolvePipTextModel((name) => values[name]), 'account-approved-text')
  assertEquals(
    resolvePipTextModel((name) =>
      name === 'OPENAI_MODEL' ? 'unrelated-extraction-model' : undefined
    ),
    'gpt-5-nano',
  )
})
```

- [ ] **Step 2: Update existing provider and voice tests before implementation**

Add assertions that an OpenAI agent request without an explicit model sends
`gpt-5-nano`, that `OPENAI_TEXT_MODEL` reaches both app and Telegram
conversation providers, and that extraction continues using its existing
`OPENAI_MODEL` path. Change the multipart STT assertion from `whisper-1` to:

```ts
assertEquals(form.get('model'), 'gpt-4o-mini-transcribe')
```

Retain the existing TTS assertion:

```ts
assertEquals(body.model, 'gpt-4o-mini-tts')
```

- [ ] **Step 3: Run the failing tests**

Run:

```bash
deno test --allow-env --allow-net \
  supabase/functions/_shared/pip_model_routing_test.ts \
  supabase/functions/telegram-hatchery-agent/agent_provider_test.ts \
  supabase/functions/telegram-hatchery-agent/index_test.ts \
  supabase/functions/app-hatchery-agent/voice_test.ts \
  supabase/functions/app-hatchery-agent/index_test.ts
```

Expected: failures naming the missing router and the old
`gpt-4.1-mini`/`whisper-1` defaults.

- [ ] **Step 4: Implement the shared routing module and consumers**

Import `PIP_MODEL_DEFAULTS` in `agent_provider.ts` and replace the local OpenAI
default. In the app and Telegram `readAiConfig` functions, resolve the
conversation model with `resolvePipTextModel(Deno.env.get)` only when the
provider is OpenAI. Preserve explicit OpenRouter routing exactly as implemented.

In `voice.ts`, replace local model literals with the shared defaults:

```ts
const STT_MODEL = PIP_MODEL_DEFAULTS.voiceNoteTranscription
const TTS_MODEL = PIP_MODEL_DEFAULTS.voiceNoteSpeech
```

Do not change endpoint URLs, transcription parsing, TTS voice `ash`, language
instructions, tools, or agent request shape.

- [ ] **Step 5: Run the focused and shared-runtime tests**

Run the Step 3 command, then:

```bash
deno test --allow-env --allow-net \
  supabase/functions/telegram-hatchery-agent/agent_runtime_test.ts \
  supabase/functions/telegram-hatchery-agent/agent_acceptance_test.ts \
  supabase/functions/telegram-hatchery-agent/unified_agent_e2e_test.ts
```

Expected: all pass; tool count, tool arguments, response normalization, and
voice-note behavior are unchanged.

- [ ] **Step 6: Update current-behavior documentation**

Document the internal workload router, `OPENAI_TEXT_MODEL`, exact four defaults,
and the fact that recorded notes use the same reasoning route as typed text.
Add a newest-first `2026-08-17` changelog entry. Do not rewrite historical
`whisper-1` or `gpt-4.1-mini` entries.

- [ ] **Step 7: Orchestrator review and commit**

Review exact diffs, stage only Task 1 hunks plus its two documentation hunks,
and commit:

```bash
git commit -m "feat(pip): route workloads through low-cost defaults"
```

The user's already-staged migration renames must remain staged and absent from
this commit.

---

### Task 2: Give Live the shared ChickMark policy and aligned Realtime model

**Files:**

- Modify: `supabase/functions/telegram-hatchery-agent/agent_prompt.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/agent_prompt_test.ts`
- Create:
  `services/pip-realtime-sideband/tools/render_agent_instructions.ts`
- Create:
  `services/pip-realtime-sideband/test/instruction_parity_test.ts`
- Modify: `services/pip-realtime-sideband/src/config.ts`
- Modify: `services/pip-realtime-sideband/src/session_config.ts`
- Modify: `services/pip-realtime-sideband/src/server.ts`
- Modify: `services/pip-realtime-sideband/src/sideband.ts`
- Modify: `services/pip-realtime-sideband/main.ts`
- Modify: `services/pip-realtime-sideband/test/config_test.ts`
- Modify: `services/pip-realtime-sideband/test/sideband_test.ts`
- Modify: `services/pip-realtime-sideband/test/server_test.ts`
- Modify: `services/pip-realtime-sideband/test/tool_contract_test.ts`
- Modify: `supabase/functions/pip-realtime-session/config.ts`
- Modify: `supabase/functions/pip-realtime-session/config_test.ts`
- Modify: `services/pip-realtime-sideband/README.md`
- Modify: `docs/PIP_REALTIME_DEPLOYMENT.md`
- Modify: `docs/LIVING_SPEC.md`
- Modify: `docs/CHANGELOG.md`

**Interfaces:**

```ts
export const CHICKMARK_AGENT_POLICY_VERSION = '1.1.0'

export interface RealtimeConfig {
  // existing fields unchanged
  readonly instructions: string
  readonly instructionVersion: string
}

export function renderRealtimeInstructions(): string
export const RENDERED_INSTRUCTION_VERSION: string
```

`ServerDeps.instructions`, `SidebandOptions.instructions`, and
`buildSessionUpdate({ instructions })` become required nonempty strings. The
model-facing payload always contains `session.instructions`.

- [ ] **Step 1: Write failing parity and configuration tests**

The new parity suite imports the policy and renderer and asserts:

```ts
assertEquals(renderRealtimeInstructions(), CHICKMARK_AGENT_POLICY)
assertEquals(
  RENDERED_INSTRUCTION_VERSION,
  CHICKMARK_AGENT_POLICY_VERSION,
)
assertStringIncludes(renderRealtimeInstructions(), 'get_breed_benchmark')
assertStringIncludes(renderRealtimeInstructions(), 'state the breed and the age')
```

Extend Sideband `REQUIRED` test environment with:

```ts
PIP_REALTIME_INSTRUCTIONS: 'You are ChickMark.',
PIP_REALTIME_INSTRUCTIONS_VERSION: '1.1.0',
```

Test missing/blank instructions and version fail startup. Test the default model
is `gpt-realtime-2.1-mini`. Test `session.update.session.instructions` equals the
configured policy and is never omitted.

Update `pip-realtime-session/config_test.ts` to expect:

```ts
assertEquals(config.realtimeModel, 'gpt-realtime-2.1-mini')
```

- [ ] **Step 2: Run tests to prove the parity gap**

```bash
deno test --allow-env --allow-read --allow-net \
  services/pip-realtime-sideband/test/instruction_parity_test.ts \
  services/pip-realtime-sideband/test/config_test.ts \
  services/pip-realtime-sideband/test/sideband_test.ts \
  services/pip-realtime-sideband/test/server_test.ts \
  supabase/functions/pip-realtime-session/config_test.ts
```

Expected: fail because production-style server setup accepts no instructions and
the two Realtime defaults are still divergent.

- [ ] **Step 3: Implement the renderer and fail-fast configuration**

The renderer mirrors `render_tool_definitions.ts`. Its default output is the raw
policy. With `--json`, serialize the exact deployment values without flattening
the multiline policy:

```ts
console.log(JSON.stringify({
  PIP_REALTIME_INSTRUCTIONS_VERSION: CHICKMARK_AGENT_POLICY_VERSION,
  PIP_REALTIME_INSTRUCTIONS: renderRealtimeInstructions(),
}))
```

In `loadConfig`, use `requireString` for both fields. Do not add the instruction
text to startup logs or `safeConfigSnapshot`; log only the version. Pass
`config.instructions` from `main.ts` into the unchanged `RealtimeServer` path.

In the Supabase control plane, import `PIP_MODEL_DEFAULTS.live` and use it as
`PIP_REALTIME_DEFAULTS.realtimeModel`. Set the Sideband's independent metadata
default to the same exact alias and keep the parity test cross-deployment.

- [ ] **Step 4: Run the complete Sideband and Realtime-session suites**

```bash
deno test --allow-env --allow-read --allow-net \
  services/pip-realtime-sideband/test \
  supabase/functions/pip-realtime-session
```

Expected: all pass, including the 32-tool catalogue, broker ownership,
authoritative READY, persistence, cleanup, and no-pre-READY-audio contracts.

- [ ] **Step 5: Update deployment and living documentation**

Add the two instruction variables to Cloud Run inventory, show the renderer
command beside the tool renderer, require re-render on policy-version changes,
and replace stale `gpt-realtime`/`gpt-realtime-2.1` defaults with
`gpt-realtime-2.1-mini`. State that policy text must never be logged. Add a
newest-first changelog entry without altering the historical preflight record.

- [ ] **Step 6: Orchestrator review and commit**

Confirm the diff contains no tool contract, broker, RBAC, or prompt-content
change except adding the version export. Commit reviewed Task 2 hunks:

```bash
git commit -m "fix(pip): give Live the shared data policy"
```

---

### Task 3: Add mobile background-call lifecycle without moving WebRTC

**Files:**

- Create: `lib/services/realtime/realtime_background_service.dart`
- Create: `test/services/realtime/realtime_background_service_test.dart`
- Modify: `lib/features/chat/providers/realtime_voice_controller.dart`
- Modify: `test/features/chat/realtime_voice_controller_test.dart`
- Modify: `lib/services/realtime/webrtc_realtime_transport.dart`
- Modify: `test/services/realtime/webrtc_realtime_transport_test.dart`
- Create:
  `android/app/src/main/kotlin/com/hatchery/hatchaudit/PipRealtimeForegroundService.kt`
- Modify:
  `android/app/src/main/kotlin/com/hatchery/hatchaudit/MainActivity.kt`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `ios/Runner/Info.plist`
- Modify: `docs/LIVING_SPEC.md`
- Modify: `docs/CHANGELOG.md`

**Interfaces:**

```dart
abstract interface class RealtimeBackgroundPort {
  Stream<void> get endRequests;
  Future<void> activate();
  Future<void> deactivate();
  void dispose();
}

class PlatformRealtimeBackgroundService implements RealtimeBackgroundPort {
  static const MethodChannel channel =
      MethodChannel('com.chickmark/realtime_background');
}
```

`RealtimeVoiceController` adds an injectable `RealtimeBackgroundPort?` and a
single subscription to `endRequests`. Activation state belongs to the
user-initiated start, not to an individual recovery generation.

- [ ] **Step 1: Write the Dart background-port tests**

Use `TestDefaultBinaryMessengerBinding` to assert:

```dart
await service.activate();
expect(nativeCalls, ['activate']);

await service.deactivate();
expect(nativeCalls, ['activate', 'deactivate']);
```

Simulate `requestEnd` from native and assert one `endRequests` event. On web,
iOS, macOS, Windows, and Linux, the service methods are safe no-ops; iOS audio
background eligibility is configured by Info.plist and WebRTC audio session,
not an Android-style foreground service.

- [ ] **Step 2: Write controller lifecycle tests before integration**

Add a fake background port and prove:

- activation happens only after `openMicrophone` succeeds;
- activation happens once across the existing one automatic recovery;
- explicit stop, final error, notification End, and dispose each deactivate;
- a permission denial never activates;
- notification End calls the existing `stop()` path and records
  `RealtimeEndReason.userEnded`.

The key ordered assertion is:

```dart
expect(log.indexOf('openMicrophone'), lessThan(log.indexOf('background.activate')));
expect(log.indexOf('background.activate'), lessThan(log.indexOf('createSession')));
```

- [ ] **Step 3: Write WebRTC Apple-audio configuration tests**

Inject two callbacks into `WebRtcRealtimeTransport`:

```dart
typedef RealtimeConfigureCallAudio = Future<void> Function();
typedef RealtimeReleaseCallAudio = Future<void> Function();
```

Assert configuration happens before `getUserMedia`, and release happens after
`track.stop()` even when later teardown operations throw. The production
configuration uses the package's RTCAudioSession-aware helper:

```dart
Helper.setAppleAudioIOMode(AppleAudioIOMode.localAndRemote)
```

That maps the active call to Apple's play-and-record/voice-chat WebRTC audio
session. Release restores `AppleAudioIOMode.none` through the same helper. Do
not add a second audio-session package.

- [ ] **Step 4: Run failing Dart tests**

```bash
flutter test \
  test/services/realtime/realtime_background_service_test.dart \
  test/features/chat/realtime_voice_controller_test.dart \
  test/services/realtime/webrtc_realtime_transport_test.dart
```

Expected: missing background port and configuration callbacks.

- [ ] **Step 5: Implement the Dart lifecycle adapters**

Activate the background port after successful mic acquisition and before
session provisioning. Keep it active while the controller tears down and makes
its one automatic recovery attempt. Deactivate only when the user-started call
reaches idle/error/dispose. If activation fails, surface a bounded
`RealtimeTransportException` and do not create a billable Realtime session.

Register the native End callback once in the platform service constructor and
route it to the controller's existing `stop()`. Never give the background port
access to tokens, session IDs, SDP, audio, captions, tools, or RBAC state.

- [ ] **Step 6: Implement Android's foreground service and channel bridge**

`PipRealtimeForegroundService` defines:

```kotlin
const val ACTION_START = "com.chickmark.pip.realtime.START"
const val ACTION_STARTED = "com.chickmark.pip.realtime.STARTED"
const val ACTION_START_FAILED = "com.chickmark.pip.realtime.START_FAILED"
const val ACTION_END = "com.chickmark.pip.realtime.END"
const val ACTION_END_REQUESTED = "com.chickmark.pip.realtime.END_REQUESTED"
const val NOTIFICATION_CHANNEL_ID = "pip_live_call"
const val NOTIFICATION_ID = 2401
```

On START, create a low-importance channel, call `startForeground` immediately,
and post an ongoing notification titled `Pip Live` with body
`Live voice conversation in progress` and an `End` action. On END, broadcast
`ACTION_END_REQUESTED` inside the app package, remove the notification, and stop
the service.

`MainActivity.configureFlutterEngine` installs the MethodChannel. `activate`
starts the service while the activity is visible and completes only after the
service broadcasts `ACTION_STARTED`. Surface `ACTION_START_FAILED`, and fail
with a bounded five-second timeout if no acknowledgement arrives; never create
the Realtime session after a failed foreground-service start. `deactivate`
stops the service. A non-exported receiver forwards `ACTION_END_REQUESTED` to
Dart as `requestEnd`. Unregister the receiver and resolve any pending channel
result as an error in `cleanUpFlutterEngine`.

Manifest additions are exact:

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
```

```xml
<service
    android:name=".PipRealtimeForegroundService"
    android:exported="false"
    android:foregroundServiceType="microphone|mediaPlayback" />
```

Use immutable/update-current `PendingIntent` flags and do not export either the
service or receiver.

- [ ] **Step 7: Enable iOS background audio**

Add only the supported active-audio background mode:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

Do not add `voip`, CallKit, incoming-call handling, or unrestricted background
execution.

- [ ] **Step 8: Validate Dart and native builds**

```bash
flutter test \
  test/services/realtime/realtime_background_service_test.dart \
  test/features/chat/realtime_voice_controller_test.dart \
  test/services/realtime/webrtc_realtime_transport_test.dart
flutter build apk --debug
flutter build ios --debug --no-codesign
```

Expected: tests pass; Android manifest/service compiles; iOS build contains the
audio background mode and `flutter_webrtc` audio configuration compiles.

- [ ] **Step 9: Update docs and commit after review**

Document the user-started foreground-service notification, iOS audio mode,
session-limit/platform caveats, and terminal cleanup paths. Add the dated
changelog entry and commit reviewed Task 3 hunks:

```bash
git commit -m "feat(pip): keep Live calls active in background"
```

---

### Task 4: Build the dedicated captioned Live screen and minimized indicator

**Files:**

- Create: `lib/features/chat/screens/realtime_voice_screen.dart`
- Create: `lib/features/chat/widgets/realtime_voice_orb.dart`
- Create: `lib/features/chat/widgets/realtime_live_banner.dart`
- Modify: `lib/features/chat/screens/assistant_chat_screen.dart`
- Modify: `lib/features/home/widgets/main_shell.dart`
- Modify: `lib/l10n/app_localizations.dart`
- Create: `test/features/chat/realtime_voice_screen_test.dart`
- Modify: `test/features/chat/assistant_chat_screen_realtime_test.dart`
- Create: `test/features/home/realtime_live_banner_test.dart`
- Modify: `docs/LIVING_SPEC.md`
- Modify: `docs/CHANGELOG.md`

**Interfaces:**

```dart
class RealtimeVoiceScreen extends StatefulWidget {
  const RealtimeVoiceScreen({super.key, this.autoStart = false});
  final bool autoStart;
}

class RealtimeVoiceOrb extends StatefulWidget {
  const RealtimeVoiceOrb({super.key, required this.state});
  final RealtimeVoiceState state;
}

class RealtimeLiveBanner extends StatelessWidget {
  const RealtimeLiveBanner({
    super.key,
    required this.controller,
    required this.onOpen,
  });
  final RealtimeVoiceController controller;
  final VoidCallback onOpen;
}
```

- [ ] **Step 1: Write the Live screen widget tests**

With the existing fake Realtime transport/session/sideband, assert:

- `autoStart` opens one call and shows connecting state immediately;
- READY moves the screen to listening;
- user and assistant caption deltas replace the unfinished last caption and
  final captions remain as separate transcript rows;
- Arabic captions render with `TextDirection.rtl`;
- mute toggles controller state and semantics;
- minimize pops the route without calling `stop()`;
- End calls `stop()` and then pops;
- error and reconnect states show localized status and retry controls.

Use stable keys:

```text
pip-live-screen
pip-live-orb
pip-live-transcript
pip-live-mute
pip-live-minimize
pip-live-end
pip-live-retry
pip-live-banner
```

- [ ] **Step 2: Write assistant-entry and shell-banner tests**

Change the existing active-Live expectation: tapping the composer Live control
while a call is active reopens the screen and does not end it. Test switching to
another shell tab leaves the call active and displays `pip-live-banner`; tapping
the banner returns to the screen; its End action uses the same controller stop
path.

- [ ] **Step 3: Run the failing widget tests**

```bash
flutter test \
  test/features/chat/realtime_voice_screen_test.dart \
  test/features/chat/assistant_chat_screen_realtime_test.dart \
  test/features/home/realtime_live_banner_test.dart
```

Expected: missing widgets/routes and old tap-to-end behavior.

- [ ] **Step 4: Implement the screen and animation**

The screen watches the existing controller. It never creates a transport or
controller. Use an `AnimationController` with bounded scale/opacity/ring values;
state changes select animation intensity, not a new audio-level stream:

```dart
double intensityFor(RealtimeVoiceState state) => switch (state) {
  RealtimeVoiceState.userSpeaking => 1.0,
  RealtimeVoiceState.assistantSpeaking => 0.85,
  RealtimeVoiceState.thinking => 0.55,
  RealtimeVoiceState.listening => 0.25,
  _ => 0.1,
};
```

Display captions from `controller.captions` in an `AnimatedList` or keyed
`ListView`, using `TextDirectionDetector.detect(caption.text)`. Do not persist,
re-send, or copy them into `AssistantProvider.messages`.

- [ ] **Step 5: Lift only the Realtime controller to shell ownership**

Create one `RealtimeVoiceController` in `_MainShellState`, inject it into the
assistant tab with `ChangeNotifierProvider.value`, and dispose it with the
shell. Keep `AssistantProvider` scoped to the assistant tab. Wrap the shell body
in a listener/stack that shows the compact banner only when
`controller.isRealtimeActive` is true.

Opening Live pushes `RealtimeVoiceScreen` with the same controller. `autoStart`
is true only for a new call. Minimize is `Navigator.pop`; End awaits
`controller.stop()` before popping.

- [ ] **Step 6: Add every English string and Arabic map entry**

Add translations for at least:

```text
Pip Live
Listening
You are speaking
Pip is thinking
Pip is speaking
Connecting securely
Reconnecting
Live voice conversation in progress
Mute
Unmute
Minimize
Return to Pip Live
End live conversation
```

Tests must use `context.tr` output rather than hardcoding English-only labels.

- [ ] **Step 7: Run focused and surrounding UI tests**

```bash
flutter test test/features/chat/
flutter test test/features/home/
```

Expected: all pass, including existing typed chat, recorded voice, avatar,
composer gating, and shell navigation tests.

- [ ] **Step 8: Update docs and commit after review**

Document the dedicated screen, presentation-only captions, minimize/reopen
behavior, global banner, animation states, and unchanged recorded/Live mutual
exclusion. Add the changelog entry and commit:

```bash
git commit -m "feat(pip): add the Live conversation screen"
```

---

### Task 5: Prove endpoint isolation, validate production aliases, and deploy

**Files:**

- Create: `scripts/verify_pip_openai_models.sh`
- Create: `test/security/pip_openai_model_verification_test.dart`
- Modify: `supabase/functions/app-hatchery-agent/voice_test.ts`
- Modify: `supabase/functions/app-hatchery-agent/index_test.ts`
- Modify: `test/features/chat/assistant_provider_test.dart`
- Modify: `docs/PIP_REALTIME_DEPLOYMENT.md`
- Modify: `docs/LIVING_SPEC.md`
- Modify: `docs/CHANGELOG.md`

**Interfaces:**

`scripts/verify_pip_openai_models.sh` requires `OPENAI_API_KEY` and checks, in
this order:

```text
gpt-5-nano
gpt-realtime-2.1-mini
gpt-4o-mini-transcribe
gpt-4o-mini-tts
```

For each exact alias above, it calls `GET https://api.openai.com/v1/models/`
followed by that URL-encoded model ID. It prints only model ID and HTTP outcome,
never prints response headers or the key, and exits nonzero on the first
unavailable alias.

- [ ] **Step 1: Add explicit pipeline-count tests**

Using existing fetch seams, prove a recorded note performs one transcription,
one normal agent turn (including its tool loop), and at most one TTS request.
Add a Flutter test that a Live start uses only `RealtimeSessionPort`, signaling,
Sideband, and WebRTC fakes; its recorded-voice port counters remain zero.

The assertions are:

```ts
assertEquals(transcriptionRequests, 1)
assertEquals(agentResponseTurns, 1)
assertEquals(speechRequests, 1)
```

```dart
expect(recordedVoicePort.sendVoiceCalls, 0);
expect(realtimeSessionPort.calls, contains('createSession'));
```

- [ ] **Step 2: Implement and statically test the account preflight script**

The Dart security test reads the script and asserts all four exact aliases are
present, `OPENAI_API_KEY` is referenced only as an environment variable, and no
string matching `sk-` is embedded. It does not call the network.

- [ ] **Step 3: Run all repository-local verification**

```bash
deno test --allow-env --allow-read --allow-net \
  supabase/functions/_shared \
  supabase/functions/app-hatchery-agent \
  supabase/functions/telegram-hatchery-agent \
  supabase/functions/pip-realtime-session \
  supabase/functions/pip-realtime-tool-broker \
  services/pip-realtime-sideband/test
flutter test test/features/chat/ test/services/realtime/ \
  test/security/pip_openai_model_verification_test.dart
flutter analyze
```

Expected: all pass. If `gpt-5-nano` fails any agent acceptance/tool test, stop
for human review; do not silently substitute a model.

- [ ] **Step 4: Re-run account verification with the production key**

Read the key into a validated shell variable without printing it, then invoke:

```bash
OPENAI_API_KEY="${openai_key_value:?}" \
  scripts/verify_pip_openai_models.sh
```

Expected: four HTTP 200 outcomes. Unset the variable immediately afterward.

- [ ] **Step 5: Deploy Edge Functions and explicit production routing**

Using the linked project, deploy only affected functions:

```bash
supabase functions deploy app-hatchery-agent
supabase functions deploy telegram-hatchery-agent
supabase functions deploy pip-realtime-session
supabase secrets set AI_PROVIDER=openai OPENAI_TEXT_MODEL=gpt-5-nano \
  PIP_REALTIME_MODEL=gpt-realtime-2.1-mini
```

Do not change `OPENAI_MODEL`; it remains available for extraction. Do not deploy
or alter the tool broker because its code, tools, RBAC, and ownership did not
change.

- [ ] **Step 6: Deploy a new Sideband revision with rendered policy and tools**

Render both values from the reviewed commit and deploy
`pip-realtime-sideband` in project `chickmark-ai-agent`, region
`europe-west1`, preserving all existing secrets, URLs, budgets, concurrency,
timeout, min instances, cleanup audience, and service accounts. Update only:

```bash
policy_json="$(deno run --allow-read \
  services/pip-realtime-sideband/render_agent_instructions.ts --json)"
rendered_policy="$(jq -r '.PIP_REALTIME_INSTRUCTIONS' <<<"${policy_json:?}")"
rendered_policy_version="$(jq -r '.PIP_REALTIME_INSTRUCTIONS_VERSION' \
  <<<"${policy_json:?}")"
rendered_tools="$(deno run --allow-read \
  services/pip-realtime-sideband/render_tool_definitions.ts)"
```

Validate all four values are non-empty and the rendered tool array has exactly
32 entries before supplying them to the deployment command. The resulting
environment values must be:

```text
PIP_REALTIME_MODEL=gpt-realtime-2.1-mini
PIP_REALTIME_INSTRUCTIONS=${rendered_policy}
PIP_REALTIME_INSTRUCTIONS_VERSION=${rendered_policy_version}
PIP_REALTIME_TOOL_DEFINITIONS=${rendered_tools}
PIP_REALTIME_TOOL_CONTRACT_VERSION=1.0.0
```

Before traffic validation, describe the revision and assert the startup log
contains the expected model, instruction version, tool contract version, and
tool count 32. Logs must not contain instruction text.

- [ ] **Step 7: Run production smoke tests without exposing user data**

From an authorized test account/device:

1. Typed English BMK request for Ross 308 at 35 weeks.
2. Recorded Arabic voice-note request for the same breed/week.
3. Live English BMK request for the same breed/week.
4. Live Arabic BMK request using `روس 308` and age 35 weeks.
5. Live BMK request without an age.

Expected: the first four call `get_breed_benchmark`, state resolved breed and
week, and return database values; the fifth asks one focused age question. Query
only model/provider/tool names and counts to verify evidence—never print
transcripts, tool arguments, or results.

Confirm Live produces no request to `/audio/transcriptions` or `/audio/speech`
and recorded voice produces exactly its standalone STT/reasoning/TTS sequence.

- [ ] **Step 8: Complete the real-device background matrix**

Run the spec's iPhone and Android API 31/34/35 lock/Home/interruption/network
tests. Record pass/fail for two-way audio, captions, banner/notification,
return-to-call, BMK tool call, and resource release. A simulator-only result is
not sufficient for the background guarantee.

- [ ] **Step 9: Final documentation, review, and commit**

Update deployment docs with the actual revision and verified aliases, update
the living spec to only implemented behavior, and add a final newest-first
changelog entry. Run the high-effort Sol review over the complete diff and fix
all actionable findings. Commit only reviewed Task 5 hunks:

```bash
git commit -m "test(pip): verify Live routing and voice isolation"
```

Do not mark the product task complete. Hand the implementation and device-test
matrix to the human reviewer for explicit approval.
