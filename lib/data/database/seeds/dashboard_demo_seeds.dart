import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../../features/audits/models/est_grid_data.dart';
import '../../models/temperature_rh_model.dart';

/// Customer id whose data is a built-in demo for the Scopes dashboard.
/// Real breakout/panel rows are seeded for it (debug only) so the dashboard
/// queries can be exercised end-to-end; the scope UI also limits its example
/// fallback to this customer.
const String kDashboardDemoCustomerId = 'cust-dashboard-test';
const String _alGhareebCustomerId = 'cust-al-ghareeb';
const String _flockId = 'flock-dashboard-demo';
const String _alGhareebRossFlockId = 'flock-gh-sal-rs';
const String _alGhareebIrFlockId = 'flock-gh-moh-ir';
const String _hatcheryId = 'hatchery-dashboard-demo';
const String _sessionId = 'sess-dashboard-demo';
const String _date = '2026-06-01';
const String _ts = '2026-06-01T08:00:00Z';
const String _breed = 'Ross 308';
const int _age = 30; // matches a seeded bmk_egg_breakout ageWeek

/// Idempotent debug-only seed of a demo customer with real breakout/panel rows.
Future<void> ensureDashboardDemoData(DatabaseExecutor db) async {
  if (kReleaseMode) return;
  await _deleteKnownRetiredSeedCustomers(db);
  await _ensureAlGhareebSeedData(db);
  await _upsert(db, 'customers', {
    'id': kDashboardDemoCustomerId,
    'name': 'Dashboard Test Customer',
    'location': 'Test Hatchery',
    'phone': '+20 100 000 0000',
    'email': 'dashboard-test@chickmark.local',
    'createdAt': _ts,
    'createdBy': 'system',
  });
  await _upsert(db, 'flocks', {
    'id': _flockId,
    'customerId': kDashboardDemoCustomerId,
    'flockId': 'DEMO-F1',
    'breed': _breed,
    'entryDate': '2025-11-01',
    'status': 'active',
  });
  await _upsert(db, 'hatcheries', {
    'id': _hatcheryId,
    'customerId': kDashboardDemoCustomerId,
    'name': 'Dashboard Test Hatchery',
    'createdAt': _ts,
    'createdBy': 'system',
  });
  await _upsert(db, 'audit_sessions', {
    'id': _sessionId,
    'customerId': kDashboardDemoCustomerId,
    'flockId': _flockId,
    'hatcheryId': _hatcheryId,
    'date': _date,
    'breed': _breed,
    'flockAgeWeeks': _age,
    'status': 'completed',
    'createdBy': 'system',
    'createdAt': _ts,
    'updatedAt': _ts,
  });

  for (final entry in _panelRows().entries) {
    for (final row in entry.value) {
      // Upsert panel rows so seed-content changes (e.g. newly added raw input
      // arrays) reach existing debug installs without a manual DB wipe. Panel
      // rows are leaves — nothing references them — so replace cannot cascade.
      // Parent entities above use update-based upserts because replacing them
      // would cascade-delete the child rows.
      await _ins(db, entry.key, row, conflict: ConflictAlgorithm.replace);
    }
  }

  for (final row in _goveeRows()) {
    await _ins(
      db,
      'govee_daily_captures',
      row,
      conflict: ConflictAlgorithm.replace,
    );
  }
}

Future<void> _deleteKnownRetiredSeedCustomers(DatabaseExecutor db) async {
  const ids = [
    'cust-dashboard-demo',
    'cust-abdel-fattah-el-barmawy',
    'cust-osama-el-sayed',
    'cust-molting-flock',
    'cust-al-jazira',
    'cust-demo-all-sections',
  ];
  final placeholders = List.filled(ids.length, '?').join(', ');
  await db.delete(
    'govee_daily_captures',
    where: 'customerId IN ($placeholders)',
    whereArgs: ids,
  );
  await db.delete('customers', where: 'id IN ($placeholders)', whereArgs: ids);
}

Future<void> _ensureAlGhareebSeedData(DatabaseExecutor db) async {
  await _upsert(db, 'customers', {
    'id': _alGhareebCustomerId,
    'name': 'الغريب',
    'location': null,
    'phone': null,
    'email': null,
    'createdAt': '2026-04-19T00:00:00Z',
    'createdBy': 'system',
  });
  await _upsert(db, 'flocks', {
    'id': _alGhareebRossFlockId,
    'customerId': _alGhareebCustomerId,
    'flockId': 'Gh Sal Rs',
    'breed': 'Ross308',
    'entryDate': '2025-03-09',
  });
  await _upsert(db, 'flocks', {
    'id': _alGhareebIrFlockId,
    'customerId': _alGhareebCustomerId,
    'flockId': 'Gh Moh IR',
    'breed': 'IR',
    'entryDate': '2025-08-05',
  });
}

Future<void> _ins(
  DatabaseExecutor db,
  String table,
  Map<String, Object?> row, {
  ConflictAlgorithm conflict = ConflictAlgorithm.ignore,
}) {
  return db.insert(table, row, conflictAlgorithm: conflict);
}

Future<void> _upsert(
  DatabaseExecutor db,
  String table,
  Map<String, Object?> row,
) async {
  final inserted = await db.insert(
    table,
    row,
    conflictAlgorithm: ConflictAlgorithm.ignore,
  );
  if (inserted != 0) return;
  await db.update(table, row, where: 'id = ?', whereArgs: [row['id']]);
}

Map<String, Object?> _base(String id, Map<String, Object?> extra) => {
  'id': id,
  'sessionId': _sessionId,
  'customerId': kDashboardDemoCustomerId,
  'flockId': _flockId,
  'hatcheryId': _hatcheryId,
  'date': _date,
  'breed': _breed,
  'flockAgeWeeks': _age,
  'bmkAgeWeeks': _age,
  'createdAt': _ts,
  'updatedAt': _ts,
  'syncStatus': 'synced',
  ...extra,
};

List<Map<String, Object?>> _goveeRows() {
  const specs = [
    _GoveeSeedSpec(
      id: 'demo-govee-egg-storage-room',
      place: TemperaturePlace.eggStorageRoom,
      temperatures: [66.8, 67.0, 67.4, 67.2, 66.9],
      humidities: [72.0, 72.4, 71.8, 72.1, 72.3],
    ),
    _GoveeSeedSpec(
      id: 'demo-govee-chick-holding-area',
      place: TemperaturePlace.chickHoldingArea,
      temperatures: [77.8, 78.0, 78.4, 78.2, 77.9],
      humidities: [60.2, 60.0, 59.8, 60.4, 60.1],
    ),
    _GoveeSeedSpec(
      id: 'demo-govee-setter-room',
      place: TemperaturePlace.setterRoom,
      temperatures: [74.4, 74.7, 75.0, 74.8, 74.6],
      humidities: [52.1, 52.5, 52.0, 52.3, 52.2],
    ),
    _GoveeSeedSpec(
      id: 'demo-govee-inside-setter-s1',
      place: TemperaturePlace.insideSetter,
      machineId: 'S1',
      temperatures: [99.6, 99.8, 100.0, 99.9, 99.7],
      humidities: [53.0, 53.4, 53.1, 53.2, 53.3],
    ),
    _GoveeSeedSpec(
      id: 'demo-govee-hatcher-room',
      place: TemperaturePlace.hatcherRoom,
      temperatures: [76.2, 76.5, 76.8, 76.6, 76.4],
      humidities: [58.2, 58.5, 58.1, 58.3, 58.4],
    ),
    _GoveeSeedSpec(
      id: 'demo-govee-inside-hatcher-h1',
      place: TemperaturePlace.insideHatcher,
      machineId: 'H1',
      temperatures: [98.4, 98.6, 98.9, 98.7, 98.5],
      humidities: [61.0, 61.3, 60.9, 61.2, 61.1],
    ),
  ];

  return specs.map(_goveeRow).toList(growable: false);
}

Map<String, Object?> _goveeRow(_GoveeSeedSpec spec) {
  final tempSd = _stdDev(spec.temperatures);
  final rhSd = _stdDev(spec.humidities);
  final tempAvg = _avg(spec.temperatures);
  final rhAvg = _avg(spec.humidities);
  return {
    'id': spec.id,
    'customerId': kDashboardDemoCustomerId,
    'hatcheryId': _hatcheryId,
    'stationKey': goveeStationKeyForTemperaturePlace(spec.place),
    'place': spec.place.name,
    'machineId': spec.machineId,
    'captureDate': _date,
    'startedAt': _ts,
    'endedAt': '2026-06-01T08:04:00Z',
    'deviceId': 'govee-demo-${spec.id}',
    'deviceName': 'Govee ${spec.place.label}',
    'status': 'completed',
    'tempAvg': tempAvg,
    'tempMin': spec.temperatures.reduce(math.min),
    'tempMax': spec.temperatures.reduce(math.max),
    'tempSd': tempSd,
    'tempCvPct': _cv(tempAvg, tempSd),
    'rhAvg': rhAvg,
    'rhMin': spec.humidities.reduce(math.min),
    'rhMax': spec.humidities.reduce(math.max),
    'rhSd': rhSd,
    'rhCvPct': _cv(rhAvg, rhSd),
    'readingCount': spec.temperatures.length,
    'chartPointsJson': _goveeChartPointsJson(spec),
    'createdAt': _ts,
    'updatedAt': _ts,
    'syncStatus': 'synced',
    'dirtyAt': null,
    'lastSyncedAt': _ts,
    'syncError': null,
  };
}

String _goveeChartPointsJson(_GoveeSeedSpec spec) {
  return jsonEncode([
    for (var i = 0; i < spec.temperatures.length; i++)
      {
        't': DateTime.parse(
          _ts,
        ).add(Duration(minutes: i)).toUtc().toIso8601String(),
        'temp': spec.temperatures[i],
        'rh': spec.humidities[i],
      },
  ]);
}

double _avg(List<double> values) {
  return _round(values.reduce((a, b) => a + b) / values.length);
}

double _stdDev(List<double> values) {
  final mean = _avg(values);
  final variance =
      values.map((value) => math.pow(value - mean, 2)).reduce((a, b) => a + b) /
      values.length;
  return _round(math.sqrt(variance));
}

double _cv(double avg, double sd) => avg == 0 ? 0 : _round(sd / avg * 100);

double _round(double value) => double.parse(value.toStringAsFixed(2));

class _GoveeSeedSpec {
  final String id;
  final TemperaturePlace place;
  final String machineId;
  final List<double> temperatures;
  final List<double> humidities;

  const _GoveeSeedSpec({
    required this.id,
    required this.place,
    this.machineId = '',
    required this.temperatures,
    required this.humidities,
  });
}

int _count(num pct, int traySize) => (pct / 100 * traySize).round();

// ── Round-trip raw inputs ───────────────────────────────────────────────────
// The demo previously seeded only aggregate columns (estAvg, avgWeight, …), so
// the dashboard rendered but the entry screens reopened blank — the raw arrays
// they hydrate from were empty. These helpers fan a seeded aggregate out into
// realistic raw readings whose arithmetic mean is exactly the aggregate, so
// every seeded screen reopens showing the same data a user would have entered.

/// Multipliers averaging exactly 1.0 (≈5% spread) used to derive raw readings
/// from a target mean. Index 0 is replaced by an exact compensator so rounding
/// never drifts the mean.
const List<double> _spreadMultipliers = [
  1.00,
  1.04,
  0.96,
  1.06,
  0.94,
  1.03,
  0.97,
  1.05,
  0.95,
];

/// [n] raw values (1 dp) whose arithmetic mean is exactly [mean], fanned around
/// [mean] for a realistic spread. Deterministic — no RNG, so seeds are stable.
List<double> _rawValues(double mean, int n) {
  final values = <double>[];
  for (var i = 1; i < n; i++) {
    final mult = _spreadMultipliers[i % _spreadMultipliers.length];
    values.add(double.parse((mean * mult).toStringAsFixed(1)));
  }
  final rest = values.fold<double>(0, (sum, v) => sum + v);
  values.insert(0, double.parse((mean * n - rest).toStringAsFixed(1)));
  return values;
}

/// 9-cell EST/CVT grid map keyed by [EstGridData.scanKeys] with mean == [mean].
Map<String, double> _gridMap(double mean) {
  final vals = _rawValues(mean, EstGridData.scanKeys.length);
  return {
    for (var i = 0; i < EstGridData.scanKeys.length; i++)
      EstGridData.scanKeys[i]: vals[i],
  };
}

/// JSON object form of [_gridMap] for `estReadingsJson` / `cvtReadingsJson`.
String _gridJson(double mean) => jsonEncode(_gridMap(mean));

/// JSON list of [n] raw weights (1 dp) with mean == [mean] for `*WeightsJson`.
String _weightsJson(double mean, int n) => jsonEncode(_rawValues(mean, n));

Map<String, List<Map<String, Object?>>> _panelRows() => {
  'residue_breakout': _residueRows(),
  'candled_egg_breakout': _candledRows(),
  'fresh_egg_breakout': _freshRows(),
  'egg_quality': _eggQualityRows(),
  'chick_quality': _chickQualityRows(),
  'chick_weights': _chickWeightRows(),
  'egg_storage': _eggStorageRows(),
  'setter_optimizing': _setterRows(),
  'hatcher_optimizing': _hatcherRows(),
};

// ── Residue: full crossed 16 leaves ─────────────────────────────────────────
List<Map<String, Object?>> _residueRows() {
  // h, setter, hatcher, trolley, tray, [infert, early, mid, late, extpip, crack, contam, fert]
  const data = <List<Object?>>[
    ['H1', 'S1', 'H1', 'Tr1', 'Ty1', 7.9, 2.2, 0.8, 3.0, 0.6, 0.3, 0.4, 92.1],
    ['H1', 'S1', 'H1', 'Tr1', 'Ty2', 8.0, 2.1, 0.9, 3.4, 0.5, 0.4, 0.5, 92.0],
    ['H1', 'S1', 'H1', 'Tr2', 'Ty1', 7.7, 2.3, 0.9, 2.9, 0.6, 0.3, 0.5, 92.2],
    ['H1', 'S1', 'H1', 'Tr2', 'Ty2', 8.1, 2.0, 1.0, 3.1, 0.7, 0.4, 0.4, 91.9],
    ['H1', 'S2', 'H2', 'Tr1', 'Ty1', 7.5, 2.4, 1.0, 2.8, 0.6, 0.3, 0.6, 92.4],
    ['H1', 'S2', 'H2', 'Tr1', 'Ty2', 7.8, 2.5, 1.1, 2.7, 0.7, 0.4, 0.5, 92.3],
    ['H1', 'S2', 'H2', 'Tr2', 'Ty1', 7.6, 2.4, 1.0, 2.8, 0.7, 0.3, 0.6, 92.4],
    ['H1', 'S2', 'H2', 'Tr2', 'Ty2', 7.9, 2.6, 1.2, 3.0, 0.6, 0.4, 0.7, 92.0],
    ['H2', 'S1', 'H1', 'Tr1', 'Ty1', 8.2, 2.6, 1.1, 2.9, 0.6, 0.5, 0.4, 91.8],
    ['H2', 'S1', 'H1', 'Tr1', 'Ty2', 8.4, 2.5, 1.0, 3.0, 0.7, 0.5, 0.5, 91.6],
    ['H2', 'S1', 'H1', 'Tr2', 'Ty1', 8.0, 2.3, 0.9, 2.9, 0.6, 0.4, 0.4, 92.0],
    ['H2', 'S1', 'H1', 'Tr2', 'Ty2', 8.3, 2.7, 1.2, 3.5, 0.8, 0.6, 0.6, 91.5],
    ['H2', 'S2', 'H2', 'Tr1', 'Ty1', 7.7, 2.2, 0.9, 2.8, 0.6, 0.3, 0.5, 92.3],
    ['H2', 'S2', 'H2', 'Tr1', 'Ty2', 7.8, 2.3, 1.0, 2.9, 0.5, 0.4, 0.5, 92.2],
    ['H2', 'S2', 'H2', 'Tr2', 'Ty1', 7.9, 2.4, 1.0, 2.7, 0.7, 0.3, 0.6, 92.1],
    ['H2', 'S2', 'H2', 'Tr2', 'Ty2', 8.1, 2.5, 1.1, 3.2, 0.7, 0.5, 0.7, 91.9],
  ];
  const t = 150;
  final rows = <Map<String, Object?>>[];
  for (var i = 0; i < data.length; i++) {
    final d = data[i];
    final infert = d[5] as num,
        early = d[6] as num,
        mid = d[7] as num,
        late = d[8] as num,
        extpip = d[9] as num,
        crack = d[10] as num,
        contam = d[11] as num,
        fert = d[12] as num;
    final infC = _count(infert, t),
        earlyC = _count(early, t),
        midC = _count(mid, t),
        lateC = _count(late, t),
        extC = _count(extpip, t),
        crackC = _count(crack, t),
        contamC = _count(contam, t);
    final hatched = t - infC - earlyC - midC - lateC - extC - crackC - contamC;
    rows.add(
      _base('demo-res-$i', {
        'house': d[0],
        'setter': d[1],
        'hatcher': d[2],
        'trolley': d[3],
        'tray': d[4],
        'traySize': t,
        'infertileCount': infC,
        'earlyDeadCount': earlyC,
        'midDeadCount': midC,
        'lateDeadCount': lateC,
        'externalPipCount': extC,
        'crackedCount': crackC,
        'contaminatedCount': contamC,
        'infertilePct': infert,
        'earlyDeadPct': early,
        'midDeadPct': mid,
        'lateDeadPct': late,
        'externalPipPct': extpip,
        'crackedPct': crack,
        'contaminatedPct': contam,
        'totalEggsSet': t,
        'hatchedCount': hatched,
        'culledCount': 0,
        'deadCount': 0,
        'hatchabilityPct': (100 * hatched / t),
        'fertilityPct': fert,
        'hofPct': fert - 0.5,
        'culledPct': 0.0,
        'deadPct': 0.0,
      }),
    );
  }
  return rows;
}

// ── Candled: 4 leaves ───────────────────────────────────────────────────────
List<Map<String, Object?>> _candledRows() {
  const data = <List<Object?>>[
    ['H1', 'S1', 'H1', 'Tr2', 'Ty5', 7.7, 2.0, 1.0, 0.8, 1.4],
    ['H1', 'S1', 'H1', 'Tr2', 'Ty6', 8.1, 2.2, 1.2, 0.9, 1.6],
    ['H2', 'S2', 'H2', 'Tr1', 'Ty5', 7.5, 1.9, 0.9, 0.7, 1.3],
    ['H2', 'S2', 'H2', 'Tr1', 'Ty6', 7.9, 2.1, 1.1, 0.8, 1.5],
  ];
  const t = 150;
  final rows = <Map<String, Object?>>[];
  for (var i = 0; i < data.length; i++) {
    final d = data[i];
    final infert = d[5] as num,
        e24 = d[6] as num,
        e48 = d[7] as num,
        blood = d[8] as num,
        black = d[9] as num;
    rows.add(
      _base('demo-cand-$i', {
        'house': d[0],
        'setter': d[1],
        'hatcher': d[2],
        'trolley': d[3],
        'tray': d[4],
        'candlingDay': 10,
        'traySize': t,
        'infertileCount': _count(infert, t),
        'early24hCount': _count(e24, t),
        'early48hCount': _count(e48, t),
        'bloodRingCount': _count(blood, t),
        'blackEyeCount': _count(black, t),
        'infertilePct': infert,
        'early24hPct': e24,
        'early48hPct': e48,
        'bloodRingPct': blood,
        'blackEyePct': black,
      }),
    );
  }
  return rows;
}

// ── Fresh: house × tray ─────────────────────────────────────────────────────
List<Map<String, Object?>> _freshRows() {
  const data = <List<Object?>>[
    ['House A', 'Tray 1', 7.9, 1.2, 0.9, 0.6],
    ['House A', 'Tray 2', 8.4, 1.4, 1.1, 0.7],
    ['House B', 'Tray 1', 7.6, 1.1, 0.8, 0.5],
    ['House B', 'Tray 2', 8.1, 1.3, 1.0, 0.6],
  ];
  const t = 150;
  final rows = <Map<String, Object?>>[];
  for (var i = 0; i < data.length; i++) {
    final d = data[i];
    final infert = d[2] as num,
        e24 = d[3] as num,
        e48 = d[4] as num,
        blood = d[5] as num;
    rows.add(
      _base('demo-fresh-$i', {
        'house': d[0],
        'tray': d[1],
        'traySize': t,
        'infertileCount': _count(infert, t),
        'early24hCount': _count(e24, t),
        'early48hCount': _count(e48, t),
        'bloodRingCount': _count(blood, t),
        'infertilePct': infert,
        'early24hPct': e24,
        'early48hPct': e48,
        'bloodRingPct': blood,
      }),
    );
  }
  return rows;
}

// ── Egg quality: per house ──────────────────────────────────────────────────
List<Map<String, Object?>> _eggQualityRows() => [
  _base('demo-eq-0', {
    'house': 'House A',
    'eggSampleSize': 92,
    'eggWeightsJson': _weightsJson(62.4, 92),
    'eggAvgWeight': 62.4,
    'eggUniformityPct': 88.2,
    'eggCvPct': 6.1,
    'eggBmkAgeWeeks': _age,
    'eggBmkWeight': 63.0,
    'uvTrayEggCount': 150,
    'uvAffectedCount': _count(3.2, 150),
    'uvAffectedPct': 3.2,
    'uvCuticleDamageCount': _count(1.1, 150),
    'uvCuticleDamagePct': 1.1,
    'uvWashedCount': _count(0.4, 150),
    'uvWashedPct': 0.4,
    'uvDirtyCount': _count(0.8, 150),
    'uvDirtyPct': 0.8,
  }),
  _base('demo-eq-1', {
    'house': 'House B',
    'eggSampleSize': 88,
    'eggWeightsJson': _weightsJson(61.2, 88),
    'eggAvgWeight': 61.2,
    'eggUniformityPct': 83.4,
    'eggCvPct': 8.6,
    'eggBmkAgeWeeks': _age,
    'eggBmkWeight': 63.0,
    'uvTrayEggCount': 150,
    'uvAffectedCount': _count(4.1, 150),
    'uvAffectedPct': 4.1,
    'uvCuticleDamageCount': _count(1.6, 150),
    'uvCuticleDamagePct': 1.6,
    'uvWashedCount': _count(0.6, 150),
    'uvWashedPct': 0.6,
    'uvDirtyCount': _count(1.2, 150),
    'uvDirtyPct': 1.2,
  }),
];

// ── Chick quality: per machine ──────────────────────────────────────────────
List<Map<String, Object?>> _chickQualityRows() => [
  _base('demo-cq-0', {
    'setter': 'S1',
    'hatcher': 'H1',
    'pasgarSampleSize': 100,
    'pasgarFinalScore': 8.7,
    'pasgarReflexesCount': _count(2.0, 100),
    'pasgarReflexesPct': 2.0,
    'pasgarBeakCount': _count(3.0, 100),
    'pasgarBeakPct': 3.0,
    'pasgarNavelCount': _count(9.0, 100),
    'pasgarNavelPct': 9.0,
    'pasgarBellyCount': _count(5.0, 100),
    'pasgarBellyPct': 5.0,
    'pasgarLegCount': _count(3.0, 100),
    'pasgarLegPct': 3.0,
    'pasgarFeatherDevCount': _count(1.0, 100),
    'pasgarFeatherDevPct': 1.0,
    'cvtSampleSize': 9,
    'cvtReadingsJson': _gridJson(104.1),
    'cvtAvgTemp': 104.1,
    'cvtCvPct': 5.5,
    'yfbmAvgPct': 9.1,
  }),
  _base('demo-cq-1', {
    'setter': 'S2',
    'hatcher': 'H2',
    'pasgarSampleSize': 100,
    'pasgarFinalScore': 8.4,
    'pasgarReflexesCount': _count(2.0, 100),
    'pasgarReflexesPct': 2.0,
    'pasgarBeakCount': _count(4.0, 100),
    'pasgarBeakPct': 4.0,
    'pasgarNavelCount': _count(21.0, 100),
    'pasgarNavelPct': 21.0,
    'pasgarBellyCount': _count(6.0, 100),
    'pasgarBellyPct': 6.0,
    'pasgarLegCount': _count(3.0, 100),
    'pasgarLegPct': 3.0,
    'pasgarFeatherDevCount': _count(1.0, 100),
    'pasgarFeatherDevPct': 1.0,
    'cvtSampleSize': 9,
    'cvtReadingsJson': _gridJson(104.0),
    'cvtAvgTemp': 104.0,
    'cvtCvPct': 6.0,
    'yfbmAvgPct': 9.4,
  }),
];

// ── Chick weights: per house ────────────────────────────────────────────────
List<Map<String, Object?>> _chickWeightRows() => [
  _base('demo-cw-0', {
    'house': 'House A',
    'sampleSize': 100,
    'weightsJson': _weightsJson(42.3, 100),
    'avgWeight': 42.3,
    'uniformityPct': 87.0,
    'cvPct': 6.8,
    'bmkWeight': 42.5,
  }),
  _base('demo-cw-1', {
    'house': 'House B',
    'sampleSize': 100,
    'weightsJson': _weightsJson(41.8, 100),
    'avgWeight': 41.8,
    'uniformityPct': 85.0,
    'cvPct': 7.2,
    'bmkWeight': 42.5,
  }),
];

// ── Egg storage: pooled ─────────────────────────────────────────────────────
List<Map<String, Object?>> _eggStorageRows() => [
  _base('demo-es-0', {
    // estAvg is the EST grid average (egg screen derives it from the mean).
    'estReadingsJson': _gridJson(20.0),
    'estAvg': 20.0, 'estCvPct': 4.2,
    'storagePeriodDays': 4, 'turningTimes': 2, 'traySpacing': 'Adequate',
    'coolerProximity': 'Far', 'condensationPresent': 0, 'upsideDownPct': 0.6,
  }),
];

// ── Setter optimizing: per setter ───────────────────────────────────────────
/// Setter EST is stored as a list of sample objects (`estSamplesJson`); the
/// screen hydrates the grid from `sample['estReadings']`. One sample whose grid
/// mean equals [avg] keeps the panel round-trip complete.
String _setterEstSamplesJson(String id, double avg, double cv) => jsonEncode([
  {
    'id': id,
    'breed': 'Ross308',
    'incubationAge': 12,
    'incubationHours': 0,
    'estReadings': _gridMap(avg),
    'estPhotos': <String, String>{},
    'estAvg': avg,
    'estCv': cv,
  },
]);

List<Map<String, Object?>> _setterRows() => [
  _base('demo-set-0', {
    'setter': 'S-01',
    'setpointF': 100.0,
    'actualF': 100.2,
    'setpointRh': 55,
    'actualRh': 54,
    'turningAngle': 45,
    'co2Ppm': 2700,
    'incubationAgeDays': 12,
    'incubationHours': 0,
    'estSampleSize': 9,
    'estReadingsJson': _gridJson(100.3),
    'estSamplesJson': _setterEstSamplesJson('demo-set-0', 100.3, 6.4),
    'estAvg': 100.3,
    'estCvPct': 6.4,
    'batchSize': 14400,
    'batchCount': 1,
  }),
  _base('demo-set-1', {
    'setter': 'S-03',
    'setpointF': 100.0,
    'actualF': 100.4,
    'setpointRh': 55,
    'actualRh': 53,
    'turningAngle': 45,
    'co2Ppm': 2900,
    'incubationAgeDays': 12,
    'incubationHours': 0,
    'estSampleSize': 9,
    'estReadingsJson': _gridJson(100.4),
    'estSamplesJson': _setterEstSamplesJson('demo-set-1', 100.4, 9.1),
    'estAvg': 100.4,
    'estCvPct': 9.1,
    'batchSize': 14400,
    'batchCount': 1,
  }),
];

// ── Hatcher optimizing: per hatcher ─────────────────────────────────────────
List<Map<String, Object?>> _hatcherRows() => [
  _base('demo-hat-0', {
    'hatcher': 'H-01',
    'setpointF': 98.5,
    'setpointRh': 60,
    'co2Ppm': 2800,
    'cvtSampleSize': 9,
    'cvtReadingsJson': _gridJson(103.6),
    'cvtAvg': 103.6,
    'cvtCvPct': 6.1,
    'chickPanting': 0,
    'meconium': 'None',
    'transferDay': 18,
  }),
  _base('demo-hat-1', {
    'hatcher': 'H-02',
    'setpointF': 98.5,
    'setpointRh': 60,
    'co2Ppm': 3100,
    'cvtSampleSize': 9,
    'cvtReadingsJson': _gridJson(103.8),
    'cvtAvg': 103.8,
    'cvtCvPct': 6.5,
    'chickPanting': 0,
    'meconium': 'None',
    'transferDay': 18,
  }),
];
