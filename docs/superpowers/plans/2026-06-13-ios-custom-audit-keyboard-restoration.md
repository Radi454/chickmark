# iOS Custom Audit Keyboard Restoration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the existing ChickMark custom keypad for native iOS audit numeric fields without changing ordinary text input.

**Architecture:** Change the shared adaptive platform policy so iOS follows the same existing custom-keypad path as Android. Keep the keypad component, focus handling, validation, and screen integrations unchanged.

**Tech Stack:** Flutter, Dart, Flutter widget tests

---

### Task 1: Lock Restored iOS Behavior

**Files:**
- Modify: `test/features/audits/audit_numeric_keyboard_test.dart`

- [ ] **Step 1: Replace the native-iOS expectation**

Update the iOS adaptive-mode test so tapping an audit numeric field expects one
`AuditNumericKeyboard`, a read-only backing `TextField`, and
`TextInputType.none`.

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
flutter test test/features/audits/audit_numeric_keyboard_test.dart \
  --plain-name 'adaptive mode keeps the custom keypad on iOS targets'
```

Expected: FAIL because adaptive iOS currently selects native numeric input.

### Task 2: Restore the Shared Platform Policy

**Files:**
- Modify: `lib/features/audits/widgets/audit_numeric_keyboard.dart`

- [ ] **Step 1: Route Android and iOS to the custom keypad**

Use the existing switch branch:

```dart
TargetPlatform.android || TargetPlatform.iOS => true,
```

- [ ] **Step 2: Run the focused iOS test**

Run the command from Task 1. Expected: PASS.

### Task 3: Document and Verify

**Files:**
- Modify: `docs/LIVING_SPEC.md`

- [ ] **Step 1: Update implemented behavior**

Document that native iOS and Android audit numeric fields use the ChickMark
keypad, while ordinary text fields and desktop numeric entry keep their current
system input behavior.

- [ ] **Step 2: Run focused regression tests**

Run:

```bash
flutter test \
  test/features/audits/audit_numeric_keyboard_test.dart \
  test/features/audits/audit_keyboard_dismiss_test.dart \
  test/features/audits/audit_session_navigation_test.dart \
  test/features/audits/weight_grid_widget_test.dart
```

Expected: all tests pass.

- [ ] **Step 3: Check formatting and diff**

Run:

```bash
dart format lib/features/audits/widgets/audit_numeric_keyboard.dart \
  test/features/audits/audit_numeric_keyboard_test.dart
git diff --check
```

Expected: formatting succeeds and no whitespace errors are reported.
