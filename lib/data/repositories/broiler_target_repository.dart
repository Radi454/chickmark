import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../database/seeds/broiler_target_seeds.dart';
import '../models/broiler_target_models.dart';
import '../models/poultry_hierarchy_models.dart';
import 'sync_tombstone_repository.dart';

class BroilerTargetRepository {
  BroilerTargetRepository({
    DatabaseHelper? databaseHelper,
    Uuid uuid = const Uuid(),
  }) : _databaseHelper = databaseHelper ?? DatabaseHelper(),
       _uuid = uuid;

  final DatabaseHelper _databaseHelper;
  final Uuid _uuid;

  Future<void> ensureOfficialCatalogueSeeded() async {
    final db = await _databaseHelper.db;
    await db.transaction((txn) async {
      for (final entry in officialBroilerTargetCatalogue) {
        await txn.insert(
          'broiler_target_profiles',
          entry.profile.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        final batch = txn.batch();
        for (final row in entry.rows) {
          batch.insert(
            'broiler_target_rows',
            row.toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        await batch.commit(noResult: true);
      }
    });
  }

  Future<List<BroilerTargetProfile>> listProfiles({
    String? brand,
    String? breed,
    FlockSexProfile? sexProfile,
    bool activeOnly = false,
  }) async {
    final db = await _databaseHelper.db;
    final clauses = <String>[];
    final arguments = <Object?>[];
    if (brand != null) {
      clauses.add('brand = ?');
      arguments.add(brand);
    }
    if (breed != null) {
      clauses.add('breed = ?');
      arguments.add(breed);
    }
    if (sexProfile != null) {
      clauses.add('sexProfile = ?');
      arguments.add(sexProfile.storageKey);
    }
    if (activeOnly) {
      clauses.add('isActive = 1');
    }
    final rows = await db.query(
      'broiler_target_profiles',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: arguments.isEmpty ? null : arguments,
      orderBy: 'brand, breed, sexProfile, publicationVersion DESC',
    );
    return rows.map(BroilerTargetProfile.fromMap).toList(growable: false);
  }

  Future<BroilerTargetRow?> getRow(String profileId, int ageDay) async {
    final db = await _databaseHelper.db;
    final rows = await db.query(
      'broiler_target_rows',
      where: 'profileId = ? AND ageDay = ?',
      whereArgs: [profileId, ageDay],
      limit: 1,
    );
    return rows.isEmpty ? null : BroilerTargetRow.fromMap(rows.single);
  }

  Future<BroilerTargetProfile> createCustomProfileVersion({
    required String sourceProfileId,
    required String publicationVersion,
    required String createdBy,
  }) async {
    final normalizedVersion = publicationVersion.trim();
    if (normalizedVersion.isEmpty) {
      throw ArgumentError.value(
        publicationVersion,
        'publicationVersion',
        'A version label is required.',
      );
    }
    final db = await _databaseHelper.db;
    return db.transaction((txn) async {
      final source = await _getProfile(txn, sourceProfileId);
      if (source == null) {
        throw TargetProfileNotFoundException(sourceProfileId);
      }
      final duplicate = await txn.query(
        'broiler_target_profiles',
        columns: const ['id'],
        where:
            'brand = ? AND breed = ? AND sexProfile = ? '
            'AND publicationVersion = ?',
        whereArgs: [
          source.brand,
          source.breed,
          source.sexProfile.storageKey,
          normalizedVersion,
        ],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        throw TargetProfileVersionConflict(normalizedVersion);
      }

      final now = DateTime.now().toUtc();
      final profileId = '${source.id}-custom-${_uuid.v4()}';
      final draft = source.copyWith(
        id: profileId,
        publicationVersion: normalizedVersion,
        sourceTitle: 'Custom profile based on ${source.sourceTitle}',
        isOfficial: false,
        isActive: false,
        supersedesProfileId: source.id,
        createdBy: createdBy,
        createdAt: now,
        updatedAt: now,
        syncStatus: 'pending',
        dirtyAt: now,
        clearActiveFrom: true,
        clearActiveTo: true,
      );
      await txn.insert('broiler_target_profiles', draft.toMap());

      final sourceRows = await txn.query(
        'broiler_target_rows',
        where: 'profileId = ?',
        whereArgs: [source.id],
        orderBy: 'ageDay',
      );
      final batch = txn.batch();
      for (final sourceMap in sourceRows) {
        final sourceRow = BroilerTargetRow.fromMap(sourceMap);
        batch.insert(
          'broiler_target_rows',
          sourceRow
              .copyWith(
                id: '$profileId-day-${sourceRow.ageDay}',
                profileId: profileId,
                createdAt: now,
                updatedAt: now,
                syncStatus: 'pending',
                dirtyAt: now,
              )
              .toMap(),
        );
      }
      await batch.commit(noResult: true);
      return draft;
    });
  }

  Future<void> replaceRowsInDraftVersion(
    String profileId,
    List<BroilerTargetRow> rows,
  ) async {
    final ages = rows.map((row) => row.ageDay).toSet();
    if (ages.length != rows.length) {
      throw const DuplicateTargetAgeException();
    }
    final db = await _databaseHelper.db;
    await db.transaction((txn) async {
      final profile = await _getProfile(txn, profileId);
      if (profile == null) {
        throw TargetProfileNotFoundException(profileId);
      }
      if (profile.isOfficial || profile.isActive) {
        throw TargetProfileImmutableException(profileId);
      }

      final existingRows = await txn.query(
        'broiler_target_rows',
        columns: const ['id'],
        where: 'profileId = ?',
        whereArgs: [profileId],
      );
      await SyncTombstoneRepository.queueDeletesWithExecutor(
        txn,
        'broiler_target_rows',
        existingRows.map((row) => row['id']),
      );
      await txn.delete(
        'broiler_target_rows',
        where: 'profileId = ?',
        whereArgs: [profileId],
      );
      final now = DateTime.now().toUtc();
      final batch = txn.batch();
      for (final row in rows) {
        batch.insert(
          'broiler_target_rows',
          row
              .copyWith(
                id: '$profileId-day-${row.ageDay}',
                profileId: profileId,
                createdAt: row.createdAt ?? now,
                updatedAt: now,
                syncStatus: 'pending',
                dirtyAt: now,
              )
              .toMap(),
        );
      }
      await batch.commit(noResult: true);
      await txn.update(
        'broiler_target_profiles',
        {
          'updatedAt': now.toIso8601String(),
          'dirtyAt': now.toIso8601String(),
          'syncStatus': 'pending',
          'syncError': null,
        },
        where: 'id = ?',
        whereArgs: [profileId],
      );
    });
  }

  Future<void> activateVersion(String profileId) async {
    final db = await _databaseHelper.db;
    await db.transaction((txn) async {
      final profile = await _getProfile(txn, profileId);
      if (profile == null) {
        throw TargetProfileNotFoundException(profileId);
      }
      final countRows = await txn.rawQuery(
        'SELECT COUNT(*) AS count FROM broiler_target_rows WHERE profileId = ?',
        [profileId],
      );
      if ((countRows.single['count'] as int) == 0) {
        throw TargetProfileHasNoRowsException(profileId);
      }

      final now = DateTime.now().toUtc().toIso8601String();
      await txn.update(
        'broiler_target_profiles',
        {
          'isActive': 0,
          'activeTo': now,
          'updatedAt': now,
          'dirtyAt': now,
          'syncStatus': 'pending',
          'syncError': null,
        },
        where:
            'brand = ? AND breed = ? AND sexProfile = ? '
            'AND isActive = 1 AND id <> ?',
        whereArgs: [
          profile.brand,
          profile.breed,
          profile.sexProfile.storageKey,
          profileId,
        ],
      );
      await txn.update(
        'broiler_target_profiles',
        {
          'isActive': 1,
          'activeFrom': now,
          'activeTo': null,
          'updatedAt': now,
          'dirtyAt': now,
          'syncStatus': 'pending',
          'syncError': null,
        },
        where: 'id = ?',
        whereArgs: [profileId],
      );
    });
  }

  Future<BroilerTargetProfile?> _getProfile(
    DatabaseExecutor db,
    String profileId,
  ) async {
    final rows = await db.query(
      'broiler_target_profiles',
      where: 'id = ?',
      whereArgs: [profileId],
      limit: 1,
    );
    return rows.isEmpty ? null : BroilerTargetProfile.fromMap(rows.single);
  }
}

class TargetProfileNotFoundException implements Exception {
  const TargetProfileNotFoundException(this.profileId);

  final String profileId;

  @override
  String toString() => 'Target profile not found: $profileId';
}

class TargetProfileVersionConflict implements Exception {
  const TargetProfileVersionConflict(this.publicationVersion);

  final String publicationVersion;
}

class TargetProfileImmutableException implements Exception {
  const TargetProfileImmutableException(this.profileId);

  final String profileId;
}

class DuplicateTargetAgeException implements Exception {
  const DuplicateTargetAgeException();
}

class TargetProfileHasNoRowsException implements Exception {
  const TargetProfileHasNoRowsException(this.profileId);

  final String profileId;
}
