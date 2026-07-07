# Breakout Photo Path Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recover breakout and other evidence photos after an iOS application-container path change, with cloud download as the fallback when the local file is truly gone.

**Architecture:** Keep recovery below the UI. `PhotoRepository` will reconcile stale absolute paths against the current documents directory and will stop preserving nonexistent local paths during remote upsert; `PhotoSyncService` will invoke reconciliation before checking cloud availability so offline files can recover too.

**Tech Stack:** Flutter/Dart, `dart:io`, `path`, SQLite via sqflite, Mocktail, Flutter test.

---

### Task 1: Add repository regression coverage

**Files:**
- Create: `test/data/repositories/photo_repository_test.dart`
- Modify: `lib/data/repositories/photo_repository.dart`

- [ ] **Step 1: Write failing tests for stale-path reconciliation and remote fallback**

Create an isolated-database suite that inserts a complete audit-session fixture and photo row. Cover these cases:

```dart
test('reconcileLocalPaths rebases a stale path to the current documents directory', () async {
  final documents = await Directory.systemTemp.createTemp('photo_documents_');
  final current = File(p.join(documents.path, 'breakout.jpg'));
  await current.writeAsBytes([1, 2, 3]);
  await _insertPhoto('/old/container/Documents/breakout.jpg');

  await repository.reconcileLocalPaths(documents.path);

  expect((await repository.getAllPhotos()).single.filePath, current.path);
  await documents.delete(recursive: true);
});

test('upsertPhoto preserves an existing usable local file', () async {
  final local = File(p.join(tempDirectory.path, 'breakout.jpg'));
  await local.writeAsBytes([1]);
  await _insertPhoto(local.path);

  await repository.upsertPhoto(_remotePhotoRow());

  expect((await repository.getAllPhotos()).single.filePath, local.path);
});

test('upsertPhoto accepts the remote path when the local file is missing', () async {
  await _insertPhoto('/missing/container/Documents/breakout.jpg');

  await repository.upsertPhoto(_remotePhotoRow());

  expect(
    (await repository.getAllPhotos()).single.filePath,
    'supabase://photos/session-1/residue_breakout/row-1/photo-1.jpg',
  );
});
```

- [ ] **Step 2: Run the repository suite and verify RED**

Run:

```bash
flutter test test/data/repositories/photo_repository_test.dart
```

Expected: compilation fails because `PhotoRepository.reconcileLocalPaths` does not exist, proving the new recovery contract is absent.

- [ ] **Step 3: Implement local path reconciliation and usable-file checks**

Add `package:path/path.dart` and implement:

```dart
Future<void> reconcileLocalPaths(String documentsDirectoryPath) async {
  final db = await dbHelper.db;
  final rows = await db.query('photos', columns: ['id', 'filePath']);
  for (final row in rows) {
    try {
      final id = row['id'] as String?;
      final storedPath = row['filePath'] as String?;
      if (id == null || !_isLocalFilePath(storedPath)) continue;
      if (await _isUsableLocalFile(storedPath)) continue;
      final candidate = path.join(
        documentsDirectoryPath,
        path.basename(storedPath!),
      );
      if (candidate == storedPath || !await _isUsableLocalFile(candidate)) {
        continue;
      }
      await db.update(
        'photos',
        {'filePath': candidate},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (_) {
      // One unreadable path must not block recovery for other photos.
    }
  }
}

Future<bool> _isUsableLocalFile(String? filePath) async {
  if (!_isLocalFilePath(filePath)) return false;
  try {
    final file = File(filePath!);
    return await file.exists() && await file.length() > 0;
  } catch (_) {
    return false;
  }
}
```

Change remote upsert preservation to:

```dart
if (_isRemotePath(incomingPath) &&
    await _isUsableLocalFile(existingPath)) {
  normalized['filePath'] = existingPath;
}
```

- [ ] **Step 4: Run repository tests and verify GREEN**

Run:

```bash
flutter test test/data/repositories/photo_repository_test.dart
```

Expected: all repository path-recovery tests pass.

### Task 2: Reconcile paths during downloaded-photo sync

**Files:**
- Modify: `test/services/photo/photo_sync_service_test.dart`
- Modify: `lib/services/photo/photo_sync_service.dart`

- [ ] **Step 1: Write the failing offline reconciliation test**

Add:

```dart
test('syncDownloaded reconciles local paths before checking cloud availability', () async {
  final documents = await Directory.systemTemp.createTemp('photo_reconcile_');
  final repo = _MockPhotoRepository();
  final supabase = _MockSupabaseService();
  when(() => repo.reconcileLocalPaths(documents.path)).thenAnswer((_) async {});
  when(() => supabase.refreshAvailability()).thenAnswer((_) async => false);

  await PhotoSyncService(
    repository: repo,
    supabase: supabase,
    documentDirectoryProvider: () async => documents,
  ).syncDownloaded();

  verify(() => repo.reconcileLocalPaths(documents.path)).called(1);
  verifyNever(() => repo.getRemotePhotos());
  await documents.delete(recursive: true);
});
```

Stub `reconcileLocalPaths` in the existing online download tests so their mock contract remains explicit.

- [ ] **Step 2: Run the sync test and verify RED**

Run:

```bash
flutter test test/services/photo/photo_sync_service_test.dart --plain-name "syncDownloaded reconciles local paths before checking cloud availability"
```

Expected: verification fails because `syncDownloaded()` does not call `reconcileLocalPaths`.

- [ ] **Step 3: Call reconciliation before cloud availability**

Update `syncDownloaded()`:

```dart
Future<void> syncDownloaded() async {
  final documentsDir = await _documentDirectoryProvider();
  try {
    await _repo.reconcileLocalPaths(documentsDir.path);
  } catch (_) {
    // Local recovery is best effort; cloud recovery can still proceed.
  }

  final available = await _supabase.refreshAvailability();
  if (!available) return;

  final remotePhotos = await _repo.getRemotePhotos();
  // Existing download loop remains unchanged.
}
```

- [ ] **Step 4: Run the complete photo sync suite and verify GREEN**

Run:

```bash
flutter test test/services/photo/photo_sync_service_test.dart
```

Expected: all pending-upload, download, and reconciliation tests pass.

### Task 3: Document and verify the implemented behavior

**Files:**
- Modify: `docs/LIVING_SPEC.md`
- Verify: `lib/data/repositories/photo_repository.dart`
- Verify: `lib/services/photo/photo_sync_service.dart`
- Verify: `test/data/repositories/photo_repository_test.dart`
- Verify: `test/services/photo/photo_sync_service_test.dart`

- [ ] **Step 1: Update the living specification**

Extend the photo-sync section to state that startup reconciliation rebases stale absolute document paths by filename and only preserves existing local paths during cloud pull when the backing file is usable. Add a dated change-log entry for the recovery behavior.

- [ ] **Step 2: Format changed Dart files**

Run:

```bash
dart format lib/data/repositories/photo_repository.dart lib/services/photo/photo_sync_service.dart test/data/repositories/photo_repository_test.dart test/services/photo/photo_sync_service_test.dart
```

Expected: formatter exits successfully.

- [ ] **Step 3: Run focused tests**

Run:

```bash
flutter test test/data/repositories/photo_repository_test.dart test/services/photo/photo_sync_service_test.dart test/services/supabase/startup_sync_service_test.dart test/services/supabase/startup_sync_incoming_test.dart
```

Expected: all focused photo and startup-sync tests pass.

- [ ] **Step 4: Run focused static analysis**

Run:

```bash
dart analyze lib/data/repositories/photo_repository.dart lib/services/photo/photo_sync_service.dart test/data/repositories/photo_repository_test.dart test/services/photo/photo_sync_service_test.dart
```

Expected: `No issues found!`.

- [ ] **Step 5: Inspect the final task-scoped diff**

Run:

```bash
git diff --check -- lib/data/repositories/photo_repository.dart lib/services/photo/photo_sync_service.dart test/data/repositories/photo_repository_test.dart test/services/photo/photo_sync_service_test.dart docs/LIVING_SPEC.md
git diff --stat -- lib/data/repositories/photo_repository.dart lib/services/photo/photo_sync_service.dart test/data/repositories/photo_repository_test.dart test/services/photo/photo_sync_service_test.dart docs/LIVING_SPEC.md
```

Expected: no whitespace errors and only the approved path-recovery behavior in the task-scoped files, alongside pre-existing unrelated edits already present in those files.
