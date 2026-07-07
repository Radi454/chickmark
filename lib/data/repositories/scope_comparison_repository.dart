import '../../features/dashboard/models/dashboard_filter.dart';
import '../../features/dashboard/models/scope_cumulative.dart';
import '../../features/dashboard/scope/scope_config.dart';
import '../../features/dashboard/scope/scope_models.dart';
import '../database/database_helper.dart';
import '../models/panel_sample_schema.dart';

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
          cells[p.column] = ScopeCellAccumulator.sample(
            value: _asNum(row[p.column]),
            traySize: traySize,
            count: count,
          );
        }
      }
      return ScopeLeafRow(
        bmkAge: _asNum(row['_scopeBmkAge'])?.toInt(),
        layerSegments: segments,
        cells: cells,
      );
    }).toList();
  }

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
