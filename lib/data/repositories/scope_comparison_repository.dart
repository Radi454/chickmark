import '../../features/dashboard/models/dashboard_filter.dart';
import '../../features/dashboard/models/scope_cumulative.dart';
import '../../features/dashboard/models/dashboard_intelligence_models.dart';
import '../../features/dashboard/scope/scope_config.dart';
import '../../features/dashboard/scope/scope_models.dart';
import '../database/database_helper.dart';
import '../models/panel_sample_schema.dart';
import '../services/panel_aggregate_deriver.dart';

/// Fetches the finest-grain sample rows for a scope sector and turns each into a
/// [ScopeLeafRow] (with per-layer segments + per-parameter accumulators). The
/// engine ([ScopeEngine]) then composes/aggregates these client-side, so layer
/// toggles never re-hit the DB.
class ScopeComparisonRepository {
  ScopeComparisonRepository({DatabaseHelper? dbHelper})
    : _dbHelper = dbHelper ?? DatabaseHelper();

  final DatabaseHelper _dbHelper;

  /// DB columns backing each breakdown layer. `setterHatcher` is the concat of
  /// the separate `setter` + `hatcher` columns (e.g. "S1H1").
  static const Map<SamplingLayer, List<String>> _layerColumns = {
    SamplingLayer.house: ['house'],
    SamplingLayer.setterHatcher: ['setter', 'hatcher'],
    SamplingLayer.setter: ['setter'],
    SamplingLayer.hatcher: ['hatcher'],
    SamplingLayer.trolley: ['trolley'],
    SamplingLayer.tray: ['tray'],
  };

  Future<List<ScopeLeafRow>> getScopeLeaves(
    ScopeSectorConfig sector,
    DashboardFilter filter,
  ) async {
    final table = sector.tableName;
    if (table == null) return const []; // dummy-only sector (no backing table)
    final ageColumn = _ageColumnFor(table);

    final def = PanelSampleSchema.byTable(table);
    final existing = <String>{
      ...def.hierarchyColumnNames,
      ...def.measurementColumns.map((d) => d.split(' ').first),
    };

    final nonPool = sector.allowedLayers
        .where((l) => l != SamplingLayer.pool)
        .toList();

    final hierCols = <String>{};
    for (final layer in nonPool) {
      for (final col in (_layerColumns[layer] ?? const <String>[])) {
        if (existing.contains(col)) hierCols.add(col);
      }
    }

    final measureCols = <String>{};
    final hasTray = existing.contains('traySize');
    if (hasTray) measureCols.add('traySize');
    for (final p in sector.params) {
      if (existing.contains(p.column)) measureCols.add(p.column);
      final cc = p.countColumn;
      if (cc != null && existing.contains(cc)) measureCols.add(cc);
      final denominator = p.denominatorColumn;
      if (denominator != null && existing.contains(denominator)) {
        measureCols.add(denominator);
      }
    }

    final selectCols = {...hierCols, ...measureCols}.toList();
    if (selectCols.isEmpty) return const [];

    final db = await _dbHelper.db;
    final (:clause, :args) = _where(filter, bmkColumn: ageColumn);
    final rows = await db.rawQuery(
      'SELECT ${selectCols.join(', ')}, '
      '$ageColumn AS _scopeBmkAge FROM $table $clause',
      args,
    );

    return _leavesFromRows(sector, rows);
  }

  Future<ScopeDataBundle> loadBundle(
    List<ScopeSectorConfig> sectors,
    DashboardFilter filter,
  ) async {
    if (!filter.isOperational) return const ScopeDataBundle();
    final db = await _dbHelper.db;
    final rowsByTable = <String, List<Map<String, Object?>>>{};
    final tableErrors = <String, String>{};
    for (final table
        in sectors.map((sector) => sector.tableName).nonNulls.toSet()) {
      try {
        final ageColumn = _ageColumnFor(table);
        final (:clause, :args) = _where(filter, bmkColumn: ageColumn);
        rowsByTable[table] = await db.rawQuery(
          'SELECT * FROM $table $clause ORDER BY date ASC, updatedAt ASC',
          args,
        );
      } catch (error) {
        rowsByTable[table] = const [];
        tableErrors[table] = error.toString();
      }
    }

    final leavesBySector = <String, List<ScopeLeafRow>>{};
    final periodsBySector = <String, List<ScopePeriod>>{};
    final observationsBySector = <String, List<MetricObservation>>{};
    final qualityBySector = <String, DashboardDataQuality>{};
    final errorsBySector = <String, String>{};

    for (final sector in sectors) {
      final table = sector.tableName;
      if (table == null) continue;
      final rows = rowsByTable[table] ?? const [];
      final error = tableErrors[table];
      if (error != null) errorsBySector[sector.id] = error;
      final leaves = _leavesFromRows(sector, rows);
      leavesBySector[sector.id] = leaves;
      periodsBySector[sector.id] = _periodsFromLeaves(leaves);
      final observations = _observationsFromRows(sector, rows);
      observationsBySector[sector.id] = observations;
      qualityBySector[sector.id] = _qualityFor(
        sector,
        rows,
        leaves,
        observations,
        error,
      );
    }
    return ScopeDataBundle(
      leavesBySector: leavesBySector,
      periodsBySector: periodsBySector,
      observationsBySector: observationsBySector,
      qualityBySector: qualityBySector,
      errorsBySector: errorsBySector,
    );
  }

  List<ScopeLeafRow> _leavesFromRows(
    ScopeSectorConfig sector,
    List<Map<String, Object?>> rows,
  ) {
    final table = sector.tableName;
    if (table == null) return const [];
    final def = PanelSampleSchema.byTable(table);
    final existing = <String>{
      ...def.hierarchyColumnNames,
      ...def.measurementColumns.map((d) => d.split(' ').first),
    };
    final nonPool = sector.allowedLayers
        .where((layer) => layer != SamplingLayer.pool)
        .toList();
    final hasTray = existing.contains('traySize');
    return rows.map((row) {
      final segments = <SamplingLayer, String>{};
      for (final layer in nonPool) {
        final seg = _segmentFor(layer, row);
        if (seg != null && seg.isNotEmpty) segments[layer] = seg;
      }
      final traySize = hasTray ? _asNum(row['traySize']) : null;
      final cells = <String, ScopeCellAccumulator>{};
      for (final p in sector.params) {
        if (p.format == ScopeValueFormat.text) {
          cells[p.column] = ScopeCellAccumulator.sample(
            text: row[p.column]?.toString(),
          );
        } else {
          final count = p.countColumn != null
              ? _asNum(row[p.countColumn])
              : null;
          final denominator = p.denominatorColumn != null
              ? _asNum(row[p.denominatorColumn])
              : traySize;
          cells[p.column] = ScopeCellAccumulator.sample(
            value: _asNum(row[p.column]),
            traySize: traySize,
            denominator: denominator,
            count: count,
          );
        }
      }
      final derived = PanelAggregateDeriver.derive(table, row);
      final flags = <String>{...derived.qualityFlags};
      for (final entry in derived.row.entries) {
        if (!row.containsKey(entry.key)) continue;
        if (_meaningfullyDifferent(row[entry.key], entry.value)) {
          flags.add('aggregate_drift');
          break;
        }
      }
      return ScopeLeafRow(
        rowId: row['id']?.toString(),
        sessionId: row['sessionId']?.toString(),
        sourceTable: table,
        customerId: row['customerId']?.toString(),
        hatcheryId: row['hatcheryId']?.toString(),
        flockId: row['flockId']?.toString(),
        observedAt: _date(row['date'] ?? row['updatedAt']),
        syncStatus: row['syncStatus']?.toString(),
        qualityFlags: flags,
        bmkAge: _asNum(
          row[_ageColumnFor(table)] ?? row['_scopeBmkAge'],
        )?.toInt(),
        layerSegments: segments,
        cells: cells,
      );
    }).toList();
  }

  List<ScopePeriod> _periodsFromLeaves(List<ScopeLeafRow> leaves) {
    final counts = <int, int>{};
    for (final leaf in leaves) {
      final age = leaf.bmkAge;
      if (age != null) counts[age] = (counts[age] ?? 0) + 1;
    }
    final ages = counts.keys.toList()..sort();
    return [
      for (final age in ages)
        ScopePeriod(label: 'W$age', age: age, n: counts[age] ?? 0),
    ];
  }

  List<MetricObservation> _observationsFromRows(
    ScopeSectorConfig sector,
    List<Map<String, Object?>> rows,
  ) {
    final table = sector.tableName;
    if (table == null) return const [];
    final leaves = _leavesFromRows(sector, rows);
    final out = <MetricObservation>[];
    for (var i = 0; i < rows.length && i < leaves.length; i++) {
      final row = rows[i];
      final leaf = leaves[i];
      final observedAt = leaf.observedAt;
      if (observedAt == null) continue;
      for (final param in sector.params) {
        final value = _asNum(row[param.column]);
        out.add(
          MetricObservation(
            tableName: table,
            rowId: leaf.rowId ?? '',
            sessionId: leaf.sessionId ?? '',
            customerId: leaf.customerId ?? '',
            hatcheryId: leaf.hatcheryId ?? '',
            flockId: leaf.flockId,
            sectorId: sector.id,
            metricKey: param.column,
            metricLabel: param.label,
            policy: param.aggregationPolicy,
            observedAt: observedAt,
            bmkAge: leaf.bmkAge,
            value: value,
            numerator: param.countColumn == null
                ? null
                : _asNum(row[param.countColumn]),
            denominator: param.denominatorColumn == null
                ? _asNum(row['traySize'])
                : _asNum(row[param.denominatorColumn]),
            sampleCount:
                _asNum(
                  param.denominatorColumn == null
                      ? row['traySize']
                      : row[param.denominatorColumn],
                )?.toInt() ??
                0,
            layerSegments: Map<Object, String>.from(leaf.layerSegments),
            qualityFlags: leaf.qualityFlags,
          ),
        );
      }
    }
    return out;
  }

  DashboardDataQuality _qualityFor(
    ScopeSectorConfig sector,
    List<Map<String, Object?>> rows,
    List<ScopeLeafRow> leaves,
    List<MetricObservation> observations,
    String? error,
  ) {
    DateTime? latest;
    var failed = 0;
    var pending = 0;
    final flags = <String>{};
    for (final leaf in leaves) {
      final at = leaf.observedAt;
      if (at != null && (latest == null || at.isAfter(latest))) latest = at;
      if (leaf.syncStatus == 'failed') failed++;
      if (leaf.syncStatus == 'pending') pending++;
      flags.addAll(leaf.qualityFlags);
    }
    final expected = leaves.length * sector.params.length;
    final missing = observations.where((item) => item.value == null).length;
    final sampleCount = observations
        .map((item) => item.sampleCount)
        .where((count) => count > 0)
        .fold<int>(0, (sum, count) => sum + count);
    final photoColumns = rows
        .expand((row) => row.keys)
        .where((key) => key.toLowerCase().contains('photo'))
        .toSet();
    final expectedPhotos = photoColumns.length * rows.length;
    final photoCount = rows.fold<int>(0, (count, row) {
      return count +
          photoColumns.where((column) {
            final value = row[column]?.toString().trim();
            return value != null &&
                value.isNotEmpty &&
                value != '[]' &&
                value != '{}';
          }).length;
    });
    return DashboardDataQuality(
      latestAt: latest,
      rowCount: leaves.length,
      sampleCount: sampleCount,
      ageCount: leaves.map((leaf) => leaf.bmkAge).nonNulls.toSet().length,
      missingMetricCount: missing,
      expectedMetricCount: expected,
      photoCount: photoCount,
      expectedPhotoCount: expectedPhotos,
      failedSyncCount: failed,
      pendingSyncCount: pending,
      qualityFlags: flags,
      error: error,
    );
  }

  bool _meaningfullyDifferent(Object? stored, Object? derived) {
    if (stored == null || derived == null) return stored != derived;
    final a = _asNum(stored);
    final b = _asNum(derived);
    if (a != null && b != null) return (a - b).abs() > 0.11;
    return stored.toString() != derived.toString();
  }

  DateTime? _date(Object? raw) =>
      raw == null ? null : DateTime.tryParse(raw.toString())?.toLocal();

  /// The most common bmkAgeWeeks present in the breakout data for this filter,
  /// used to pick a BMK reference for severity when no age is explicitly chosen.
  Future<int?> dominantBmkAge(DashboardFilter filter) async {
    final db = await _dbHelper.db;
    for (final table in const [
      'residue_breakout',
      'candled_egg_breakout',
      'fresh_egg_breakout',
    ]) {
      final (:clause, :args) = _where(filter, bmkColumn: 'bmkAgeWeeks');
      final rows = await db.rawQuery(
        'SELECT bmkAgeWeeks AS age, COUNT(*) AS c FROM $table $clause '
        'AND bmkAgeWeeks IS NOT NULL GROUP BY bmkAgeWeeks ORDER BY c DESC LIMIT 1',
        args,
      );
      if (rows.isNotEmpty) {
        final age = _asNum(rows.first['age']);
        if (age != null) return age.toInt();
      }
    }
    return null;
  }

  String? _segmentFor(SamplingLayer layer, Map<String, Object?> row) {
    if (layer == SamplingLayer.setterHatcher) {
      final s = row['setter']?.toString().trim() ?? '';
      final h = row['hatcher']?.toString().trim() ?? '';
      final combined = '$s$h';
      return combined.isEmpty ? null : combined;
    }
    final col = (_layerColumns[layer] ?? const ['']).first;
    return row[col]?.toString().trim();
  }

  num? _asNum(Object? raw) {
    if (raw == null) return null;
    if (raw is num) return raw;
    return num.tryParse(raw.toString());
  }

  ({String clause, List<Object?> args}) _where(
    DashboardFilter filter, {
    String? bmkColumn,
  }) {
    final parts = <String>['1 = 1'];
    final args = <Object?>[];
    if (filter.customerId != null) {
      parts.add('customerId = ?');
      args.add(filter.customerId);
    }
    if (filter.hatcheryId != null) {
      parts.add('hatcheryId = ?');
      args.add(filter.hatcheryId);
    }
    if (filter.flockId != null) {
      parts.add('flockId = ?');
      args.add(filter.flockId);
    }
    if (filter.bmkAge != null) {
      parts.add('${bmkColumn ?? 'flockAgeWeeks'} = ?');
      args.add(filter.bmkAge);
    }
    if (filter.sessionId != null) {
      parts.add('sessionId = ?');
      args.add(filter.sessionId);
    }
    return (clause: 'WHERE ${parts.join(' AND ')}', args: args);
  }

  // ── Cumulative-axis period listing ─────────────────────────────────────────

  /// The age column a sector groups its Cumulative-by-age view on (mirrors the
  /// per-table bmk-age column used in [getScopeLeaves]).
  static String _ageColumnFor(String table) => switch (table) {
    'fresh_egg_breakout' ||
    'candled_egg_breakout' ||
    'residue_breakout' => 'bmkAgeWeeks',
    'egg_quality' => 'eggBmkAgeWeeks',
    _ => 'flockAgeWeeks',
  };

  /// Distinct BMK ages for a sector, oldest→newest. Ignores any age/session
  /// narrowing on [base] so every station gets the same age-first selector.
  Future<List<ScopePeriod>> distinctPeriods(
    ScopeSectorConfig sector,
    DashboardFilter base,
  ) async {
    final table = sector.tableName;
    if (table == null) return const [];
    final db = await _dbHelper.db;
    final cf = DashboardFilter(
      customerId: base.customerId,
      hatcheryId: base.hatcheryId,
      flockId: base.flockId,
    );
    final ageCol = _ageColumnFor(table);
    final (:clause, :args) = _where(cf, bmkColumn: ageCol);
    final rows = await db.rawQuery(
      'SELECT $ageCol AS age, COUNT(*) AS n FROM $table $clause '
      'AND $ageCol IS NOT NULL GROUP BY $ageCol ORDER BY $ageCol ASC',
      args,
    );
    return [
      for (final row in rows)
        if (_asNum(row['age']) != null)
          ScopePeriod(
            label: 'W${_asNum(row['age'])!.toInt()}',
            age: _asNum(row['age'])!.toInt(),
            n: _asNum(row['n'])?.toInt() ?? 0,
          ),
    ];
  }
}
