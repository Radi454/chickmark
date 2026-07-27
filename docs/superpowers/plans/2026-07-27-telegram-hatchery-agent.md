# Telegram Hatchery Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Telegram-connected ChickMark AI agent that extracts hatchery data, asks staff for missing values, creates draft batches, calculates hatchability, checks history/BMK context, and lets the admin approve rows before cloud save.

**Architecture:** Add an additive local/Supabase data model for agent submissions and hatchery draft/final rows, then add a Supabase Edge Function for Telegram ingestion and AI extraction. The Flutter app gets an admin-only Agent Monitor that reads draft batches, exposes row-by-row review, and sends approval actions through repository/service boundaries.

**Tech Stack:** Dart 3.10.7, Flutter, Provider, sqflite/sqflite_common_ffi_web, Supabase Flutter, Supabase PostgreSQL migrations, Supabase Edge Functions on Deno TypeScript, Telegram Bot API webhooks, OpenAI Responses API with structured outputs and image input.

## Global Constraints

- Current Flutter codebase is the primary source of truth.
- Preserve unrelated local changes; do not revert files you did not touch.
- Prefer additive, migration-safe changes.
- Update `docs/LIVING_SPEC.md` after every meaningful code change.
- Use `http://127.0.0.1:57863` for Flutter web preview if a preview is needed.
- Telegram bot token must never be committed or embedded in app code.
- The already-shared Telegram token is compromised and must not be reused.
- Admin confirmation is required before final hatchery records, flock age, or master data updates.
- Staff can submit and answer Telegram questions, but cannot approve or save final records.
- Hatchability formula is exactly `Total production / Eggs placed * 100`.
- Historical hatchability warning threshold is 3 percentage points in either direction.
- Historical comparison key is customer, flock, station, and breed.
- BMK comparison uses breed and stored flock age.
- English and Arabic UI/bot copy are required.

---

## File Structure

Stage 1 creates the local and remote data foundation:

- Modify: `lib/data/database/database_helper.dart`
- Modify: `lib/data/database/database_schema.dart`
- Modify: `lib/data/database/database_migrations.dart`
- Create: `lib/data/models/hatchery_agent_models.dart`
- Create: `lib/data/repositories/hatchery_agent_repository.dart`
- Modify: `lib/data/repositories/performance_sync_repository.dart`
- Modify: `lib/services/supabase/startup_sync_service.dart`
- Create: `supabase/migrations/0018_telegram_hatchery_agent.sql`
- Modify: `scripts/check_supabase_secrets.sh`
- Test: `test/data/database/telegram_hatchery_agent_schema_test.dart`
- Test: `test/data/models/hatchery_agent_models_test.dart`
- Test: `test/data/repositories/hatchery_agent_repository_test.dart`
- Modify: `test/security/secret_scan_test.dart`

Stage 2 creates deterministic agent rules:

- Create: `lib/features/agents/services/hatchery_agent_rules.dart`
- Create: `test/features/agents/hatchery_agent_rules_test.dart`
- Modify: `lib/data/repositories/hatchery_agent_repository.dart`

Stage 3 creates the Telegram/AI backend:

- Create: `supabase/functions/telegram-hatchery-agent/index.ts`
- Create: `supabase/functions/telegram-hatchery-agent/extraction_schema.ts`
- Create: `supabase/functions/telegram-hatchery-agent/telegram.ts`
- Create: `supabase/functions/telegram-hatchery-agent/index_test.ts`
- Modify: `supabase/migrations/0018_telegram_hatchery_agent.sql`

Stage 4 creates the app monitor and draft review UI:

- Create: `lib/features/agents/providers/agent_monitor_provider.dart`
- Create: `lib/features/agents/screens/agent_monitor_screen.dart`
- Create: `lib/features/agents/widgets/agent_submission_card.dart`
- Create: `lib/features/agents/widgets/hatchery_draft_row_card.dart`
- Modify: `lib/features/home/widgets/main_shell.dart`
- Modify: `lib/core/constants/app_strings.dart`
- Modify: `lib/l10n/app_localizations.dart`
- Test: `test/features/agents/agent_monitor_provider_test.dart`
- Test: `test/features/agents/agent_monitor_screen_test.dart`
- Modify: `test/core/l10n/hardcoded_ui_strings_test.dart`

Stage 5 wires approval, final records, sync, docs, and end-to-end validation:

- Modify: `lib/data/models/hatchery_agent_models.dart`
- Modify: `lib/data/repositories/hatchery_agent_repository.dart`
- Modify: `lib/services/supabase/startup_sync_service.dart`
- Modify: `lib/features/agents/providers/agent_monitor_provider.dart`
- Modify: `lib/features/agents/screens/agent_monitor_screen.dart`
- Modify: `docs/LIVING_SPEC.md`
- Test: `test/features/agents/hatchery_agent_approval_test.dart`
- Test: `test/services/supabase/startup_sync_service_test.dart`

---

### Task 1: Agent Data Foundation

**Files:**
- Create: `lib/data/models/hatchery_agent_models.dart`
- Create: `lib/data/repositories/hatchery_agent_repository.dart`
- Modify: `lib/data/database/database_helper.dart`
- Modify: `lib/data/database/database_schema.dart`
- Modify: `lib/data/database/database_migrations.dart`
- Modify: `lib/data/repositories/performance_sync_repository.dart`
- Create: `supabase/migrations/0018_telegram_hatchery_agent.sql`
- Modify: `scripts/check_supabase_secrets.sh`
- Test: `test/data/database/telegram_hatchery_agent_schema_test.dart`
- Test: `test/data/models/hatchery_agent_models_test.dart`
- Test: `test/data/repositories/hatchery_agent_repository_test.dart`
- Modify: `test/security/secret_scan_test.dart`

**Interfaces:**
- Consumes: existing `DatabaseHelper`, `BenchmarkLookup`, `FlockModel`, `HatcheryModel`, Supabase camelCase/snake_case sync helpers.
- Produces:
  - `AgentSubmissionStatus.fromStorage(Object? value)`
  - `HatcheryDraftRowStatus.fromStorage(Object? value)`
  - `AgentSourceKind.fromStorage(Object? value)`
  - `HatcheryAgentSubmission.fromMap(Map<String, Object?> map)`
  - `HatcheryDraftBatch.fromMap(Map<String, Object?> map)`
  - `HatcheryDraftRow.fromMap(Map<String, Object?> map)`
  - `HatcheryAgentQuestion.fromMap(Map<String, Object?> map)`
  - `AgentSettings.fromMap(Map<String, Object?> map)`
  - `HatcheryAgentRepository.createSubmissionGraph(...)`
  - `HatcheryAgentRepository.loadSettings()`
  - `HatcheryAgentRepository.saveSettings(AgentSettings settings)`
  - `HatcheryAgentRepository.listBatchSummaries()`
  - `HatcheryAgentRepository.loadBatchDetails(String batchId)`
  - `HatcheryAgentRepository.previousApprovedComparable(...)`

- [ ] **Step 1: Write the failing schema test**

Add `test/data/database/telegram_hatchery_agent_schema_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDirectory;

  setUpAll(() async {
    databaseDirectory = await useIsolatedAppDatabase();
  });

  setUp(resetAppDatabase);

  tearDownAll(() async {
    await resetAppDatabase();
    if (databaseDirectory.existsSync()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  test('fresh database exposes v52 Telegram hatchery agent tables', () async {
    final db = await DatabaseHelper().db;

    expect(await _userVersion(db), 52);
    expect(await _tableNames(db), containsAll(const <String>[
      'telegram_staff_links',
      'agent_settings',
      'agent_submissions',
      'agent_questions',
      'hatchery_draft_batches',
      'hatchery_draft_rows',
      'hatchery_agent_audit_events',
      'hatchery_daily_records',
    ]));
    expect(await _columnNames(db, 'hatchery_draft_rows'), containsAll(const [
      'customerName',
      'flockName',
      'stationName',
      'breed',
      'eggsPlaced',
      'totalProduction',
      'hatchabilityPct',
      'confidencePct',
      'warningsJson',
      'status',
    ]));
    expect(await _indexNames(db), containsAll(const [
      'idx_agent_submissions_status',
      'idx_hatchery_draft_rows_batch',
      'idx_hatchery_daily_records_comparable',
    ]));
  });
}

Future<int> _userVersion(Database db) async {
  final rows = await db.rawQuery('PRAGMA user_version');
  return rows.single['user_version']! as int;
}

Future<Set<String>> _tableNames(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  );
  return rows.map((row) => row['name']! as String).toSet();
}

Future<Set<String>> _columnNames(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((row) => row['name']! as String).toSet();
}

Future<Set<String>> _indexNames(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'index'",
  );
  return rows.map((row) => row['name']! as String).toSet();
}
```

- [ ] **Step 2: Run the schema test and verify it fails**

Run:

```bash
flutter test test/data/database/telegram_hatchery_agent_schema_test.dart
```

Expected: FAIL because the database is still version 51 and the new tables do not exist.

- [ ] **Step 3: Add local table creation**

In `lib/data/database/database_schema.dart`, add `_createHatcheryAgentTables(DatabaseExecutor db)`:

```dart
Future<void> _createHatcheryAgentTables(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS telegram_staff_links (
    id TEXT PRIMARY KEY,
    telegramUserId TEXT NOT NULL UNIQUE,
    telegramChatId TEXT,
    displayName TEXT,
    username TEXT,
    status TEXT NOT NULL DEFAULT 'allowed',
    invitedBy TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT
  )''');

  await db.execute('''CREATE TABLE IF NOT EXISTS agent_settings (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    telegramEnabled INTEGER NOT NULL DEFAULT 1,
    hatchabilityWarningThresholdPoints REAL NOT NULL DEFAULT 3.0,
    minimumReadyConfidencePct REAL NOT NULL DEFAULT 85.0,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT
  )''');

  await db.execute('''CREATE TABLE IF NOT EXISTS agent_submissions (
    id TEXT PRIMARY KEY,
    telegramUpdateId TEXT UNIQUE,
    telegramMessageId TEXT,
    telegramChatId TEXT,
    telegramUserId TEXT,
    staffLinkId TEXT,
    sourceKind TEXT NOT NULL,
    sourceText TEXT,
    sourceFileName TEXT,
    sourceMimeType TEXT,
    sourceRemotePath TEXT,
    status TEXT NOT NULL,
    errorMessage TEXT,
    submittedAt TEXT NOT NULL,
    processedAt TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (staffLinkId) REFERENCES telegram_staff_links(id) ON DELETE SET NULL
  )''');

  await db.execute('''CREATE TABLE IF NOT EXISTS agent_questions (
    id TEXT PRIMARY KEY,
    submissionId TEXT NOT NULL,
    rowOrdinal INTEGER,
    fieldKey TEXT NOT NULL,
    questionTextEn TEXT NOT NULL,
    questionTextAr TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'open',
    answerText TEXT,
    answeredAt TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (submissionId) REFERENCES agent_submissions(id) ON DELETE CASCADE
  )''');

  await db.execute('''CREATE TABLE IF NOT EXISTS hatchery_draft_batches (
    id TEXT PRIMARY KEY,
    submissionId TEXT NOT NULL,
    status TEXT NOT NULL,
    sourceSummary TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (submissionId) REFERENCES agent_submissions(id) ON DELETE CASCADE
  )''');

  await db.execute('''CREATE TABLE IF NOT EXISTS hatchery_draft_rows (
    id TEXT PRIMARY KEY,
    batchId TEXT NOT NULL,
    rowOrdinal INTEGER NOT NULL,
    status TEXT NOT NULL,
    customerId TEXT,
    customerName TEXT,
    flockId TEXT,
    flockName TEXT,
    hatcheryId TEXT,
    stationName TEXT,
    breed TEXT,
    eggsPlaced INTEGER,
    productionDate TEXT,
    placementDate TEXT,
    eggWeightG REAL,
    fertilityPct REAL,
    transferWeightG REAL,
    setterNumber TEXT,
    hatcherNumber TEXT,
    hatchDate TEXT,
    healthyChicks INTEGER,
    secondGradeChicks INTEGER,
    condemnedChicks INTEGER,
    totalProduction INTEGER,
    hatchabilityPct REAL,
    confidencePct REAL,
    extractionJson TEXT,
    warningsJson TEXT,
    proposedFlockAgeWeeks INTEGER,
    approvedRecordId TEXT,
    reviewedBy TEXT,
    reviewedAt TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (batchId) REFERENCES hatchery_draft_batches(id) ON DELETE CASCADE
  )''');

  await db.execute('''CREATE TABLE IF NOT EXISTS hatchery_agent_audit_events (
    id TEXT PRIMARY KEY,
    submissionId TEXT NOT NULL,
    rowId TEXT,
    actorType TEXT NOT NULL,
    actorId TEXT,
    eventType TEXT NOT NULL,
    detailsJson TEXT,
    createdAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (submissionId) REFERENCES agent_submissions(id) ON DELETE CASCADE,
    FOREIGN KEY (rowId) REFERENCES hatchery_draft_rows(id) ON DELETE SET NULL
  )''');

  await db.execute('''CREATE TABLE IF NOT EXISTS hatchery_daily_records (
    id TEXT PRIMARY KEY,
    sourceDraftRowId TEXT,
    customerId TEXT NOT NULL,
    flockId TEXT NOT NULL,
    hatcheryId TEXT,
    stationName TEXT NOT NULL,
    breed TEXT NOT NULL,
    eggsPlaced INTEGER NOT NULL,
    productionDate TEXT,
    placementDate TEXT,
    eggWeightG REAL,
    fertilityPct REAL,
    transferWeightG REAL,
    setterNumber TEXT,
    hatcherNumber TEXT,
    hatchDate TEXT NOT NULL,
    healthyChicks INTEGER,
    secondGradeChicks INTEGER,
    condemnedChicks INTEGER,
    totalProduction INTEGER NOT NULL,
    hatchabilityPct REAL NOT NULL,
    approvedBy TEXT,
    approvedAt TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (sourceDraftRowId) REFERENCES hatchery_draft_rows(id) ON DELETE SET NULL,
    FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE,
    FOREIGN KEY (flockId) REFERENCES flocks(id) ON DELETE CASCADE,
    FOREIGN KEY (hatcheryId) REFERENCES hatcheries(id) ON DELETE SET NULL
  )''');

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_agent_submissions_status ON agent_submissions (status, submittedAt DESC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_agent_questions_submission ON agent_questions (submissionId, status)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_hatchery_draft_rows_batch ON hatchery_draft_rows (batchId, rowOrdinal)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_hatchery_daily_records_comparable ON hatchery_daily_records (customerId, flockId, stationName, breed, hatchDate DESC)',
  );
}
```

Call `_createHatcheryAgentTables(db)` from `_onCreate`, add the new tables to `DatabaseHelper._criticalTables`, and add column checks for the most important columns in `_criticalColumns`.

- [ ] **Step 4: Add v52 migration**

In `lib/data/database/database_helper.dart`, change database version from `51` to `52`.

In `lib/data/database/database_migrations.dart`, add:

```dart
Future<void> _applyV52Upgrade(Database db) async {
  await _createHatcheryAgentTables(db);
}
```

In `_onUpgrade`, add:

```dart
if (oldVersion < 52) {
  await _applyV52Upgrade(db);
}
```

- [ ] **Step 5: Add model round-trip tests**

Add `test/data/models/hatchery_agent_models_test.dart` with one test per key model:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/hatchery_agent_models.dart';

void main() {
  test('draft row round-trips all hatchery extraction fields', () {
    final row = HatcheryDraftRow(
      id: 'row-1',
      batchId: 'batch-1',
      rowOrdinal: 1,
      status: HatcheryDraftRowStatus.needsReview,
      customerName: 'Al Salehia',
      flockName: 'Ross 1',
      stationName: 'Station A',
      breed: 'Ross',
      eggsPlaced: 19200,
      productionDate: DateTime.utc(2025, 12, 9),
      placementDate: DateTime.utc(2025, 12, 11),
      eggWeightG: 67,
      fertilityPct: 92,
      transferWeightG: 63,
      setterNumber: '6',
      hatcherNumber: '6',
      hatchDate: DateTime.utc(2026, 1, 1),
      healthyChicks: 11400,
      secondGradeChicks: 105,
      condemnedChicks: 13,
      totalProduction: 11518,
      hatchabilityPct: 59.989583333333336,
      confidencePct: 94,
      warningsJson: '[{"kind":"historical_change"}]',
    );

    final copy = HatcheryDraftRow.fromMap(row.toMap());

    expect(copy.customerName, 'Al Salehia');
    expect(copy.eggsPlaced, 19200);
    expect(copy.totalProduction, 11518);
    expect(copy.hatchabilityPct, closeTo(59.9895, 0.0001));
    expect(copy.status, HatcheryDraftRowStatus.needsReview);
  });
}
```

- [ ] **Step 6: Implement models**

Create `lib/data/models/hatchery_agent_models.dart` with enums and map helpers. Use string `storageKey` values:

```dart
enum AgentSubmissionStatus {
  received('received'),
  processing('processing'),
  waitingForStaffAnswer('waiting_for_staff_answer'),
  draftReady('draft_ready'),
  needsAdminReview('needs_admin_review'),
  partiallyApproved('partially_approved'),
  approved('approved'),
  rejected('rejected'),
  failed('failed');
  // storageKey + fromStorage implementation.
}
```

Repeat the same pattern for:

```dart
enum HatcheryDraftRowStatus { pending, needsReview, approved, rejected }
enum AgentSourceKind { text, image, pdf, spreadsheet, file }
enum AgentQuestionStatus { open, answered, closed }
```

Use nullable dates parsed through:

```dart
DateTime? _date(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

String? _dateText(DateTime? value) => value?.toUtc().toIso8601String();
```

Expose immutable model classes:

```dart
class HatcheryAgentSubmission { /* fields matching agent_submissions */ }
class HatcheryAgentQuestion { /* fields matching agent_questions */ }
class HatcheryDraftBatch { /* fields matching hatchery_draft_batches */ }
class HatcheryDraftRow { /* fields matching hatchery_draft_rows */ }
class HatcheryAgentAuditEvent { /* fields matching hatchery_agent_audit_events */ }
class HatcheryDailyRecord { /* fields matching hatchery_daily_records */ }
class HatcheryHistoricalPoint { /* record id, hatchDate, hatchabilityPct */ }
class AgentSettings { /* telegramEnabled, hatchabilityWarningThresholdPoints, minimumReadyConfidencePct */ }
```

- [ ] **Step 7: Add repository tests**

Add `test/data/repositories/hatchery_agent_repository_test.dart`:

```dart
test('createSubmissionGraph stores one batch with multiple rows', () async {
  final repo = HatcheryAgentRepository(uuid: const UuidValueFactoryForTest());
  await _seedCustomerFlockHatchery();

  await repo.createSubmissionGraph(
    submission: _submission(id: 'submission-1'),
    batch: _batch(id: 'batch-1', submissionId: 'submission-1'),
    rows: [
      _row(id: 'row-1', batchId: 'batch-1', rowOrdinal: 1),
      _row(id: 'row-2', batchId: 'batch-1', rowOrdinal: 2),
    ],
    questions: const [],
    events: const [],
  );

  final details = await repo.loadBatchDetails('batch-1');

  expect(details, isNotNull);
  expect(details!.rows, hasLength(2));
  expect(details.rows.map((row) => row.rowOrdinal), [1, 2]);
});
```

Use local helper methods in the test file to seed `customers`, `flocks`, and `hatcheries` directly into the test database.

- [ ] **Step 8: Implement repository**

Create `lib/data/repositories/hatchery_agent_repository.dart`.

Required public methods:

```dart
Future<void> createSubmissionGraph({
  required HatcheryAgentSubmission submission,
  required HatcheryDraftBatch batch,
  required List<HatcheryDraftRow> rows,
  List<HatcheryAgentQuestion> questions = const [],
  List<HatcheryAgentAuditEvent> events = const [],
});

Future<AgentSettings> loadSettings();

Future<void> saveSettings(AgentSettings settings);

Future<List<HatcheryDraftBatchSummary>> listBatchSummaries();

Future<HatcheryDraftBatchDetails?> loadBatchDetails(String batchId);

Future<HatcheryHistoricalPoint?> previousApprovedComparable({
  required String customerId,
  required String flockId,
  required String stationName,
  required String breed,
  required DateTime hatchDate,
});
```

Implementation rules:

- Use a single SQLite transaction for graph creation.
- Mark local writes with `syncStatus = 'pending'`, `dirtyAt = now`, and `syncError = null`.
- `loadSettings` returns row `id = 1`; when missing, create and return defaults: Telegram enabled, threshold 3.0, minimum confidence 85.0.
- `saveSettings` upserts row `id = 1` and marks it pending sync.
- Sort batch summaries by newest submission first.
- `previousApprovedComparable` queries `hatchery_daily_records` before the supplied hatch date, ordered by `hatchDate DESC`, limited to 1.

- [ ] **Step 9: Add Supabase migration**

Create `supabase/migrations/0018_telegram_hatchery_agent.sql` with snake_case versions of the local tables. Use `text primary key`, `double precision`, `integer`, tenant-safe foreign keys, indexes matching local query paths, and RLS enabled.

Required checks:

```sql
status text not null check (status in (
  'received', 'processing', 'waiting_for_staff_answer', 'draft_ready',
  'needs_admin_review', 'partially_approved', 'approved', 'rejected', 'failed'
))
```

For final rows, include:

```sql
create index idx_hatchery_daily_records_comparable
  on public.hatchery_daily_records
  (customer_id, flock_id, station_name, breed, hatch_date desc);
```

RLS rule:

- Approved admins can select/insert/update agent tables.
- Customer users cannot see agent tables in v1.
- Service role can operate all tables for the Edge Function.

- [ ] **Step 10: Extend sync table lists**

Add the agent tables to `PerformanceSyncRepository.postFlockPushOrder` after customer/flock/hatchery dependencies:

```dart
'telegram_staff_links',
'agent_settings',
'agent_submissions',
'agent_questions',
'hatchery_draft_batches',
'hatchery_draft_rows',
'hatchery_agent_audit_events',
'hatchery_daily_records',
```

If this makes the class name misleading, do not rename it in this stage. Keep the change focused and add a comment that the adapter now covers the wider operational sync graph.

- [ ] **Step 11: Extend secret scanning**

Update `scripts/check_supabase_secrets.sh` so `SECRET_PATTERN` also catches Telegram bot tokens:

```bash
[0-9]{8,12}:AA[A-Za-z0-9_-]{30,}
```

Update `test/security/secret_scan_test.dart` to assert the script contains the Telegram token pattern split across string literals so the test itself does not look like a real token.

- [ ] **Step 12: Run tests**

Run:

```bash
flutter test test/data/database/telegram_hatchery_agent_schema_test.dart test/data/models/hatchery_agent_models_test.dart test/data/repositories/hatchery_agent_repository_test.dart test/security/secret_scan_test.dart
```

Expected: PASS.

- [ ] **Step 13: Update living spec**

Append a short implemented-behavior section to `docs/LIVING_SPEC.md` describing the new local/Supabase agent tables and secret scanner coverage. Do not describe UI/backend behavior that is not implemented in this stage.

- [ ] **Step 14: Commit**

```bash
git add lib/data/database/database_helper.dart lib/data/database/database_schema.dart lib/data/database/database_migrations.dart lib/data/models/hatchery_agent_models.dart lib/data/repositories/hatchery_agent_repository.dart lib/data/repositories/performance_sync_repository.dart supabase/migrations/0018_telegram_hatchery_agent.sql scripts/check_supabase_secrets.sh test/data/database/telegram_hatchery_agent_schema_test.dart test/data/models/hatchery_agent_models_test.dart test/data/repositories/hatchery_agent_repository_test.dart test/security/secret_scan_test.dart docs/LIVING_SPEC.md
git commit -m "feat: add hatchery agent data foundation"
```

---

### Task 2: Hatchability, History, and BMK Rules

**Files:**
- Create: `lib/features/agents/services/hatchery_agent_rules.dart`
- Modify: `lib/data/repositories/hatchery_agent_repository.dart`
- Test: `test/features/agents/hatchery_agent_rules_test.dart`

**Interfaces:**
- Consumes:
  - `HatcheryHistoricalPoint`
  - `BenchmarkLookup.nearestBreedBenchmark(...)`
  - `HatcheryAgentRepository.previousApprovedComparable(...)`
- Produces:
  - `double? calculateHatchabilityPct({required int? totalProduction, required int? eggsPlaced})`
  - `HatcheryRowWarning? buildHistoricalWarning(...)`
  - `HatcheryRowWarning? buildBmkWarning(...)`
  - `Future<List<HatcheryRowWarning>> buildReviewWarnings(...)`

- [ ] **Step 1: Write failing pure-rule tests**

Create `test/features/agents/hatchery_agent_rules_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/agents/services/hatchery_agent_rules.dart';

void main() {
  test('calculates hatchability from total production and eggs placed', () {
    expect(
      calculateHatchabilityPct(totalProduction: 11518, eggsPlaced: 19200),
      closeTo(59.9895, 0.0001),
    );
  });

  test('returns null hatchability when eggs placed is zero', () {
    expect(
      calculateHatchabilityPct(totalProduction: 100, eggsPlaced: 0),
      isNull,
    );
  });

  test('flags a three point historical increase', () {
    final warning = buildHistoricalWarning(
      currentPct: 83,
      previousPct: 80,
      thresholdPoints: 3,
    );

    expect(warning, isNotNull);
    expect(warning!.kind, HatcheryRowWarningKind.historicalChange);
    expect(warning.severity, HatcheryRowWarningSeverity.review);
  });

  test('does not flag a two point historical increase', () {
    expect(
      buildHistoricalWarning(
        currentPct: 82,
        previousPct: 80,
        thresholdPoints: 3,
      ),
      isNull,
    );
  });

  test('BMK calms a rising hatchability warning when current is below BMK', () {
    final warning = buildBmkWarning(
      currentPct: 85,
      previousPct: 80,
      bmkPct: 88,
      flockAgeWeeks: 30,
    );

    expect(warning, isNotNull);
    expect(warning!.messageEn, contains('may be consistent'));
  });
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
flutter test test/features/agents/hatchery_agent_rules_test.dart
```

Expected: FAIL because the service file does not exist.

- [ ] **Step 3: Implement pure rules**

Create `lib/features/agents/services/hatchery_agent_rules.dart`:

```dart
double? calculateHatchabilityPct({
  required int? totalProduction,
  required int? eggsPlaced,
}) {
  if (totalProduction == null || eggsPlaced == null || eggsPlaced <= 0) {
    return null;
  }
  if (totalProduction < 0) return null;
  return totalProduction / eggsPlaced * 100;
}
```

Add:

```dart
enum HatcheryRowWarningKind { historicalChange, bmkContext, missingBmk, missingFlockAge }
enum HatcheryRowWarningSeverity { info, review, critical }

class HatcheryRowWarning {
  const HatcheryRowWarning({
    required this.kind,
    required this.severity,
    required this.messageEn,
    required this.messageAr,
    this.previousPct,
    this.currentPct,
    this.bmkPct,
    this.flockAgeWeeks,
  });
  // fields + toJson/fromJson
}
```

Implement:

```dart
HatcheryRowWarning? buildHistoricalWarning({
  required double currentPct,
  required double? previousPct,
  double thresholdPoints = 3,
});

HatcheryRowWarning? buildBmkWarning({
  required double currentPct,
  required double? previousPct,
  required double? bmkPct,
  required int? flockAgeWeeks,
});
```

Message rules:

- Historical message includes previous, current, and absolute point change.
- BMK rising message says the increase may be consistent when `currentPct > previousPct` and `bmkPct >= currentPct`.
- Missing flock age returns `missingFlockAge` info warning only when BMK comparison is requested but no age exists.

- [ ] **Step 4: Add repository-assisted warning builder**

Add:

```dart
class HatcheryAgentRuleEngine {
  HatcheryAgentRuleEngine({
    HatcheryAgentRepository? repository,
    BenchmarkLookup? benchmarkLookup,
  });

  Future<List<HatcheryRowWarning>> buildReviewWarnings({
    required String customerId,
    required String flockId,
    required String stationName,
    required String breed,
    required DateTime hatchDate,
    required double currentHatchabilityPct,
    required int? flockAgeWeeks,
    double thresholdPoints = 3,
  });
}
```

This method loads the previous approved comparable row through `previousApprovedComparable`, adds the historical warning when needed, then calls `BenchmarkLookup.nearestBreedBenchmark(calculatedBmkAgeDays: flockAgeWeeks * 7, breed: breed)` when flock age exists.

- [ ] **Step 5: Run tests**

Run:

```bash
flutter test test/features/agents/hatchery_agent_rules_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/agents/services/hatchery_agent_rules.dart lib/data/repositories/hatchery_agent_repository.dart test/features/agents/hatchery_agent_rules_test.dart
git commit -m "feat: add hatchery agent review rules"
```

---

### Task 3: Telegram Webhook and AI Extraction Backend

**Files:**
- Create: `supabase/functions/telegram-hatchery-agent/index.ts`
- Create: `supabase/functions/telegram-hatchery-agent/extraction_schema.ts`
- Create: `supabase/functions/telegram-hatchery-agent/telegram.ts`
- Create: `supabase/functions/telegram-hatchery-agent/index_test.ts`
- Modify: `supabase/migrations/0018_telegram_hatchery_agent.sql`

**Interfaces:**
- Consumes: Supabase tables from Task 1.
- Produces:
  - POST webhook endpoint for Telegram updates.
  - `handleTelegramUpdate(update, deps)` pure handler for tests.
  - `extractHatcheryRows(input, deps)` AI extraction function returning JSON rows.
  - Telegram follow-up messages when flock age or required fields are missing.

- [ ] **Step 1: Write failing backend tests**

Create `supabase/functions/telegram-hatchery-agent/index_test.ts`:

```ts
import { assertEquals } from 'jsr:@std/assert'
import { handleTelegramUpdate } from './index.ts'

Deno.test('rejects request with missing Telegram secret', async () => {
  const response = await handleTelegramUpdate(
    new Request('https://example.test', { method: 'POST', body: '{}' }),
    {
      expectedTelegramSecret: 'secret',
      adminClient: fakeAdminClient(),
      extract: fakeExtract([]),
      sendTelegramMessage: async () => {},
    },
  )

  assertEquals(response.status, 401)
})

Deno.test('stores one submission and one draft batch for extracted rows', async () => {
  const calls: string[] = []
  const response = await handleTelegramUpdate(
    new Request('https://example.test', {
      method: 'POST',
      headers: { 'X-Telegram-Bot-Api-Secret-Token': 'secret' },
      body: JSON.stringify({
        update_id: 100,
        message: {
          message_id: 10,
          date: 1784890000,
          chat: { id: 123 },
          from: { id: 456, first_name: 'Staff' },
          text: 'Customer A Ross flock eggs placed 19200 total 11518',
        },
      }),
    }),
    {
      expectedTelegramSecret: 'secret',
      adminClient: fakeAdminClient(calls),
      extract: fakeExtract([{ customerName: 'Customer A', flockName: 'Ross flock', eggsPlaced: 19200, totalProduction: 11518 }]),
      sendTelegramMessage: async () => {},
    },
  )

  assertEquals(response.status, 200)
  assertEquals(calls.includes('agent_submissions.insert'), true)
  assertEquals(calls.includes('hatchery_draft_batches.insert'), true)
  assertEquals(calls.includes('hatchery_draft_rows.insert'), true)
})
```

Keep `fakeAdminClient`, `fakeExtract`, and call recording in the same test file. Do not use a real Telegram token, real OpenAI key, or real Supabase project in tests.

- [ ] **Step 2: Run backend tests and verify failure**

Run:

```bash
deno test supabase/functions/telegram-hatchery-agent/index_test.ts --allow-env
```

Expected: FAIL because the function files do not exist. If Deno is not installed on the machine, document that in the stage handoff and still complete the TypeScript implementation.

- [ ] **Step 3: Define structured extraction schema**

Create `supabase/functions/telegram-hatchery-agent/extraction_schema.ts`:

```ts
export const hatcheryExtractionSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['rows', 'missingQuestions'],
  properties: {
    rows: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: [
          'rowOrdinal',
          'customerName',
          'flockName',
          'stationName',
          'breed',
          'eggsPlaced',
          'productionDate',
          'placementDate',
          'eggWeightG',
          'fertilityPct',
          'transferWeightG',
          'setterNumber',
          'hatcherNumber',
          'hatchDate',
          'healthyChicks',
          'secondGradeChicks',
          'condemnedChicks',
          'totalProduction',
          'confidencePct',
        ],
        properties: {
          rowOrdinal: { type: 'integer' },
          customerName: { type: ['string', 'null'] },
          flockName: { type: ['string', 'null'] },
          stationName: { type: ['string', 'null'] },
          breed: { type: ['string', 'null'] },
          eggsPlaced: { type: ['integer', 'null'] },
          productionDate: { type: ['string', 'null'] },
          placementDate: { type: ['string', 'null'] },
          eggWeightG: { type: ['number', 'null'] },
          fertilityPct: { type: ['number', 'null'] },
          transferWeightG: { type: ['number', 'null'] },
          setterNumber: { type: ['string', 'null'] },
          hatcherNumber: { type: ['string', 'null'] },
          hatchDate: { type: ['string', 'null'] },
          healthyChicks: { type: ['integer', 'null'] },
          secondGradeChicks: { type: ['integer', 'null'] },
          condemnedChicks: { type: ['integer', 'null'] },
          totalProduction: { type: ['integer', 'null'] },
          confidencePct: { type: 'number' },
        },
      },
    },
    missingQuestions: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['rowOrdinal', 'fieldKey', 'questionTextEn', 'questionTextAr'],
        properties: {
          rowOrdinal: { type: ['integer', 'null'] },
          fieldKey: { type: 'string' },
          questionTextEn: { type: 'string' },
          questionTextAr: { type: 'string' },
        },
      },
    },
  },
} as const
```

- [ ] **Step 4: Implement Telegram helpers**

Create `supabase/functions/telegram-hatchery-agent/telegram.ts`:

```ts
export async function sendTelegramMessage(params: {
  botToken: string
  chatId: string
  text: string
}): Promise<void> {
  const response = await fetch(
    `https://api.telegram.org/bot${params.botToken}/sendMessage`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: params.chatId, text: params.text }),
    },
  )
  if (!response.ok) {
    throw new Error(`Telegram sendMessage failed: ${response.status}`)
  }
}
```

- [ ] **Step 5: Implement webhook handler**

Create `supabase/functions/telegram-hatchery-agent/index.ts` with:

```ts
export async function handleTelegramUpdate(
  request: Request,
  deps: HandlerDeps,
): Promise<Response>
```

Rules:

- Return 405 for non-POST except OPTIONS.
- Validate `X-Telegram-Bot-Api-Secret-Token` equals `TELEGRAM_WEBHOOK_SECRET`.
- Read `TELEGRAM_BOT_TOKEN`, `OPENAI_API_KEY`, `SUPABASE_URL`, and `SUPABASE_SERVICE_ROLE_KEY` only from `Deno.env`.
- Use Supabase service-role client server-side only.
- Upsert or look up the Telegram staff link by `telegram_user_id`.
- Reject revoked or unknown staff with a Telegram message and no draft batch.
- Store `agent_submissions` immediately with status `received`.
- Extract rows with OpenAI structured outputs.
- Insert one `hatchery_draft_batches` row.
- Insert all extracted rows into `hatchery_draft_rows`.
- Insert missing questions into `agent_questions`.
- If questions exist, set submission status `waiting_for_staff_answer`.
- If no questions exist and row confidence is acceptable, set `draft_ready`.
- If confidence is low or warnings exist, set `needs_admin_review`.

OpenAI extraction guidance:

- Use OpenAI Responses API with structured outputs.
- Use image input for photos and file/PDF input where supported.
- Keep extraction schema strict and require nulls for unknown values.
- The model prompt must say: extract only visible/provided hatchery values, do not guess customer/flock/station/breed, and support English/Arabic mixed tables.

- [ ] **Step 6: Add setup SQL comments**

At the top of `supabase/migrations/0018_telegram_hatchery_agent.sql`, add deployment notes in SQL comments:

```sql
-- Required Edge Function secrets:
-- TELEGRAM_BOT_TOKEN: regenerated bot token from BotFather.
-- TELEGRAM_WEBHOOK_SECRET: random 32+ character value used with Telegram setWebhook secret_token.
-- OPENAI_API_KEY: OpenAI API key used only by the Edge Function.
```

- [ ] **Step 7: Run backend tests**

Run:

```bash
deno test supabase/functions/telegram-hatchery-agent/index_test.ts --allow-env
```

Expected: PASS, or document that Deno is unavailable.

- [ ] **Step 8: Commit**

```bash
git add supabase/functions/telegram-hatchery-agent supabase/migrations/0018_telegram_hatchery_agent.sql
git commit -m "feat: add telegram hatchery agent backend"
```

---

### Task 4: Agent Monitor and Draft Review UI

**Files:**
- Create: `lib/features/agents/providers/agent_monitor_provider.dart`
- Create: `lib/features/agents/screens/agent_monitor_screen.dart`
- Create: `lib/features/agents/widgets/agent_submission_card.dart`
- Create: `lib/features/agents/widgets/hatchery_draft_row_card.dart`
- Modify: `lib/features/home/widgets/main_shell.dart`
- Modify: `lib/core/constants/app_strings.dart`
- Modify: `lib/l10n/app_localizations.dart`
- Test: `test/features/agents/agent_monitor_provider_test.dart`
- Test: `test/features/agents/agent_monitor_screen_test.dart`
- Modify: `test/core/l10n/hardcoded_ui_strings_test.dart`

**Interfaces:**
- Consumes:
  - `HatcheryAgentRepository.listBatchSummaries()`
  - `HatcheryAgentRepository.loadBatchDetails(String batchId)`
  - models from Task 1.
- Produces:
  - `AgentMonitorProvider.load()`
  - `AgentMonitorProvider.selectBatch(String batchId)`
  - `AgentMonitorProvider.setTelegramEnabled(bool enabled)`
  - Admin tab/screen labelled `Agent`

- [ ] **Step 1: Write provider test**

Create `test/features/agents/agent_monitor_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/agents/providers/agent_monitor_provider.dart';

void main() {
  test('load exposes newest batch summaries', () async {
    final repo = FakeHatcheryAgentRepository.withSummaries([
      fakeSummary(id: 'batch-new', submittedAt: DateTime.utc(2026, 7, 27)),
      fakeSummary(id: 'batch-old', submittedAt: DateTime.utc(2026, 7, 26)),
    ]);
    final provider = AgentMonitorProvider(repository: repo);

    await provider.load();

    expect(provider.isLoading, isFalse);
    expect(provider.batches.map((batch) => batch.id), ['batch-new', 'batch-old']);
  });
}
```

Keep fakes inside the test file unless a reusable fake already exists.

- [ ] **Step 2: Implement provider**

Create `lib/features/agents/providers/agent_monitor_provider.dart`:

```dart
class AgentMonitorProvider extends ChangeNotifier {
  AgentMonitorProvider({HatcheryAgentRepository? repository});

  bool get isLoading;
  String? get error;
  AgentSettings get settings;
  List<HatcheryDraftBatchSummary> get batches;
  HatcheryDraftBatchDetails? get selectedBatch;

  Future<void> load();
  Future<void> selectBatch(String batchId);
  Future<void> refreshSelected();
  Future<void> setTelegramEnabled(bool enabled);
}
```

Rules:

- `load` clears old errors, loads summaries, and keeps existing selected batch if still present.
- `selectBatch` loads details for the selected batch.
- `setTelegramEnabled` saves settings through the repository and updates the screen immediately after success.
- Failed repository calls set a readable `error` and notify listeners.

- [ ] **Step 3: Write screen smoke test**

Create `test/features/agents/agent_monitor_screen_test.dart`:

```dart
testWidgets('Agent Monitor shows batch list and row warnings', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: ChangeNotifierProvider<AgentMonitorProvider>.value(
        value: AgentMonitorProvider(repository: fakeRepoWithOneWarning()),
        child: const AgentMonitorScreen(),
      ),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.text('Agent Monitor'), findsOneWidget);
  expect(find.textContaining('Hatchability'), findsWidgets);
  expect(find.textContaining('Review'), findsWidgets);
});
```

- [ ] **Step 4: Implement screen and widgets**

Create `AgentMonitorScreen` as a dense operational screen, not a marketing page.

Layout:

- Top row: title `Agent Monitor`, refresh button, and a pause/resume control bound to `AgentMonitorProvider.setTelegramEnabled`.
- Left/list area on wide screens or top list on mobile: submission batch cards.
- Detail area: original source summary, status chip, staff identity, questions/answers, row cards.
- Row cards show extraction confidence and warnings separately.
- Row actions are visible but can be disabled until Task 5 wires approval if Task 4 is UI-only.

Use existing app styles:

- `AppColors`
- `AppSizes`
- `AppTextStyles`
- `SectionCard` or `AppCard`
- Material icons from Flutter.

- [ ] **Step 5: Add navigation tab**

Modify `lib/core/constants/app_strings.dart`:

```dart
static const String agentTab = 'Agent';
```

Modify `lib/features/home/widgets/main_shell.dart`:

- Import `../../agents/screens/agent_monitor_screen.dart`.
- Add `'agent'` to `_allMainShellTabKeys` before `settings`.
- Keep customer users out of this tab by not adding it to `_customerMainShellTabKeys`.
- Add a `_ShellTab` with `Icons.smart_toy_outlined` and `Icons.smart_toy`.

- [ ] **Step 6: Add Arabic translations**

Add direct Arabic translations in `lib/l10n/app_localizations.dart` for the user-visible strings introduced by this stage:

```dart
'Agent': 'الوكيل',
'Agent Monitor': 'مراقبة الوكيل',
'Draft ready': 'المسودة جاهزة',
'Telegram paused': 'تم إيقاف تيليجرام مؤقتًا',
'Telegram running': 'تيليجرام يعمل',
'Needs admin review': 'تحتاج مراجعة المدير',
'Waiting for staff answer': 'بانتظار رد الموظف',
'Confidence': 'الثقة',
'Warnings': 'تنبيهات',
'Hatchability': 'نسبة الفقس',
```

- [ ] **Step 7: Run UI tests**

Run:

```bash
flutter test test/features/agents/agent_monitor_provider_test.dart test/features/agents/agent_monitor_screen_test.dart test/core/l10n/hardcoded_ui_strings_test.dart
```

Expected: PASS.

- [ ] **Step 8: Update living spec**

Add a concise implemented-behavior section to `docs/LIVING_SPEC.md` describing the Agent Monitor tab and read-only draft review screen. Do not claim approval works until Task 5 is done.

- [ ] **Step 9: Commit**

```bash
git add lib/features/agents lib/features/home/widgets/main_shell.dart lib/core/constants/app_strings.dart lib/l10n/app_localizations.dart test/features/agents test/core/l10n/hardcoded_ui_strings_test.dart docs/LIVING_SPEC.md
git commit -m "feat: add hatchery agent monitor"
```

---

### Task 5: Row Approval, Final Save, and Sync Completion

**Files:**
- Modify: `lib/data/models/hatchery_agent_models.dart`
- Modify: `lib/data/repositories/hatchery_agent_repository.dart`
- Modify: `lib/services/supabase/startup_sync_service.dart`
- Modify: `lib/features/agents/providers/agent_monitor_provider.dart`
- Modify: `lib/features/agents/screens/agent_monitor_screen.dart`
- Modify: `docs/LIVING_SPEC.md`
- Test: `test/features/agents/hatchery_agent_approval_test.dart`
- Test: `test/services/supabase/startup_sync_service_test.dart`

**Interfaces:**
- Consumes:
  - Draft rows from Task 1.
  - Agent Monitor from Task 4.
- Produces:
  - `HatcheryAgentRepository.approveDraftRow(...)`
  - `HatcheryAgentRepository.rejectDraftRow(...)`
  - `HatcheryAgentRepository.updateDraftRow(...)`
  - row-by-row UI actions.

- [ ] **Step 1: Write approval repository test**

Create `test/features/agents/hatchery_agent_approval_test.dart`:

```dart
test('approving a draft row creates final hatchery record and marks row approved', () async {
  final repo = HatcheryAgentRepository();
  await _seedCustomerFlockHatcheryAndDraftRow();

  final saved = await repo.approveDraftRow(
    rowId: 'row-1',
    approvedBy: 'admin-1',
    approvedAt: DateTime.utc(2026, 7, 27, 10),
  );

  expect(saved.hatchabilityPct, closeTo(60, 0.1));

  final details = await repo.loadBatchDetails('batch-1');
  expect(details!.rows.single.status, HatcheryDraftRowStatus.approved);

  final db = await DatabaseHelper().db;
  final finalRows = await db.query('hatchery_daily_records');
  expect(finalRows, hasLength(1));
  expect(finalRows.single['sourceDraftRowId'], 'row-1');
});
```

Add a second test:

```dart
test('approval rejects row without matched customer and flock ids', () async {
  final repo = HatcheryAgentRepository();
  await _seedDraftRowWithoutMatches();

  await expectLater(
    repo.approveDraftRow(
      rowId: 'row-unmatched',
      approvedBy: 'admin-1',
      approvedAt: DateTime.utc(2026, 7, 27),
    ),
    throwsA(isA<StateError>()),
  );
});
```

- [ ] **Step 2: Implement approval repository methods**

Add:

```dart
Future<HatcheryDailyRecord> approveDraftRow({
  required String rowId,
  required String approvedBy,
  required DateTime approvedAt,
});

Future<void> rejectDraftRow({
  required String rowId,
  required String rejectedBy,
  required DateTime rejectedAt,
  String? reason,
});

Future<void> updateDraftRow(HatcheryDraftRow row);
```

Approval rules:

- Load the row and its batch in one transaction.
- Require `customerId`, `flockId`, `stationName`, `breed`, `eggsPlaced`, `hatchDate`, `totalProduction`, and `hatchabilityPct`.
- Insert one `hatchery_daily_records` row.
- Mark the draft row approved with `approvedRecordId`, `reviewedBy`, and `reviewedAt`.
- Insert a `hatchery_agent_audit_events` row with `eventType = 'row_approved'`.
- Recalculate batch status:
  - all approved or rejected: `approved` when at least one row approved and none pending.
  - mixed approved/pending/rejected: `partially_approved`.
  - no approved rows and all rejected: `rejected`.
- Mark all changed rows pending sync.

- [ ] **Step 3: Wire provider actions**

In `AgentMonitorProvider`, add:

```dart
Future<void> approveRow(String rowId, String adminUserId);
Future<void> rejectRow(String rowId, String adminUserId, {String? reason});
Future<void> saveRowEdit(HatcheryDraftRow row);
```

Each method calls the repository, reloads the selected batch, and refreshes summaries.

- [ ] **Step 4: Wire screen actions**

Enable row action buttons in `HatcheryDraftRowCard`:

- Edit opens a modal with all row fields.
- Approve calls `provider.approveRow(row.id, currentUser.id)`.
- Reject asks for optional reason and calls `provider.rejectRow(...)`.

Use `AuthProvider` to get the admin user id. Hide action buttons for customer users.

- [ ] **Step 5: Add sync coverage**

Ensure `hatchery_daily_records`, changed draft rows, batch rows, and audit events are pushed and pulled by the operational sync path. Add or update tests in `test/services/supabase/startup_sync_service_test.dart` using fake Supabase loaders/executors to verify the new table names participate in pull and push.

- [ ] **Step 6: Run tests**

Run:

```bash
flutter test test/features/agents/hatchery_agent_approval_test.dart test/features/agents/agent_monitor_provider_test.dart test/features/agents/agent_monitor_screen_test.dart test/services/supabase/startup_sync_service_test.dart
```

Expected: PASS.

- [ ] **Step 7: Update living spec**

Update `docs/LIVING_SPEC.md` to describe implemented approval behavior:

- Staff submissions produce draft batches.
- Admin can approve/edit/reject row by row.
- Approved rows create `hatchery_daily_records`.
- Rejected rows remain audit evidence only.
- Final records sync through the existing cloud sync path.

- [ ] **Step 8: Commit**

```bash
git add lib/data/models/hatchery_agent_models.dart lib/data/repositories/hatchery_agent_repository.dart lib/services/supabase/startup_sync_service.dart lib/features/agents test/features/agents test/services/supabase/startup_sync_service_test.dart docs/LIVING_SPEC.md
git commit -m "feat: approve hatchery agent draft rows"
```

---

## Stage Execution Order

Each stage should run in a separate Codex chat/task as requested:

1. Task 1: Agent Data Foundation
2. Task 2: Hatchability, History, and BMK Rules
3. Task 3: Telegram Webhook and AI Extraction Backend
4. Task 4: Agent Monitor and Draft Review UI
5. Task 5: Row Approval, Final Save, and Sync Completion

Later tasks should start only after the previous task is committed, because each stage depends on interfaces and migrations created earlier.

## Verification Notes

- Run the narrow test command inside each task before committing.
- For final integration after Task 5, run:

```bash
flutter test test/data/database/telegram_hatchery_agent_schema_test.dart test/data/models/hatchery_agent_models_test.dart test/data/repositories/hatchery_agent_repository_test.dart test/features/agents/hatchery_agent_rules_test.dart test/features/agents/agent_monitor_provider_test.dart test/features/agents/agent_monitor_screen_test.dart test/features/agents/hatchery_agent_approval_test.dart test/security/secret_scan_test.dart
```

- If a Flutter preview is needed, use:

```bash
make restart-web
```

and open `http://127.0.0.1:57863`.

## External References Used

- Telegram Bot API webhook `secret_token` and `X-Telegram-Bot-Api-Secret-Token` header.
- OpenAI API structured outputs for JSON-schema constrained extraction.
- OpenAI API image/vision input for hatchery screenshots and photos.
