# Dashboard Station Collapse-State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep a dashboard station card collapsed after it scrolls off-screen and back during the current dashboard visit.

**Architecture:** `DashboardScreenState` owns a `Set<String>` of collapsed station identifiers because it outlives the scope section's temporary loading subtree. `ScopeInsightsSection` and its station cards become controlled views that receive expansion state and report toggle intents upward.

**Tech Stack:** Flutter, Provider, flutter_test widget tests

---

### Task 1: Reproduce the station-state reset

**Files:**
- Modify: `test/features/dashboard/dashboard_screen_test.dart`

- [x] **Step 1: Write the failing regression test**

Add a mobile widget test that pumps `DashboardScreen`, scrolls to the Egg Storage station header, taps it to collapse, simulates the scope loading transition activated by pull-to-refresh scrolling, and asserts the station's `AnimatedCrossFade.crossFadeState` remains `CrossFadeState.showFirst`.

- [x] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/dashboard/dashboard_screen_test.dart --plain-name "collapsed dashboard station stays collapsed after scrolling away and back"`

Expected: FAIL because the recreated `_StationCardState` initializes `_expanded` to `true`, producing `CrossFadeState.showSecond`.

### Task 2: Hoist expansion state to the dashboard screen

**Files:**
- Modify: `lib/features/dashboard/screens/dashboard_screen.dart`
- Modify: `lib/features/dashboard/widgets/scope/scope_insights_section.dart`
- Modify: `test/features/dashboard/scope_insights_hatch_layout_test.dart`

- [x] **Step 1: Add the dashboard-owned state**

Add `final Set<String> _collapsedScopeStations = <String>{};` and a `_toggleScopeStation(String station)` method that toggles membership inside `setState`.

- [x] **Step 2: Make the scope section controlled**

Require `collapsedStations` and `onStationToggle` on `ScopeInsightsSection`. Pass `expanded: !collapsedStations.contains(station)` and the toggle callback into each `_StationCard`. Convert `_StationCard` to a stateless controlled widget and remove its local `_expanded` field.

- [x] **Step 3: Update direct test harnesses**

Wrap direct `ScopeInsightsSection` usage in a small stateful test harness that owns the collapsed-station set and supplies the callback.

- [x] **Step 4: Run the regression test to verify it passes**

Run: `flutter test test/features/dashboard/dashboard_screen_test.dart --plain-name "collapsed dashboard station stays collapsed after scrolling away and back"`

Expected: PASS.

- [x] **Step 5: Run focused dashboard tests**

Run: `flutter test test/features/dashboard/dashboard_screen_test.dart test/features/dashboard/scope_insights_hatch_layout_test.dart`

Expected: all tests pass.

### Task 3: Document and validate the behavior

**Files:**
- Modify: `docs/LIVING_SPEC.md`

- [x] **Step 1: Document current-visit collapse persistence**

Add a dashboard behavior note stating that station cards preserve their expanded/collapsed state while scrolling during the current dashboard visit and reset on a new visit.

- [x] **Step 2: Analyze touched Dart files**

Run: `dart analyze lib/features/dashboard/screens/dashboard_screen.dart lib/features/dashboard/widgets/scope/scope_insights_section.dart test/features/dashboard/dashboard_screen_test.dart test/features/dashboard/scope_insights_hatch_layout_test.dart`

Expected: no issues found.

- [x] **Step 3: Check the focused diff**

Run: `git diff --check -- lib/features/dashboard/screens/dashboard_screen.dart lib/features/dashboard/widgets/scope/scope_insights_section.dart test/features/dashboard/dashboard_screen_test.dart test/features/dashboard/scope_insights_hatch_layout_test.dart docs/LIVING_SPEC.md`

Expected: no whitespace errors.
