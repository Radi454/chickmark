part of 'database_helper.dart';

Future<void> _applyV18Upgrade(Database db) async {}

Future<void> _applyV19Upgrade(Database db) async {}

Future<void> _applyV20Upgrade(Database db) async {}

Future<void> _applyV21Upgrade(Database db) async {}

Future<void> _applyV22Upgrade(Database db) async {}

Future<void> _applyV23Upgrade(Database db) async {}

Future<void> _applyV24Upgrade(Database db) async {}

Future<void> _applyV25Upgrade(Database db) async {}

Future<void> _applyV26Upgrade(Database db) async {}

Future<void> _applyV27Upgrade(Database db) async {}

Future<void> _applyV28Upgrade(Database db) async {}

Future<void> _applyV29Upgrade(Database db) async {}

Future<void> _applyV30Upgrade(Database db) async {}

Future<void> _applyV31Upgrade(Database db) async {}

Future<void> _applyV32Upgrade(Database db) async {}

Future<void> _applyV33Upgrade(Database db) async {}

Future<void> _applyV34Upgrade(Database db) async {}

Future<void> _applyV35Upgrade(Database db) async {}

Future<bool> _tableExists(DatabaseExecutor db, String table) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
    [table],
  );
  return rows.isNotEmpty;
}

Future<void> _ensureDummyTestData(Database db) async {
  if (kReleaseMode) return;
  for (final seed in kDummyCustomerSeeds) {
    await _upsertSeedById(db, 'customers', seed);
  }
  for (final seed in kDummyFlockSeeds) {
    await _upsertSeedById(db, 'flocks', seed);
  }
}

Future<void> _upsertSeedById(
  Database db,
  String table,
  Map<String, dynamic> seed,
) async {
  final inserted = await db.insert(
    table,
    seed,
    conflictAlgorithm: ConflictAlgorithm.ignore,
  );
  if (inserted != 0) return;
  await db.update(table, seed, where: 'id = ?', whereArgs: [seed['id']]);
}

Future<void> _seedTroubleshooting(Database db) async {
  final columns = await db.rawQuery('PRAGMA table_info(troubleshooting)');
  final columnNames = columns.map((row) => row['name'] as String).toSet();
  for (final entry in kTroubleshootingSeeds.entries) {
    final row = <String, Object?>{
      'id': entry.key,
      'hatcheryCauses': jsonEncode(entry.value['hatcheryCauses']),
      'farmFlockCauses': jsonEncode(entry.value['farmFlockCauses']),
    };
    if (columnNames.contains('benchmarkJson')) {
      row['benchmarkJson'] = entry.value['benchmark'] == null
          ? null
          : jsonEncode(entry.value['benchmark']);
    }
    if (columnNames.contains('interpretationJson')) {
      row['interpretationJson'] = entry.value['interpretation'] == null
          ? null
          : jsonEncode(entry.value['interpretation']);
    }
    if (columnNames.contains('sourceRefsJson')) {
      row['sourceRefsJson'] = entry.value['sourceRefs'] == null
          ? null
          : jsonEncode(entry.value['sourceRefs']);
    }
    await db.insert(
      'troubleshooting',
      row,
      conflictAlgorithm: entry.value.containsKey('sourceRefs')
          ? ConflictAlgorithm.replace
          : ConflictAlgorithm.ignore,
    );
  }
}

Future<void> _backfillEggBreakoutAliases(Database db) async {
  final columns = _columnNames(
    await db.rawQuery("PRAGMA table_info('bmk_egg_breakout')"),
  );
  if (!columns.containsAll({
    'earlyDeadPct',
    'midBlackEyePct',
    'internalPipPct',
    'externalPipPct',
    'midDeadPct',
    'blackEyePct',
    'pippedInternalPct',
    'pippedExternalPct',
  })) {
    return;
  }
  await db.execute('''
    UPDATE bmk_egg_breakout
    SET
      earlyDeadPct = CASE WHEN earlyDeadPct = 0 THEN midDeadPct ELSE earlyDeadPct END,
      midBlackEyePct = CASE WHEN midBlackEyePct = 0 THEN blackEyePct ELSE midBlackEyePct END,
      internalPipPct = CASE WHEN internalPipPct = 0 THEN pippedInternalPct ELSE internalPipPct END,
      externalPipPct = CASE WHEN externalPipPct = 0 THEN pippedExternalPct ELSE externalPipPct END
  ''');
}

Future<void> _backfillOperationalBmkSeedSources(Database db) async {
  if (!await _tableExists(db, 'bmk_operational_standards')) return;
  final columns = _columnNames(
    await db.rawQuery("PRAGMA table_info('bmk_operational_standards')"),
  );
  if (!columns.contains('sourceUrl')) return;

  for (final seed in kBmkOperationalStandardSeeds) {
    await db.update(
      'bmk_operational_standards',
      {'source': seed['source'], 'sourceUrl': seed['sourceUrl']},
      where: 'id = ? AND hatcheryId IS NULL',
      whereArgs: [seed['id']],
    );
  }
}

Future<void> _ensureCompleteBmkBreedSeedData(Database db) async {
  const breeds = ['Ross308', 'Arbo', 'Avian', 'Cobb500', 'Hubbard', 'IR'];
  for (final breed in breeds) {
    final startAge = breed == 'Cobb500' ? 24 : 25;
    for (var age = startAge; age <= 65; age++) {
      final existing = await db.query(
        'bmk_breeds',
        where: 'breed = ? AND ageWeek = ?',
        whereArgs: [breed, age],
        limit: 1,
      );
      if (existing.isNotEmpty) continue;
      final template = await _nearestBmkBreedRow(db, breed, age);
      if (template == null) continue;
      await db.insert('bmk_breeds', {
        'id': '${breed.toLowerCase()}-$age',
        'breed': breed,
        'ageWeek': age,
        'hatchabilityPct': template['hatchabilityPct'],
        'fertilityPct': template['fertilityPct'],
        'hofPct': template['hofPct'],
        'productionPct': template['productionPct'],
        'eggWeightG': template['eggWeightG'],
        'chickWeightG': template['chickWeightG'],
      });
    }
  }
}

Future<Map<String, Object?>?> _nearestBmkBreedRow(
  Database db,
  String breed,
  int age,
) async {
  final rows = await db.query(
    'bmk_breeds',
    where: 'breed = ?',
    whereArgs: [breed],
    orderBy: 'ABS(ageWeek - $age) ASC',
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
}

Set<String> _columnNames(List<Map<String, Object?>> tableInfo) {
  return tableInfo
      .map((row) => row['name']?.toString())
      .whereType<String>()
      .toSet();
}
