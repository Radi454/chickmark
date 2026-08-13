# Telegram Agent Cloud-First Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Agent Monitor pause/resume update and verify Supabase before SQLite or the visible running/paused state changes.

**Architecture:** Extend the existing strict Supabase upsert path so callers can receive verified rows, then wrap it in a focused `TelegramAgentSettingsPort`. `AgentMonitorProvider` serializes requests, keeps the previous confirmed state during the cloud call, mirrors the returned row to SQLite, and only then publishes the new state.

**Tech Stack:** Dart 3.10.7, Flutter, Provider, sqflite/sqflite_common_ffi_web, Supabase Flutter/PostgREST, flutter_test.

## Global Constraints

- Current Flutter codebase is the primary source of truth.
- Supabase is authoritative for `agent_settings.telegram_enabled`.
- Never update visible state or SQLite to the requested value before cloud confirmation.
- Do not run the full application sync for this setting.
- Do not add migrations or change/deploy the Telegram Edge Function.
- Preserve unrelated local changes and commit only task-owned files.
- Update `docs/LIVING_SPEC.md` after the meaningful code change.
- Keep the existing approved-admin RLS boundary; do not add client secrets or service-role credentials.

---

## File Structure

- Create `lib/services/supabase/telegram_agent_settings_service.dart`: focused cloud control port, response validation, and safe exception.
- Modify `lib/services/supabase/supabase_service.dart`: expose verified rows from the existing strict upsert implementation.
- Create `test/services/supabase/telegram_agent_settings_service_test.dart`: payload, returned-value, malformed-response, and mismatch coverage.
- Modify `lib/data/repositories/hatchery_agent_repository.dart`: persist a cloud-confirmed settings row with synced local metadata.
- Modify `test/data/repositories/hatchery_agent_repository_test.dart`: verify confirmed settings are not left pending.
- Modify `lib/features/agents/providers/agent_monitor_provider.dart`: serialize and publish cloud-first state transitions.
- Modify `lib/features/agents/screens/agent_monitor_screen.dart`: disable refresh/toggle and retain the prior status while updating.
- Modify `test/features/agents/agent_monitor_provider_test.dart`: success, failure, ordering, confirmation, and repeated-call regression tests.
- Modify `test/features/agents/agent_monitor_screen_test.dart`: disabled/loading/prior-state widget behavior.
- Modify `docs/LIVING_SPEC.md`: document cloud authority and confirmed local mirroring.

---

### Task 1: Verified Targeted Supabase Settings Write

**Files:**
- Create: `lib/services/supabase/telegram_agent_settings_service.dart`
- Modify: `lib/services/supabase/supabase_service.dart:500-525, 935-975`
- Create: `test/services/supabase/telegram_agent_settings_service_test.dart`

**Interfaces:**
- Consumes: `SupabaseService.upsertRowsReturningStrict`, `toSupabaseUpsertPayload`, `AgentSettings.toMap`.
- Produces: `TelegramAgentSettingsPort.confirm(AgentSettings requested) -> Future<AgentSettings>` and `TelegramAgentSettingsService`.

- [ ] **Step 1: Write the failing service tests**

Create tests that capture the table/payload independently and return a literal Supabase row:

```dart
test('returns the cloud-confirmed agent setting', () async {
  String? table;
  List<Map<String, dynamic>>? rows;
  final service = TelegramAgentSettingsService(
    upsertRows: (name, values) async {
      table = name;
      rows = values;
      return [
        {
          'id': 1,
          'telegram_enabled': 1,
          'hatchability_warning_threshold_points': 4.0,
          'minimum_ready_confidence_pct': 90.0,
          'updated_at': '2026-08-13T18:00:00.000Z',
        },
      ];
    },
  );

  final confirmed = await service.confirm(
    AgentSettings(
      telegramEnabled: true,
      hatchabilityWarningThresholdPoints: 4,
      minimumReadyConfidencePct: 90,
      updatedAt: DateTime.utc(2026, 8, 13, 18),
    ),
  );

  expect(table, 'agent_settings');
  expect(rows!.single['telegramEnabled'], 1);
  expect(confirmed.telegramEnabled, isTrue);
  expect(confirmed.minimumReadyConfidencePct, 90);
});
```

Add these literal failure cases:

```dart
test('rejects a missing cloud confirmation row', () async {
  final service = TelegramAgentSettingsService(
    upsertRows: (_, _) async => const [],
  );

  await expectLater(
    service.confirm(const AgentSettings(telegramEnabled: true)),
    throwsA(isA<TelegramAgentSettingsException>()),
  );
});

test('rejects a cloud value different from the request', () async {
  final service = TelegramAgentSettingsService(
    upsertRows: (_, _) async => [
      {
        'id': 1,
        'telegram_enabled': 0,
        'hatchability_warning_threshold_points': 3.0,
        'minimum_ready_confidence_pct': 85.0,
        'updated_at': '2026-08-13T18:00:00.000Z',
      },
    ],
  );

  await expectLater(
    service.confirm(const AgentSettings(telegramEnabled: true)),
    throwsA(isA<TelegramAgentSettingsException>()),
  );
});

test('rejects malformed required cloud fields', () async {
  final service = TelegramAgentSettingsService(
    upsertRows: (_, _) async => [
      {
        'id': 1,
        'telegram_enabled': 'running',
        'hatchability_warning_threshold_points': 3.0,
        'minimum_ready_confidence_pct': 85.0,
        'updated_at': 'not-a-date',
      },
    ],
  );

  await expectLater(
    service.confirm(const AgentSettings(telegramEnabled: true)),
    throwsA(isA<TelegramAgentSettingsException>()),
  );
});
```

- [ ] **Step 2: Run the service test and verify RED**

Run:

```bash
flutter test test/services/supabase/telegram_agent_settings_service_test.dart
```

Expected: FAIL because `TelegramAgentSettingsService` and
`upsertRowsReturningStrict` do not exist.

- [ ] **Step 3: Expose returned rows from the existing strict upsert path**

Keep `upsertRowsStrict` source-compatible and add:

```dart
Future<List<Map<String, dynamic>>> upsertRowsReturningStrict(
  String table,
  List<Map<String, dynamic>> rows,
) async {
  if (rows.isEmpty) return const [];
  if (!await _prepareRemoteAccess()) {
    throw StateError('Supabase sync is not available');
  }
  return _upsertRowsWithFallback(
    table,
    rows,
    verifyAffectedRows: true,
    selectColumns: '*',
  );
}
```

Change `_upsertRowsWithFallback` to return selected rows using this contract:

```dart
Future<List<Map<String, dynamic>>> _upsertRowsWithFallback(
  String table,
  List<Map<String, dynamic>> rows, {
  bool verifyAffectedRows = false,
  String selectColumns = 'id',
}) async {
  final safeRows = rows
      .map((row) => _stripLocalOnlyColumns(table, row))
      .toList(growable: false);
  List<dynamic>? persistedRows;
  try {
    final request = _client.from(table).upsert(
      rows.map((row) => toSupabaseUpsertPayload(table, row)).toList(),
    );
    if (verifyAffectedRows) {
      persistedRows = await request.select(selectColumns);
    } else {
      await request;
    }
  } catch (_) {
    final request = _client.from(table).upsert(safeRows);
    if (verifyAffectedRows) {
      persistedRows = await request.select(selectColumns);
    } else {
      await request;
    }
  }
  if (verifyAffectedRows && persistedRows?.length != safeRows.length) {
    throw StateError(
      'Supabase did not persist every $table row '
      '(${persistedRows?.length ?? 0}/${safeRows.length})',
    );
  }
  return (persistedRows ?? const <dynamic>[])
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList(growable: false);
}
```

Existing callers continue ignoring the return value; strict callers still
verify the returned row count.

- [ ] **Step 4: Implement the focused settings port**

Create:

```dart
typedef TelegramAgentSettingsUpsert =
    Future<List<Map<String, dynamic>>> Function(
      String table,
      List<Map<String, dynamic>> rows,
    );

abstract interface class TelegramAgentSettingsPort {
  Future<AgentSettings> confirm(AgentSettings requested);
}

class TelegramAgentSettingsService implements TelegramAgentSettingsPort {
  TelegramAgentSettingsService({
    SupabaseService? supabaseService,
    TelegramAgentSettingsUpsert? upsertRows,
  }) : _upsertRows =
           upsertRows ??
           (supabaseService ?? SupabaseService()).upsertRowsReturningStrict;

  final TelegramAgentSettingsUpsert _upsertRows;

  @override
  Future<AgentSettings> confirm(AgentSettings requested) async {
    try {
      final rows = await _upsertRows('agent_settings', [requested.toMap()]);
      if (rows.length != 1) throw const FormatException('Expected one row');
      final confirmed = agentSettingsFromSupabaseRow(rows.single);
      if (confirmed.id != requested.id ||
          confirmed.telegramEnabled != requested.telegramEnabled) {
        throw const FormatException('Cloud setting did not match request');
      }
      return confirmed;
    } catch (_) {
      throw const TelegramAgentSettingsException(
        'Unable to update Telegram agent. Please try again.',
      );
    }
  }
}
```

Parse all five selected cloud fields strictly without model defaults:

```dart
AgentSettings agentSettingsFromSupabaseRow(Map<String, dynamic> row) {
  final id = row['id'];
  final enabled = row['telegram_enabled'];
  final warning = row['hatchability_warning_threshold_points'];
  final confidence = row['minimum_ready_confidence_pct'];
  final updatedText = row['updated_at']?.toString();
  final updatedAt = updatedText == null ? null : DateTime.tryParse(updatedText);
  if (id is! num ||
      enabled is! num ||
      (enabled != 0 && enabled != 1) ||
      warning is! num ||
      confidence is! num ||
      updatedAt == null) {
    throw const FormatException('Invalid agent settings confirmation');
  }
  return AgentSettings(
    id: id.toInt(),
    telegramEnabled: enabled == 1,
    hatchabilityWarningThresholdPoints: warning.toDouble(),
    minimumReadyConfidencePct: confidence.toDouble(),
    updatedAt: updatedAt.toUtc(),
  );
}
```

- [ ] **Step 5: Run the service test and verify GREEN**

Run:

```bash
dart format lib/services/supabase/telegram_agent_settings_service.dart lib/services/supabase/supabase_service.dart test/services/supabase/telegram_agent_settings_service_test.dart
flutter test test/services/supabase/telegram_agent_settings_service_test.dart test/services/supabase/supabase_service_security_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit the targeted cloud adapter**

```bash
git add lib/services/supabase/telegram_agent_settings_service.dart lib/services/supabase/supabase_service.dart test/services/supabase/telegram_agent_settings_service_test.dart
git commit -m "fix(agents): add confirmed Telegram settings write"
```

---

### Task 2: Cloud-First Provider and Local Mirror

**Files:**
- Modify: `lib/data/repositories/hatchery_agent_repository.dart:83-118`
- Modify: `lib/features/agents/providers/agent_monitor_provider.dart:14-55, 204-223`
- Modify: `test/data/repositories/hatchery_agent_repository_test.dart:140-175`
- Modify: `test/features/agents/agent_monitor_provider_test.dart:174-190, 560-640, 775-795`

**Interfaces:**
- Consumes: `TelegramAgentSettingsPort.confirm` from Task 1.
- Produces: `HatcheryAgentRepository.saveConfirmedSettings`, `AgentMonitorProvider.isUpdatingTelegram`, and serialized `setTelegramEnabled` behavior.

- [ ] **Step 1: Write failing repository and provider regressions**

Add this real-database repository test:

```dart
test('saveConfirmedSettings stores a synced cloud mirror', () async {
  final confirmed = AgentSettings(
    telegramEnabled: false,
    updatedAt: DateTime.utc(2026, 8, 13, 18),
  );

  await repository.saveConfirmedSettings(confirmed);
  final rows = await db.query(
    'agent_settings',
    where: 'id = ?',
    whereArgs: const [1],
  );

  expect(rows.single['telegramEnabled'], 0);
  expect(rows.single['syncStatus'], 'synced');
  expect(rows.single['dirtyAt'], isNull);
  expect(rows.single['lastSyncedAt'], isNotNull);
});
```

Add provider tests using a completer-backed fake port and an event-recording
fake repository. Cover:

```dart
test('resume confirms cloud before local and visible state', () async {
  final events = <String>[];
  final cloud = _FakeTelegramAgentSettingsPort(events: events);
  final repository = _FakeHatcheryAgentRepository(
    summaries: const [],
    settings: const AgentSettings(telegramEnabled: false),
    settingsEvents: events,
  );
  final provider = _providerFor(
    _adminUser(),
    repository,
    telegramSettingsPort: cloud,
  );
  await provider.load();

  final operation = provider.setTelegramEnabled(true);
  await Future<void>.delayed(Duration.zero);
  expect(provider.settings.telegramEnabled, isFalse);
  expect(provider.isUpdatingTelegram, isTrue);
  expect(events, ['cloud-start']);

  cloud.complete(telegramEnabled: true);
  await operation;
  expect(events, ['cloud-start', 'cloud-confirmed', 'local-confirmed']);
  expect(provider.settings.telegramEnabled, isTrue);
});
```

Use the same fixture for these exact additional assertions:

```dart
test('pause publishes only after cloud and local confirmation', () async {
  // Start Running, request false, and hold the cloud completer.
  expect(provider.settings.telegramEnabled, isTrue);
  expect(repository.settingsSaveCount, 0);
  cloud.complete(telegramEnabled: false);
  await operation;
  expect(repository.settingsSaveCount, 1);
  expect(provider.settings.telegramEnabled, isFalse);
});

test('resume cloud failure preserves paused local and provider state', () async {
  cloud.fail();
  await provider.setTelegramEnabled(true);
  expect(repository.settingsSaveCount, 0);
  expect(repository.settings.telegramEnabled, isFalse);
  expect(provider.settings.telegramEnabled, isFalse);
  expect(provider.error, 'Unable to update Telegram agent. Please try again.');
});

test('pause cloud failure preserves running local and provider state', () async {
  cloud.fail();
  await provider.setTelegramEnabled(false);
  expect(repository.settingsSaveCount, 0);
  expect(repository.settings.telegramEnabled, isTrue);
  expect(provider.settings.telegramEnabled, isTrue);
});

test('provider publishes threshold values returned by cloud', () async {
  cloud.complete(
    telegramEnabled: false,
    hatchabilityWarningThresholdPoints: 4,
    minimumReadyConfidencePct: 90,
  );
  await operation;
  expect(provider.settings.hatchabilityWarningThresholdPoints, 4);
  expect(provider.settings.minimumReadyConfidencePct, 90);
});

test('repeated requests while active create one cloud and local write', () async {
  final first = provider.setTelegramEnabled(false);
  await Future<void>.delayed(Duration.zero);
  await provider.setTelegramEnabled(false);
  await provider.setTelegramEnabled(true);
  expect(cloud.callCount, 1);
  cloud.complete(telegramEnabled: false);
  await first;
  expect(repository.settingsSaveCount, 1);
  expect(provider.settings.telegramEnabled, isFalse);
});
```

- [ ] **Step 2: Run provider/repository tests and verify RED**

Run:

```bash
flutter test test/data/repositories/hatchery_agent_repository_test.dart test/features/agents/agent_monitor_provider_test.dart
```

Expected: FAIL because the confirmed-save method, injected port, and updating
state do not exist and the old provider writes SQLite before cloud.

- [ ] **Step 3: Add confirmed local persistence**

Implement `saveConfirmedSettings` with the existing update/insert behavior and
these local-only fields:

```dart
{
  ...settings.toMap(),
  'syncStatus': 'synced',
  'dirtyAt': null,
  'lastSyncedAt': now,
  'syncError': null,
}
```

Keep `saveSettings` unchanged for ordinary offline pending writes.

- [ ] **Step 4: Implement the serialized provider transition**

Inject `TelegramAgentSettingsPort`, add `isUpdatingTelegram`, reject duplicate
or no-op requests, and retain the previous `_settings` until confirmation:

```dart
if (!canAccessMonitor ||
    _isUpdatingTelegram ||
    enabled == _settings.telegramEnabled) {
  return;
}
final token = ++_telegramUpdateToken;
_isUpdatingTelegram = true;
_error = null;
notifyListeners();
try {
  final confirmed = await _telegramSettingsPort.confirm(requested);
  if (token != _telegramUpdateToken) return;
  await _repository.saveConfirmedSettings(confirmed);
  if (token != _telegramUpdateToken) return;
  _settings = confirmed;
} catch (_) {
  if (token == _telegramUpdateToken) {
    _error = 'Unable to update Telegram agent. Please try again.';
  }
} finally {
  if (token == _telegramUpdateToken) {
    _isUpdatingTelegram = false;
    notifyListeners();
  }
}
```

Handle a local-cache exception after cloud success with a nested branch:

```dart
final confirmed = await _telegramSettingsPort.confirm(requested);
if (token != _telegramUpdateToken) return;
try {
  await _repository.saveConfirmedSettings(confirmed);
} catch (_) {
  if (token != _telegramUpdateToken) return;
  _settings = confirmed;
  _error =
      'Telegram updated, but the local cache could not be refreshed.';
  return;
}
if (token == _telegramUpdateToken) _settings = confirmed;
```

- [ ] **Step 5: Run provider/repository tests and verify GREEN**

Run:

```bash
dart format lib/data/repositories/hatchery_agent_repository.dart lib/features/agents/providers/agent_monitor_provider.dart test/data/repositories/hatchery_agent_repository_test.dart test/features/agents/agent_monitor_provider_test.dart
flutter test test/data/repositories/hatchery_agent_repository_test.dart test/features/agents/agent_monitor_provider_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit provider and local mirror behavior**

```bash
git add lib/data/repositories/hatchery_agent_repository.dart lib/features/agents/providers/agent_monitor_provider.dart test/data/repositories/hatchery_agent_repository_test.dart test/features/agents/agent_monitor_provider_test.dart
git commit -m "fix(agents): confirm Telegram state before local update"
```

---

### Task 3: Monitor Interaction, Living Spec, and Verification

**Files:**
- Modify: `lib/features/agents/screens/agent_monitor_screen.dart:68-105`
- Modify: `test/features/agents/agent_monitor_screen_test.dart:180-205, 650-690, 990-1090`
- Modify: `docs/LIVING_SPEC.md:2050-2070, 2700-2745`

**Interfaces:**
- Consumes: `AgentMonitorProvider.isUpdatingTelegram` from Task 2.
- Produces: disabled refresh/toggle and a loading indicator while preserving the prior confirmed state.

- [ ] **Step 1: Write the failing widget regression**

Inject a completer-backed `TelegramAgentSettingsPort`, start from Running, tap
Pause, and assert before completion:

```dart
expect(find.text('Telegram running'), findsOneWidget);
final button = tester.widget<IconButton>(
  find.byKey(const ValueKey('telegram-agent-toggle')),
);
expect(button.onPressed, isNull);
expect(find.byType(LinearProgressIndicator), findsOneWidget);
```

Complete and fail the cloud operation in separate widget tests:

```dart
cloud.complete(telegramEnabled: false);
await tester.pumpAndSettle();
expect(find.text('Telegram paused'), findsOneWidget);

// Separate test: cloud.fail() after tapping Pause.
await tester.pumpAndSettle();
expect(find.text('Telegram running'), findsOneWidget);
expect(
  find.text('Unable to update Telegram agent. Please try again.'),
  findsOneWidget,
);
```

- [ ] **Step 2: Run the screen test and verify RED**

Run:

```bash
flutter test test/features/agents/agent_monitor_screen_test.dart
```

Expected: FAIL because the screen does not use `isUpdatingTelegram` and the
old action publishes local state immediately.

- [ ] **Step 3: Wire the in-progress state into the screen**

Use `provider.isLoading || provider.isUpdatingTelegram` to disable both refresh
and the toggle. Show the existing `LinearProgressIndicator` for either state.
Continue deriving `_AgentStateBar` from `provider.settings.telegramEnabled`,
which remains the previous confirmed value until Task 2 completes.

- [ ] **Step 4: Update the living specification**

Add this implemented behavior to the Agent Monitor section and change log:

```text
Telegram agent running/paused status is cloud-authoritative. The monitor keeps
showing the previous confirmed state and disables the control while it performs
a targeted Supabase write. Only the returned cloud value is mirrored to SQLite
and published to the UI; a cloud failure preserves the prior state and reports
an error, so pause/resume no longer depends on an app restart.
```

- [ ] **Step 5: Run focused and broader verification**

Run:

```bash
dart format lib/services/supabase/telegram_agent_settings_service.dart lib/services/supabase/supabase_service.dart lib/data/repositories/hatchery_agent_repository.dart lib/features/agents/providers/agent_monitor_provider.dart lib/features/agents/screens/agent_monitor_screen.dart test/services/supabase/telegram_agent_settings_service_test.dart test/data/repositories/hatchery_agent_repository_test.dart test/features/agents/agent_monitor_provider_test.dart test/features/agents/agent_monitor_screen_test.dart
flutter test test/services/supabase/telegram_agent_settings_service_test.dart test/services/supabase/supabase_service_security_test.dart test/data/repositories/hatchery_agent_repository_test.dart test/features/agents/agent_monitor_provider_test.dart test/features/agents/agent_monitor_screen_test.dart test/integration/telegram_agent_monitor_cycle_test.dart
flutter test test/features/agents
flutter analyze
git diff --check
git diff --stat
git status --short
```

Expected: formatting succeeds; all listed tests pass; analyzer reports no new
issues; diff checks clean; only task-owned files appear in the task diff.

- [ ] **Step 6: Manually reason through the required lifecycle**

Confirm from the implemented call order:

```text
App starts Running -> Pause -> Supabase confirms Paused -> SQLite mirrors ->
Telegram webhook reads Paused -> Resume -> Supabase confirms Running -> SQLite
mirrors -> Telegram webhook reads Running, with no app restart.
```

- [ ] **Step 7: Commit the UI and documentation**

```bash
git add lib/features/agents/screens/agent_monitor_screen.dart test/features/agents/agent_monitor_screen_test.dart docs/LIVING_SPEC.md docs/superpowers/plans/2026-08-13-telegram-agent-cloud-first-toggle.md
git commit -m "fix(agents): make Telegram toggle cloud-authoritative"
```
