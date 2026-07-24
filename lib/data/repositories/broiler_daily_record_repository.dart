import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../models/broiler_daily_record_models.dart';

class BroilerDailyRecordRepository {
  BroilerDailyRecordRepository({
    DatabaseHelper? databaseHelper,
    Uuid uuid = const Uuid(),
  }) : _databaseHelper = databaseHelper ?? DatabaseHelper(),
       _uuid = uuid;

  final DatabaseHelper _databaseHelper;
  final Uuid _uuid;

  Future<SavedBroilerDailyRevision> saveRevision(
    BroilerDailyRecordDraft draft,
  ) async {
    draft.validate();
    final db = await _databaseHelper.db;
    return db.transaction((txn) async {
      final now = DateTime.now().toUtc();
      final recordDate = dateKey(draft.recordDate);
      final existing = await _findRecord(
        txn,
        recordId: draft.recordId,
        placementId: draft.placementId,
        recordDate: recordDate,
      );
      if (existing != null &&
          (existing.placementId != draft.placementId ||
              dateKey(existing.recordDate) != recordDate)) {
        throw DailyRecordIdentityConflict(existing.id);
      }

      final recordId = existing?.id ?? draft.recordId ?? _uuid.v4();
      if (existing == null) {
        await txn.insert('broiler_daily_records', {
          'id': recordId,
          'placementId': draft.placementId,
          'recordDate': recordDate,
          'verificationStatus': draft.verificationStatus.storageKey,
          'createdBy': draft.enteredBy,
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
          'syncStatus': 'pending',
          'dirtyAt': now.toIso8601String(),
        });
      }

      final nextRevision = await _nextRevisionNumber(txn, recordId);
      final revisionId = _uuid.v4();
      final revisionMap = <String, Object?>{
        'id': revisionId,
        'recordId': recordId,
        'revisionNumber': nextRevision,
        ...draft.toRevisionMap(),
        'createdAt': now.toIso8601String(),
        'syncStatus': 'pending',
        'dirtyAt': now.toIso8601String(),
      };
      await txn.insert('broiler_daily_record_revisions', revisionMap);

      final sources = <DailyRecordSource>[];
      for (final sourceDraft in draft.sources) {
        final source = DailyRecordSource(
          id: _uuid.v4(),
          revisionId: revisionId,
          sourceKind: sourceDraft.sourceKind,
          localPath: sourceDraft.localPath,
          remoteStoragePath: sourceDraft.remoteStoragePath,
          originalFilename: sourceDraft.originalFilename,
          checksum: sourceDraft.checksum,
          uploadState: sourceDraft.uploadState,
          uploadError: sourceDraft.uploadError,
          createdAt: now,
          updatedAt: now,
          syncStatus: 'pending',
          dirtyAt: now,
        );
        await txn.insert('daily_record_sources', {
          'id': source.id,
          'revisionId': source.revisionId,
          ...source.toMap(),
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
          'syncStatus': 'pending',
          'dirtyAt': now.toIso8601String(),
        });
        sources.add(source);
      }

      final events = <BroilerDailyEvent>[];
      for (final eventDraft in draft.events) {
        final event = BroilerDailyEvent(
          id: _uuid.v4(),
          revisionId: revisionId,
          eventType: eventDraft.eventType,
          eventAt: eventDraft.eventAt,
          isAllDay: eventDraft.isAllDay,
          eventState: eventDraft.eventState,
          description: eventDraft.description,
          treatment: eventDraft.treatment,
          vaccination: eventDraft.vaccination,
          feedPhase: eventDraft.feedPhase,
          equipment: eventDraft.equipment,
          createdAt: now,
          syncStatus: 'pending',
          dirtyAt: now,
        );
        await txn.insert('broiler_daily_events', {
          'id': event.id,
          'revisionId': event.revisionId,
          ...event.toMap(),
          'createdAt': now.toIso8601String(),
          'syncStatus': 'pending',
          'dirtyAt': now.toIso8601String(),
        });
        events.add(event);
      }

      await txn.update(
        'broiler_daily_records',
        {
          'currentRevisionId': revisionId,
          'verificationStatus': draft.verificationStatus.storageKey,
          'updatedAt': now.toIso8601String(),
          'syncStatus': 'pending',
          'dirtyAt': now.toIso8601String(),
          'syncError': null,
        },
        where: 'id = ?',
        whereArgs: [recordId],
      );

      final recordRows = await txn.query(
        'broiler_daily_records',
        where: 'id = ?',
        whereArgs: [recordId],
        limit: 1,
      );
      final record = BroilerDailyRecord.fromMap(recordRows.single);
      final revision = BroilerDailyRevision.fromMap(
        revisionMap,
        placementId: record.placementId,
        recordDate: record.recordDate,
      );
      return SavedBroilerDailyRevision(
        record: record,
        revision: revision,
        sources: sources,
        events: events,
      );
    });
  }

  Future<SavedBroilerDailyRevision?> getCurrentForPlacementDate(
    String placementId,
    DateTime recordDate,
  ) async {
    final db = await _databaseHelper.db;
    final rows = await db.query(
      'broiler_daily_records',
      where: 'placementId = ? AND recordDate = ?',
      whereArgs: [placementId, dateKey(recordDate)],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _loadCurrent(db, BroilerDailyRecord.fromMap(rows.single));
  }

  Future<SavedBroilerDailyRevision?> getPreviousDay(
    String placementId,
    DateTime recordDate,
  ) {
    return getCurrentForPlacementDate(
      placementId,
      recordDate.subtract(const Duration(days: 1)),
    );
  }

  Future<List<BroilerDailyRevision>> listRevisions(String recordId) async {
    final db = await _databaseHelper.db;
    final recordRows = await db.query(
      'broiler_daily_records',
      where: 'id = ?',
      whereArgs: [recordId],
      limit: 1,
    );
    if (recordRows.isEmpty) return const [];
    final record = BroilerDailyRecord.fromMap(recordRows.single);
    final rows = await db.query(
      'broiler_daily_record_revisions',
      where: 'recordId = ?',
      whereArgs: [recordId],
      orderBy: 'revisionNumber',
    );
    return rows
        .map(
          (row) => BroilerDailyRevision.fromMap(
            row,
            placementId: record.placementId,
            recordDate: record.recordDate,
          ),
        )
        .toList(growable: false);
  }

  Future<List<BroilerDailyEntryGridRow>> listFlockDateGrid(
    String flockId,
    DateTime recordDate,
  ) async {
    final db = await _databaseHelper.db;
    final placements = await db.rawQuery(
      '''
      SELECT p.id AS placementId, h.id AS houseId, h.name AS houseName
      FROM flock_placements p
      INNER JOIN houses h ON h.id = p.houseId
      WHERE p.flockId = ?
      ORDER BY h.name, p.placedAt
      ''',
      [flockId],
    );
    final grid = <BroilerDailyEntryGridRow>[];
    for (final placement in placements) {
      final placementId = placement['placementId']! as String;
      grid.add(
        BroilerDailyEntryGridRow(
          placementId: placementId,
          houseId: placement['houseId']! as String,
          houseName: placement['houseName']! as String,
          current: await getCurrentForPlacementDate(placementId, recordDate),
        ),
      );
    }
    return grid;
  }

  Future<List<SavedBroilerDailyRevision>> listCurrentForFlock(
    String flockId, {
    DateTime? rangeStart,
    DateTime? rangeEnd,
  }) async {
    final db = await _databaseHelper.db;
    final clauses = <String>['p.flockId = ?'];
    final arguments = <Object?>[flockId];
    if (rangeStart != null) {
      clauses.add('r.recordDate >= ?');
      arguments.add(dateKey(rangeStart));
    }
    if (rangeEnd != null) {
      clauses.add('r.recordDate <= ?');
      arguments.add(dateKey(rangeEnd));
    }
    final rows = await db.rawQuery('''
      SELECT r.*
      FROM broiler_daily_records r
      INNER JOIN flock_placements p ON p.id = r.placementId
      WHERE ${clauses.join(' AND ')}
      ORDER BY r.recordDate, r.placementId
      ''', arguments);
    final current = <SavedBroilerDailyRevision>[];
    for (final row in rows) {
      final saved = await _loadCurrent(db, BroilerDailyRecord.fromMap(row));
      if (saved != null) current.add(saved);
    }
    return current;
  }

  Future<BroilerDailyRecord?> _findRecord(
    DatabaseExecutor db, {
    required String? recordId,
    required String placementId,
    required String recordDate,
  }) async {
    List<Map<String, Object?>> rows;
    if (recordId != null) {
      rows = await db.query(
        'broiler_daily_records',
        where: 'id = ?',
        whereArgs: [recordId],
        limit: 1,
      );
      if (rows.isEmpty) {
        final dateRows = await db.query(
          'broiler_daily_records',
          where: 'placementId = ? AND recordDate = ?',
          whereArgs: [placementId, recordDate],
          limit: 1,
        );
        if (dateRows.isNotEmpty) {
          throw DailyRecordIdentityConflict(dateRows.single['id']! as String);
        }
        return null;
      }
    } else {
      rows = await db.query(
        'broiler_daily_records',
        where: 'placementId = ? AND recordDate = ?',
        whereArgs: [placementId, recordDate],
        limit: 1,
      );
    }
    return rows.isEmpty ? null : BroilerDailyRecord.fromMap(rows.single);
  }

  Future<int> _nextRevisionNumber(DatabaseExecutor db, String recordId) async {
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(MAX(revisionNumber), 0) + 1 AS nextRevision
      FROM broiler_daily_record_revisions
      WHERE recordId = ?
      ''',
      [recordId],
    );
    return rows.single['nextRevision']! as int;
  }

  Future<SavedBroilerDailyRevision?> _loadCurrent(
    DatabaseExecutor db,
    BroilerDailyRecord record,
  ) async {
    final revisionId = record.currentRevisionId;
    if (revisionId == null) return null;
    final revisionRows = await db.query(
      'broiler_daily_record_revisions',
      where: 'id = ?',
      whereArgs: [revisionId],
      limit: 1,
    );
    if (revisionRows.isEmpty) return null;
    final sourceRows = await db.query(
      'daily_record_sources',
      where: 'revisionId = ?',
      whereArgs: [revisionId],
      orderBy: 'createdAt',
    );
    final eventRows = await db.query(
      'broiler_daily_events',
      where: 'revisionId = ?',
      whereArgs: [revisionId],
      orderBy: 'eventAt, createdAt',
    );
    return SavedBroilerDailyRevision(
      record: record,
      revision: BroilerDailyRevision.fromMap(
        revisionRows.single,
        placementId: record.placementId,
        recordDate: record.recordDate,
      ),
      sources: sourceRows
          .map(DailyRecordSource.fromMap)
          .toList(growable: false),
      events: eventRows.map(BroilerDailyEvent.fromMap).toList(growable: false),
    );
  }
}

class DailyRecordIdentityConflict implements Exception {
  const DailyRecordIdentityConflict(this.existingRecordId);

  final String existingRecordId;
}
