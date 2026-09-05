import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Every checked-in benchmark profile asset. Adding a new official guide
/// means adding its file under `assets/benchmarks/`, declaring it in
/// `pubspec.yaml`, and adding its path here.
const List<String> _kBreederBenchmarkProfileAssetPaths = [
  'assets/benchmarks/aviagen_ross308_parent_stock_2021_en.json',
  'assets/benchmarks/aviagen_arboracres_plus_parent_stock_2021_en.json',
  'assets/benchmarks/aviagen_indianriver_parent_stock_2021_en.json',
  'assets/benchmarks/hubbard_conventional_edge_parent_stock_2025_en.json',
  'assets/benchmarks/cobb500_fast_feather_parent_stock_2020_en.json',
];

const String _kMetricDefinitionsAssetPath =
    'assets/benchmarks/metric_definitions.json';

const _uuid = Uuid();

/// Loads `breeder_metric_definitions` and every checked-in
/// `breeder_benchmark_profiles`/`breeder_benchmark_values` asset file.
///
/// Idempotent and keyed by profile identity: a profile already present under
/// its `profileKey` is left untouched (its rows are immutable once published
/// anyway — see `createBreederBenchmarkTables` in database_schema.dart), so
/// re-running this on every app open or upgrade never duplicates or mutates
/// an already-imported profile. Safe to call before any profile asset exists
/// (metric definitions import happens independently of profiles).
Future<void> importBreederBenchmarks(DatabaseExecutor db) async {
  await _importMetricDefinitions(db);
  for (final assetPath in _kBreederBenchmarkProfileAssetPaths) {
    await _importBenchmarkProfile(db, assetPath);
  }
}

Future<void> _importMetricDefinitions(DatabaseExecutor db) async {
  final raw = await rootBundle.loadString(_kMetricDefinitionsAssetPath);
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final metrics = (decoded['metrics'] as List).cast<Map<String, dynamic>>();

  final now = DateTime.now().toIso8601String();
  final batch = db.batch();
  for (final metric in metrics) {
    final code = metric['code'] as String;
    final existing = await db.query(
      'breeder_metric_definitions',
      columns: ['id'],
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    if (existing.isNotEmpty) continue;
    batch.insert('breeder_metric_definitions', {
      'id': _uuid.v4(),
      'code': code,
      'label': metric['label'],
      'unit': metric['unit'],
      'sexScope': metric['sexScope'],
      'periodType': metric['periodType'],
      'aggregationMethod': metric['aggregationMethod'],
      'displayPrecision': metric['displayPrecision'],
      'createdAt': now,
      'updatedAt': now,
      'syncStatus': 'synced',
      'lastSyncedAt': now,
    });
  }
  await batch.commit(noResult: true);
}

Future<void> _importBenchmarkProfile(
  DatabaseExecutor db,
  String assetPath,
) async {
  final raw = await rootBundle.loadString(assetPath);
  final profile = jsonDecode(raw) as Map<String, dynamic>;
  final profileKey = profile['profileKey'] as String;

  final existing = await db.query(
    'breeder_benchmark_profiles',
    columns: ['id'],
    where: 'profileKey = ?',
    whereArgs: [profileKey],
    limit: 1,
  );
  if (existing.isNotEmpty) {
    // Already imported. Published profiles are immutable, so there is
    // nothing to reconcile even if the asset file has since changed —
    // a changed official guide ships as a new profileKey/version instead.
    return;
  }

  final metricIds = <String, String>{};
  final metricRows = await db.query(
    'breeder_metric_definitions',
    columns: ['id', 'code'],
  );
  for (final row in metricRows) {
    metricIds[row['code'] as String] = row['id'] as String;
  }

  final now = DateTime.now().toIso8601String();
  final profileId = _uuid.v4();

  // Insert as `draft` first so the immutability triggers on
  // breeder_benchmark_values allow the value rows below to be inserted.
  await db.insert('breeder_benchmark_profiles', {
    'id': profileId,
    'profileKey': profileKey,
    'company': profile['company'],
    'breed': profile['breed'],
    'product': profile['product'],
    'guideVersion': profile['guideVersion'],
    'publicationDate': profile['publicationDate'],
    'sourceUrl': profile['sourceUrl'],
    'effectiveAgeStartDays': profile['effectiveAgeStartDays'],
    'effectiveAgeEndDays': profile['effectiveAgeEndDays'],
    'lifecycleCoverage': profile['lifecycleCoverage'],
    'state': 'draft',
    'createdAt': now,
    'updatedAt': now,
    'syncStatus': 'synced',
    'lastSyncedAt': now,
  });

  final values = (profile['values'] as List).cast<Map<String, dynamic>>();
  final batch = db.batch();
  for (final value in values) {
    final metricCode = value['metricCode'] as String;
    final metricId = metricIds[metricCode];
    if (metricId == null) {
      throw StateError(
        'Benchmark asset $assetPath references unknown metric code '
        '"$metricCode" — add it to metric_definitions.json first.',
      );
    }
    batch.insert('breeder_benchmark_values', {
      'id': _uuid.v4(),
      'profileId': profileId,
      'metricId': metricId,
      'sex': value['sex'],
      'ageDays': value['ageDays'],
      'ageWeek': value['ageWeek'],
      'productionWeek': value['productionWeek'],
      'periodType': value['periodType'],
      'targetValue': value['targetValue'],
      'lowerBound': value['lowerBound'],
      'upperBound': value['upperBound'],
      'createdAt': now,
      'updatedAt': now,
      'syncStatus': 'synced',
      'lastSyncedAt': now,
    });
  }
  await batch.commit(noResult: true);

  // Publish. Only this single UPDATE, from state 'draft', is allowed by the
  // immutability trigger — every subsequent write to this row or its values
  // is rejected by the database.
  final targetState = profile['state'] as String? ?? 'active';
  await db.update(
    'breeder_benchmark_profiles',
    {'state': targetState, 'updatedAt': now},
    where: 'id = ?',
    whereArgs: [profileId],
  );
}
