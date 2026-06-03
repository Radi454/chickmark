# Govee Synced Walk-through Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Change audit Govee capture so live readings guide the user, while saved evidence comes from synced device-history readings compressed to dashboard-ready summaries and 60 chart points.

**Architecture:** Add a small Govee history-sync boundary on `GoveeService`, then update `TemperatureRhProvider` audit-session capture to store start/end timestamps and summarize synced readings only. Keep saved data in the existing `temperature_sessions` and `temperature_readings` tables, adding spot/source metadata so future dashboards can draw room spot checkpoints.

**Tech Stack:** Flutter, Provider, sqflite, flutter_blue_plus, mocktail, flutter_test.

---

### Task 1: Add Synced-History Audit Capture Tests

**Files:**
- Modify: `test/features/temperature/temperature_rh_provider_test.dart`

- [ ] **Step 1: Write failing tests for synced history saving**

Add tests that stub `mockGovee.syncHistory(startedAt: any(named: 'startedAt'), endedAt: any(named: 'endedAt'))` and verify `stopAndSaveAuditSession()` saves summaries and compressed readings from synced values, not live preview values.

- [ ] **Step 2: Run the focused test**

Run: `flutter test test/features/temperature/temperature_rh_provider_test.dart`

Expected: FAIL because `GoveeService.syncHistory`, `spotLabel`, and synced-history audit saving are not implemented.

### Task 2: Add Metadata and Govee Sync Boundary

**Files:**
- Modify: `lib/services/govee/govee_service.dart`
- Modify: `lib/data/models/temperature_rh_model.dart`
- Modify: `lib/data/database/database_helper.dart`

- [ ] **Step 1: Add `GoveeService.syncHistory`**

Add a method returning `Future<List<GoveeSensorReading>>` for a start/end window. The default implementation logs a diagnostic and returns an empty list until device-memory protocol or CSV import is implemented.

- [ ] **Step 2: Add session metadata**

Add nullable `spotLabel` and `captureSource` fields to `TemperatureSessionModel`, `fromMap`, `toMap`, and `copyWith`.

- [ ] **Step 3: Add migration columns**

Add `spotLabel TEXT` and `captureSource TEXT` to the `temperature_sessions` create statement and `_addColumnIfMissing` migration block.

### Task 3: Switch Audit Capture to Synced Official Data

**Files:**
- Modify: `lib/features/temperature/providers/temperature_rh_provider.dart`
- Modify: `lib/features/audits/widgets/govee_recording_card.dart`

- [ ] **Step 1: Track audit session start/end and spot label**

Extend `startAuditSession` with optional `spotLabel`, store `startedAt`, and keep the existing live preview timer for display only.

- [ ] **Step 2: Sync official readings on stop**

In `stopAndSaveAuditSession`, call `GoveeService.syncHistory` with the audit start/end window. If no synced readings return, do not save a completed session and expose a sync error. If readings return, compute avg/min/max/CV, save max 60 compressed reading rows, save chart JSON, and mark `captureSource` as `govee_history_sync`.

- [ ] **Step 3: Pass spot label from UI**

Update `GoveeRecordingCard` to pass its visible `label` to `startAuditSession`.

### Task 4: Documentation and Verification

**Files:**
- Modify: `docs/LIVING_SPEC.md`

- [ ] **Step 1: Update living spec**

Document that audit Govee live readings are guidance only; official saved evidence comes from synced history and is compressed to summaries plus up to 60 chart points.

- [ ] **Step 2: Run verification**

Run: `flutter test test/features/temperature/temperature_rh_provider_test.dart`

Expected: PASS.
