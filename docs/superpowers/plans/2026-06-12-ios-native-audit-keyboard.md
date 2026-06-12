# iOS Native Audit Keyboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make adaptive audit numeric fields open the native iOS numeric keyboard while preserving Android's custom keypad and all existing numeric validation.

**Architecture:** Keep `AuditNumericField` and its formatter unchanged. Modify only the adaptive platform policy so native iOS follows the existing system-keyboard path, then update tests and implemented-behavior documentation. Deploy the signed release over `com.hatchery.hatchaudit` without uninstalling either ChickMark bundle.

**Tech Stack:** Flutter 3.44, Dart 3.12, Flutter widget tests, Xcode iOS release build, `devicectl`

---

### Task 1: Lock iOS and Android Platform Behavior

**Files:**
- Modify: `test/features/audits/audit_numeric_keyboard_test.dart`

- [ ] **Step 1: Change the iOS adaptive-mode test to require native system input**

Replace the current iOS test with:

```dart
testWidgets('adaptive mode uses native numeric input on iOS targets', (
  tester,
) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

  final controller = TextEditingController();
  addTearDown(controller.dispose);

  try {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuditNumericKeyboardScope(
            child: AuditNumericField(
              controller: controller,
              allowDecimal: true,
              allowNegative: true,
              maxDecimalPlaces: 1,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AuditNumericField));
    await tester.pumpAndSettle();

    expect(find.byType(AuditNumericKeyboard), findsNothing);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.readOnly, isFalse);
    expect(
      field.keyboardType,
      const TextInputType.numberWithOptions(decimal: true, signed: true),
    );

    await tester.enterText(find.byType(AuditNumericField), '12.3');
    await tester.pump();
    expect(controller.text, '12.3');

    await tester.enterText(find.byType(AuditNumericField), '12.34');
    await tester.pump();
    expect(controller.text, '12.3');
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
});
```

- [ ] **Step 2: Run the iOS test and verify it fails**

Run:

```bash
flutter test test/features/audits/audit_numeric_keyboard_test.dart \
  --plain-name 'adaptive mode uses native numeric input on iOS targets'
```

Expected: FAIL because adaptive iOS still renders `AuditNumericKeyboard`.

- [ ] **Step 3: Add an Android regression test**

Add:

```dart
testWidgets('adaptive mode keeps the custom keypad on Android targets', (
  tester,
) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;

  final controller = TextEditingController();
  addTearDown(controller.dispose);

  try {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuditNumericKeyboardScope(
            child: AuditNumericField(controller: controller),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AuditNumericField));
    await tester.pumpAndSettle();

    expect(find.byType(AuditNumericKeyboard), findsOneWidget);
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
});
```

- [ ] **Step 4: Run the Android test and verify the existing behavior passes**

Run:

```bash
flutter test test/features/audits/audit_numeric_keyboard_test.dart \
  --plain-name 'adaptive mode keeps the custom keypad on Android targets'
```

Expected: PASS.

### Task 2: Route Native iOS to System Input

**Files:**
- Modify: `lib/features/audits/widgets/audit_numeric_keyboard.dart`

- [ ] **Step 1: Make the minimal adaptive policy change**

Change `_defaultPlatformUsesCustomKeyboard()` so only Android uses the custom
keypad among native mobile targets:

```dart
return switch (defaultTargetPlatform) {
  TargetPlatform.android => true,
  TargetPlatform.fuchsia ||
  TargetPlatform.iOS ||
  TargetPlatform.linux ||
  TargetPlatform.macOS ||
  TargetPlatform.windows => false,
};
```

- [ ] **Step 2: Run the iOS and Android policy tests**

Run:

```bash
flutter test test/features/audits/audit_numeric_keyboard_test.dart
```

Expected: all tests pass, including native iOS system input, Android custom
input, desktop input, formatting, navigation, and overlay behavior.

- [ ] **Step 3: Run keyboard integration tests**

Run:

```bash
flutter test \
  test/features/audits/audit_keyboard_dismiss_test.dart \
  test/features/audits/audit_session_navigation_test.dart \
  test/features/audits/weight_grid_widget_test.dart
```

Expected: all tests pass.

### Task 3: Update Implemented-Behavior Documentation

**Files:**
- Modify: `docs/LIVING_SPEC.md`

- [ ] **Step 1: Update the station input behavior**

Replace the current statement that Android and iOS use the in-app keypad with:

```markdown
Audit numeric fields use a platform-adaptive input surface. Android targets
open the large in-app audit keypad with decimal, negative, backspace, next, and
grid-down actions. Native iOS targets use the system numeric keyboard so audit
entry remains available across visit-session focus and layout changes. Desktop
targets, including desktop web browsers, use normal editable text fields for
physical keyboard entry. All paths enforce the same numeric rules for decimal,
negative, and max-decimal-place limits.
```

- [ ] **Step 2: Add a dated change-log entry**

Add:

```markdown
- 2026-06-12: Switched adaptive native iOS audit numeric fields from the
  in-app overlay keypad to the system numeric keyboard, preventing focused
  fields from scrolling into view without presenting an input surface while
  preserving Android custom-keypad and desktop physical-keyboard behavior.
```

- [ ] **Step 3: Check formatting and repository diff**

Run:

```bash
dart format lib/features/audits/widgets/audit_numeric_keyboard.dart \
  test/features/audits/audit_numeric_keyboard_test.dart
git diff --check
git diff --stat
```

Expected: formatter succeeds, no whitespace errors, and only the planned source,
test, and living-spec files are modified.

### Task 4: Verify and Deploy to the Connected iPhone

**Files:**
- Verify: `lib/features/audits/widgets/audit_numeric_keyboard.dart`
- Verify: `test/features/audits/audit_numeric_keyboard_test.dart`
- Verify: `docs/LIVING_SPEC.md`

- [ ] **Step 1: Run focused final validation**

Run:

```bash
flutter test \
  test/features/audits/audit_numeric_keyboard_test.dart \
  test/features/audits/audit_keyboard_dismiss_test.dart \
  test/features/audits/audit_session_navigation_test.dart \
  test/features/audits/weight_grid_widget_test.dart
```

Expected: all tests pass.

- [ ] **Step 2: Build the signed iOS release**

Run:

```bash
flutter build ios --release --dart-define-from-file=.env
```

If Flutter reports the expected `build/ios/iphoneos/Runner.app` path missing but
Xcode succeeds, use the actual product at
`build/ios/Release-iphoneos/Runner.app`.

- [ ] **Step 3: Install over the current bundle without uninstalling**

Run:

```bash
xcrun devicectl device install app \
  --device 00008150-001D0DEE0CE1401C \
  /Users/ibrahimradi/Claude/ChickMark/build/ios/Release-iphoneos/Runner.app
```

Expected: installation succeeds for bundle ID `com.hatchery.hatchaudit`.

- [ ] **Step 4: Launch and verify the exact current bundle stays running**

Run:

```bash
xcrun devicectl device process launch \
  --device 00008150-001D0DEE0CE1401C \
  --terminate-existing \
  com.hatchery.hatchaudit
```

Then confirm the process path matches the current installation URL returned by
`devicectl device info apps`. Expected: the release process remains running.

- [ ] **Step 5: Commit the implementation**

Run:

```bash
git add \
  lib/features/audits/widgets/audit_numeric_keyboard.dart \
  test/features/audits/audit_numeric_keyboard_test.dart \
  docs/LIVING_SPEC.md \
  docs/superpowers/plans/2026-06-12-ios-native-audit-keyboard.md
git commit -m "fix: use native iOS audit keyboard"
```
