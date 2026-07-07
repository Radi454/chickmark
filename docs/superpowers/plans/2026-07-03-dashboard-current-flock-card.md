# Dashboard Current Flock Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the selected flock's key details inside the dashboard filter card and let that whole card scroll away with the dashboard.

**Architecture:** Keep flock selection and data in `DashboardProvider`; derive the selected `FlockModel` in `DashboardScreen`. Move the existing filter card into the dashboard `ListView`, then render a responsive four-field details area inside that card only when one flock is selected.

**Tech Stack:** Flutter, Provider, Flutter widget tests, ChickMark `AppCard` and localization catalog.

---

### Task 1: Add the failing dashboard regression test

**Files:**
- Modify: `test/features/dashboard/dashboard_screen_test.dart`

- [x] **Step 1: Extend the static provider fixture**

Add `FlockModel` import, fixture fields, constructor parameters, and overrides:

```dart
final List<FlockModel> _testFlocks;
final String? _testSelectedFlockId;

@override
List<FlockModel> get flocks => _testFlocks;

@override
String? get selectedFlockId => _testSelectedFlockId;
```

- [x] **Step 2: Write the focused widget test**

Pump `DashboardScreen` with one selected flock whose entry date is exactly 70
days before today. Assert the screen contains `Name`, the flock id, `Current
age`, `10 weeks`, `Breed`, `Entrance date`, and the formatted entry date. Also
assert the `dashboard-filter-card` finder has a `ListView` ancestor and that no
layout exception is reported at a 390-by-844 viewport.

- [x] **Step 3: Run the test and verify RED**

Run:

```bash
flutter test test/features/dashboard/dashboard_screen_test.dart --plain-name "selected flock details share the scrolling filter card"
```

Expected: FAIL because `dashboard-filter-card` and the four-field detail area do not exist yet.

### Task 2: Implement the scrolling filter/details card

**Files:**
- Modify: `lib/features/dashboard/screens/dashboard_screen.dart`
- Modify: `lib/l10n/app_localizations.dart`

- [x] **Step 1: Move the filter card into scrollable content**

Change the scaffold body from a fixed `Column` to `_buildContent(...)`. Add
`_buildCascadeFilter(provider)` as the first child of the non-empty dashboard
`ListView`, and add the same card above the empty-state message within its
scrollable content. Give the `AppCard` this key:

```dart
key: const ValueKey('dashboard-filter-card'),
```

- [x] **Step 2: Render selected flock details inside the same card**

Resolve the selected flock by matching `provider.selectedFlockId` against
`provider.flocks`. Wrap the existing responsive filter layout in a `Column` and,
when a flock is found, append a divider and a responsive `Wrap` containing these
four icon-and-text fields:

```dart
_FlockDetailItem(label: 'Name', value: flock.flockId, icon: Icons.badge_outlined)
_FlockDetailItem(label: 'Current age', value: '${flock.currentAgeWeeks.toInt().clamp(0, 999)} weeks', icon: Icons.calendar_today_outlined)
_FlockDetailItem(label: 'Breed', value: flock.breed, icon: Icons.category_outlined)
_FlockDetailItem(label: 'Entrance date', value: HatchDateUtils.formatDisplayDate(flock.entryDate), icon: Icons.login_outlined)
```

Each item uses an available-width calculation from `LayoutBuilder`, standard
ChickMark spacing and text styles, and ellipsis for long values.

- [x] **Step 3: Preserve Arabic labels**

Add direct translations for `Name` and `Entrance date` to the existing `_ar`
catalog. Existing translation entries cover `Current age` and `Breed`, and the
existing dynamic pattern covers values such as `10 weeks`.

- [x] **Step 4: Run the test and verify GREEN**

Run:

```bash
flutter test test/features/dashboard/dashboard_screen_test.dart --plain-name "selected flock details share the scrolling filter card"
```

Expected: PASS with no overflow exception.

### Task 3: Document and verify the implemented behavior

**Files:**
- Modify: `docs/LIVING_SPEC.md`

- [x] **Step 1: Update the living spec**

Document that the Customer/Flock filter card now scrolls with dashboard content
and shows the selected flock's name, completed-week age, breed, and entrance
date in the same card.

- [x] **Step 2: Run focused verification**

Run:

```bash
flutter test test/features/dashboard/dashboard_screen_test.dart
dart analyze lib/features/dashboard/screens/dashboard_screen.dart lib/l10n/app_localizations.dart test/features/dashboard/dashboard_screen_test.dart
git diff --check -- lib/features/dashboard/screens/dashboard_screen.dart lib/l10n/app_localizations.dart test/features/dashboard/dashboard_screen_test.dart docs/LIVING_SPEC.md
```

Expected: all tests pass, analyzer reports no issues, and diff check prints no errors.
