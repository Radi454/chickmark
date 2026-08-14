# Pip Agent Avatar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the in-app hatchery assistant the English-only name Pip across navigation and chat copy, with the approved clean ChickMark avatar in the conversation header, empty state, assistant messages, and thinking state.

**Architecture:** Build one deterministic 1024 × 1024 raster avatar from the existing ChickMark logo, then present it through a small stateless `AssistantAvatar` widget. `AssistantChatScreen` owns placement and localized copy while the widget owns clipping, size, semantics, and the fallback asset; no provider, database, sync, Edge Function, or prompt behavior changes.

**Tech Stack:** Flutter/Dart, Provider, hand-written `AppLocalizations`, Flutter widget tests, Pillow for deterministic asset composition.

## Global Constraints

- The conversational name is exactly `Pip`; the formal external identity is `Pip by ChickMark`.
- Keep `Pip` in Latin script in both English and Arabic interfaces. Never render `بيب`.
- Preserve the current yellow chick, blue cap, round glasses, smiling beak, wings, egg outline, and blue check.
- Do not add a star, sparkle, floating badge, circuit icon, right-side ornament, text, or wordmark to the avatar.
- The master asset is exactly 1024 × 1024 and uses only the existing ChickMark blue gradient, yellow chick, white field, and existing outline colors.
- Keep at least 10% canvas-safe margin around logo artwork so circular masks do not clip it.
- Assistant avatars are decorative in the header, message list, and thinking state; only the empty-state avatar receives the localized `ChickMark logo` semantic label.
- Preserve directional message layout so Arabic mirrors correctly.
- Preserve all chat provider, voice, network, retry, clear, and persistence behavior.
- Do not touch unrelated local changes.
- A meaningful code change updates `docs/LIVING_SPEC.md` and adds a newest-first `- 2026-08-14:` entry to `docs/CHANGELOG.md` in the same commit.

---

### Task 1: Add and integrate Pip's avatar identity

**Files:**

- Create: `assets/branding/chickmark-agent-avatar.png`
- Create: `lib/features/chat/widgets/assistant_avatar.dart`
- Create: `test/features/chat/assistant_avatar_test.dart`
- Modify: `pubspec.yaml`
- Modify: `lib/core/constants/app_strings.dart`
- Modify: `lib/l10n/app_localizations.dart`
- Modify: `lib/features/chat/screens/assistant_chat_screen.dart`
- Modify: `test/features/chat/assistant_chat_screen_test.dart`
- Modify: `docs/LIVING_SPEC.md`
- Modify: `docs/CHANGELOG.md`

**Interfaces:**

- Consumes: `ChickMarkLogo.assetPath`, `AppColors.brandGradient` color values, `GradientAppBar.titleLeading`, `ChatMessage.isUser`, and the existing injected `AssistantProvider` test seam.
- Produces: `const AssistantAvatar({Key? key, required double size, String? semanticLabel})`, `AssistantAvatar.assetPath`, and the Pip UI strings exposed through `AppStrings`.

- [ ] **Step 1: Write the failing reusable-avatar widget test**

Create `test/features/chat/assistant_avatar_test.dart` with a widget test that pumps:

```dart
const AssistantAvatar(size: 48, semanticLabel: 'ChickMark logo')
```

Assert all of the following consumer-visible behavior:

```dart
expect(find.byType(ClipOval), findsOneWidget);
final image = tester.widget<Image>(
  find.byKey(const ValueKey('assistant-avatar-image')),
);
expect((image.image as AssetImage).assetName, AssistantAvatar.assetPath);
expect(image.width, 48);
expect(image.height, 48);
expect(find.bySemanticsLabel('ChickMark logo'), findsOneWidget);
```

The production break this catches is replacing the dedicated asset, removing circular clipping, changing the requested size, or dropping the only non-decorative semantic label.

- [ ] **Step 2: Run the reusable-avatar test and verify RED**

Run:

```bash
flutter test test/features/chat/assistant_avatar_test.dart
```

Expected: compilation fails because `assistant_avatar.dart` and `AssistantAvatar` do not exist.

- [ ] **Step 3: Generate the deterministic master avatar**

Use Pillow against `assets/branding/chickmark-icon.png`; do not redraw or regenerate the mascot. Produce `assets/branding/chickmark-agent-avatar.png` with this exact composition:

```python
from pathlib import Path
from PIL import Image, ImageDraw
import math

size = 1024
inner = (7, 159, 224)   # AppColors.primaryLight
outer = (25, 63, 194)   # AppColors.primaryDark
canvas = Image.new('RGB', (size, size))
pixels = canvas.load()
cx, cy = size * 0.48, size * 0.40
max_distance = math.hypot(max(cx, size - cx), max(cy, size - cy))
for y in range(size):
    for x in range(size):
        t = min(1.0, math.hypot(x - cx, y - cy) / max_distance)
        pixels[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(inner, outer))

draw = ImageDraw.Draw(canvas)
draw.ellipse((82, 82, 942, 942), fill='white')

logo = Image.open('assets/branding/chickmark-icon.png').convert('RGBA')
logo.thumbnail((800, 800), Image.Resampling.LANCZOS)
x = (size - logo.width) // 2
y = (size - logo.height) // 2
canvas.paste(logo, (x, y), logo)
canvas.save('assets/branding/chickmark-agent-avatar.png', optimize=True)
```

Inspect the result visually. If any cap, glasses, wing, egg outline, or check is clipped, reduce only the `(800, 800)` thumbnail bound until every required element is inside the 102-pixel safe margin. Do not change colors or add decoration.

Validate the artifact:

```bash
python3 -c "from PIL import Image; p='assets/branding/chickmark-agent-avatar.png'; im=Image.open(p); assert im.size == (1024, 1024); assert im.mode in {'RGB', 'RGBA'}; print(im.size, im.mode)"
```

Expected: `(1024, 1024) RGB` or `(1024, 1024) RGBA`.

- [ ] **Step 4: Add the minimal reusable avatar widget and asset registration**

Add the asset to the existing `flutter.assets` list in `pubspec.yaml`.

Create `lib/features/chat/widgets/assistant_avatar.dart` with this public shape:

```dart
import 'package:hatchaudit/localized_material.dart';

import '../../../widgets/chick_mark_logo.dart';

class AssistantAvatar extends StatelessWidget {
  const AssistantAvatar({
    super.key,
    required this.size,
    this.semanticLabel,
  });

  static const assetPath =
      'assets/branding/chickmark-agent-avatar.png';

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final image = ClipOval(
      child: Image.asset(
        assetPath,
        key: const ValueKey('assistant-avatar-image'),
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) => Image.asset(
          ChickMarkLogo.assetPath,
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
    final label = semanticLabel;
    if (label == null) return ExcludeSemantics(child: image);
    return Semantics(
      label: context.tr(label),
      image: true,
      child: ExcludeSemantics(child: image),
    );
  }
}
```

Keep this widget presentation-only. Do not add provider state, animation, status variants, or network behavior.

- [ ] **Step 5: Run the reusable-avatar test and verify GREEN**

Run:

```bash
flutter test test/features/chat/assistant_avatar_test.dart
```

Expected: PASS with no warnings or exceptions.

- [ ] **Step 6: Write failing chat-screen identity tests**

Update `test/features/chat/assistant_chat_screen_test.dart` before changing production chat code.

Add keys used only to identify placement:

```dart
const _headerAvatarKey = ValueKey('assistant-header-avatar');
const _emptyAvatarKey = ValueKey('assistant-empty-avatar');
const _messageAvatarKey = ValueKey('assistant-message-avatar');
const _thinkingAvatarKey = ValueKey('assistant-thinking-avatar');
```

Change the empty-state test to assert:

```dart
expect(find.text('Pip'), findsOneWidget);
expect(find.text('Ask Pip'), findsOneWidget);
expect(find.byKey(_headerAvatarKey), findsOneWidget);
expect(find.byKey(_emptyAvatarKey), findsOneWidget);
expect(find.byIcon(Icons.forum_outlined), findsNothing);
```

In the two-turn history test, assert one assistant-message avatar and no avatar attached to the user turn:

```dart
expect(find.byKey(_messageAvatarKey), findsOneWidget);
```

In the thinking-state test, assert `Pip is thinking` and `_thinkingAvatarKey` appear only while the send is in flight.

Add a composer assertion:

```dart
final field = tester.widget<TextField>(find.byKey(_inputKey));
expect(field.decoration?.hintText, 'Ask Pip');
```

Extend `_pumpScreen` with `Locale locale = const Locale('en')`, pass it to `MaterialApp(locale: locale)`, and add an Arabic-locale test that asserts the header still contains the exact Latin-script text `Pip`, the Arabic empty-state heading contains `Pip`, and `find.textContaining('بيب')` finds nothing.

The production breaks these tests catch are restoring the generic assistant name, omitting a required avatar placement, attaching the avatar to user messages, or transliterating Pip in Arabic.

- [ ] **Step 7: Run the chat-screen tests and verify RED**

Run:

```bash
flutter test test/features/chat/assistant_chat_screen_test.dart
```

Expected: FAIL because the screen still says `Assistant`, `Ask the hatchery assistant`, `Ask the assistant`, and `Thinking`, and does not render `AssistantAvatar`.

- [ ] **Step 8: Implement Pip copy and all avatar placements**

In `lib/core/constants/app_strings.dart`, change and add:

```dart
static const String assistantTab = 'Pip';
static const String assistantEmptyTitle = 'Ask Pip';
static const String assistantComposerHint = 'Ask Pip';
static const String assistantThinking = 'Pip is thinking';
```

In `lib/l10n/app_localizations.dart`, replace the obsolete assistant-name keys used by this screen and add these exact mappings:

```dart
'Pip': 'Pip',
'Ask Pip': 'اسأل Pip',
'Pip is thinking': 'Pip يفكر',
```

Do not add `بيب` anywhere.

Import `../widgets/assistant_avatar.dart` in the chat screen and place avatars as follows:

- `GradientAppBar.titleLeading`: `AssistantAvatar(key: ValueKey('assistant-header-avatar'), size: 36)`.
- Empty state: replace `Icons.forum_outlined` with `AssistantAvatar(key: ValueKey('assistant-empty-avatar'), size: 88, semanticLabel: 'ChickMark logo')`.
- Assistant message only: put `AssistantAvatar(key: ValueKey('assistant-message-avatar'), size: 30)` before the assistant's existing message column inside a directional `Row`; retain the user's current layout without an avatar.
- Thinking state: put `AssistantAvatar(key: ValueKey('assistant-thinking-avatar'), size: 30)` before the existing spinner and localized `Pip is thinking` label.
- Composer: use `AppStrings.assistantComposerHint` when connected.

Use `AppStrings.assistantEmptyTitle` and `AppStrings.assistantThinking` rather than repeating string literals. Preserve current keys for clear, retry, input, send, mic, error, and thinking controls.

Constrain the assistant row to the same overall maximum width as before. Keep `AlignmentDirectional` and inherited `Directionality` so the avatar sits at the reading-start edge in both English and Arabic.

- [ ] **Step 9: Run the chat-screen tests and verify GREEN**

Run:

```bash
flutter test test/features/chat/assistant_chat_screen_test.dart
```

Expected: PASS, including voice, offline, retry, clear, English, and Arabic cases.

- [ ] **Step 10: Update living documentation in the same product commit**

In the current in-app assistant section of `docs/LIVING_SPEC.md`, add current-tense text stating that:

- the assistant is named Pip in both English and Arabic interfaces;
- the Arabic UI keeps `Pip` in Latin script;
- the clean ChickMark avatar appears in the chat header, empty state, assistant messages, and thinking state;
- user messages do not receive the avatar;
- the avatar is static and does not add a sparkle, badge, or other AI-brand symbol.

At the newest position in `docs/CHANGELOG.md`, add a `- 2026-08-14:` entry describing the same shipped behavior and why the name and clean logo treatment were chosen.

- [ ] **Step 11: Format and run focused verification**

Run:

```bash
dart format lib/core/constants/app_strings.dart lib/l10n/app_localizations.dart lib/features/chat/widgets/assistant_avatar.dart lib/features/chat/screens/assistant_chat_screen.dart test/features/chat/assistant_avatar_test.dart test/features/chat/assistant_chat_screen_test.dart
flutter test test/features/chat/assistant_avatar_test.dart test/features/chat/assistant_chat_screen_test.dart
flutter analyze lib/features/chat/widgets/assistant_avatar.dart lib/features/chat/screens/assistant_chat_screen.dart test/features/chat/assistant_avatar_test.dart test/features/chat/assistant_chat_screen_test.dart
git diff --check
```

Expected: formatting succeeds, both test files pass, analysis reports no issues, and `git diff --check` reports no whitespace errors.

- [ ] **Step 12: Self-review and commit only the task files**

Confirm:

- no source or translation contains `بيب`;
- the generated asset is 1024 × 1024 and visually preserves every required logo feature;
- only assistant turns receive message avatars;
- all Pip naming stays in Latin script;
- the living spec and changelog describe implemented behavior;
- unrelated working-tree changes are not staged.

Stage only the files listed under this task and commit:

```bash
git commit -m "feat(chat): introduce Pip agent identity"
```
