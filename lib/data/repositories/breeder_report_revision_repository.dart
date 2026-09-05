import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../models/breeder_report_revision_model.dart';

/// Insert-and-read-only access to `breeder_report_revisions`
/// (breeder-flock-performance ticket 12). There is deliberately no update
/// or delete method here at all — the schema's immutability triggers would
/// reject them anyway (see `createBreederReportRevisionsTable`), but the
/// repository surface itself never offers the call so a future caller
/// cannot even attempt one.
class BreederReportRevisionRepository {
  BreederReportRevisionRepository({DatabaseHelper? dbHelper, Uuid? uuid})
    : dbHelper = dbHelper ?? DatabaseHelper(),
      _uuid = uuid ?? const Uuid();

  final DatabaseHelper dbHelper;
  final Uuid _uuid;

  static const table = 'breeder_report_revisions';

  String _nowStamp() => DateTime.now().toIso8601String();

  /// Appends one revision row. [revision.id] is used verbatim if the
  /// caller already generated one (so a batch of rows from the same
  /// correction can be inserted with pre-assigned, ordered ids);
  /// otherwise a fresh id is generated.
  Future<BreederReportRevision> insert(
    BreederReportRevision revision,
  ) async {
    final db = await dbHelper.db;
    final now = _nowStamp();
    await db.insert(table, {
      ...revision.toMap(),
      'createdAt': now,
      'updatedAt': now,
      'syncStatus': 'pending',
      'dirtyAt': now,
    });
    return revision;
  }

  /// Every revision row written by every correction ever made to
  /// [reportId], oldest first — the full audit trail a "revision history"
  /// view shows (design section 5.3: "creates permanent revision history").
  Future<List<BreederReportRevision>> getForReport(String reportId) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      table,
      where: 'reportId = ?',
      whereArgs: [reportId],
      orderBy: 'revisionAfter ASC, changedAt ASC, id ASC',
    );
    return rows.map(BreederReportRevision.fromMap).toList();
  }

  String newId() => _uuid.v4();

  String? _dirtyReadCutoff;

  Future<List<Map<String, dynamic>>> getDirtyRows() async {
    final db = await dbHelper.db;
    _dirtyReadCutoff = _nowStamp();
    final rows = await db.query(
      table,
      where: "syncStatus IN ('pending', 'failed')",
      orderBy: 'dirtyAt ASC, id ASC',
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> markRowsSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await dbHelper.db;
    final cutoff = _dirtyReadCutoff ?? _nowStamp();
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.update(
      table,
      {
        'syncStatus': 'synced',
        'dirtyAt': null,
        'lastSyncedAt': _nowStamp(),
        'syncError': null,
      },
      where: 'id IN ($placeholders) AND (dirtyAt IS NULL OR dirtyAt <= ?)',
      whereArgs: [...ids, cutoff],
    );
  }

  Future<void> markRowsFailed(List<String> ids, Object error) async {
    if (ids.isEmpty) return;
    final db = await dbHelper.db;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.update(
      table,
      {'syncStatus': 'failed', 'syncError': error.toString()},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }
}
