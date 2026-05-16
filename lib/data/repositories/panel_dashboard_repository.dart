import 'dart:convert';

import '../../core/utils/calculation_utils.dart';
import '../../features/dashboard/models/chick_quality_models.dart';
import '../../features/dashboard/models/dashboard_filter.dart';
import '../../features/dashboard/models/egg_breakout_models.dart';
import '../../features/dashboard/models/egg_storage_models.dart';
import '../../features/dashboard/models/hatch_analysis_models.dart';
import '../database/database_helper.dart';
import '../models/panel_sample_schema.dart';

class PanelDashboardRepository {
  PanelDashboardRepository({DatabaseHelper? dbHelper})
    : _dbHelper = dbHelper ?? DatabaseHelper();

  final DatabaseHelper _dbHelper;

  Future<List<int>> getDistinctBmkAges({
    String? customerId,
    String? flockId,
  }) async {
    final db = await _dbHelper.db;
    final ages = <int>{};
    for (final table in const [
      'egg_quality',
      'chick_weights',
      'fresh_egg_breakout',
      'candled_egg_breakout',
      'residue_breakout',
    ]) {
      final bmkColumn = table == 'egg_quality'
          ? 'eggBmkAgeWeeks'
          : 'bmkAgeWeeks';
      final (:clause, :args) = _where(
        DashboardFilter(customerId: customerId, flockId: flockId),
        table,
        bmkColumn: bmkColumn,
      );
      final rows = await db.rawQuery(
        'SELECT DISTINCT $bmkColumn FROM $table $clause AND $bmkColumn IS NOT NULL',
        args,
      );
      ages.addAll(rows.map((row) => _asInt(row[bmkColumn])).nonNulls);
    }
    final sorted = ages.toList()..sort();
    return sorted;
  }

  Future<BmkReference?> getBmkReferenceForAge(int ageWeek) async {
    final db = await _dbHelper.db;
    final breedResult = await db.query(
      'bmk_breeds',
      where: 'ageWeek = ?',
      whereArgs: [ageWeek],
      limit: 1,
    );
    final breakoutResult = await db.query(
      'bmk_egg_breakout',
      where: 'ageWeek = ?',
      whereArgs: [ageWeek],
      limit: 1,
    );
    if (breedResult.isEmpty && breakoutResult.isEmpty) return null;
    return BmkReference.fromMaps(
      breedResult.isNotEmpty ? breedResult.first : null,
      breakoutResult.isNotEmpty ? breakoutResult.first : null,
    );
  }

  Future<List<String>> getDistinctSetterIds({
    String? customerId,
    String? flockId,
  }) async {
    final db = await _dbHelper.db;
    final filter = DashboardFilter(customerId: customerId, flockId: flockId);
    final (:clause, :args) = _where(filter, 'setter_optimizing');
    final rows = await db.rawQuery(
      'SELECT DISTINCT setterId FROM setter_optimizing $clause AND setterId IS NOT NULL ORDER BY setterId',
      args,
    );
    return rows.map((row) => row['setterId']?.toString()).nonNulls.toList();
  }

  Future<List<String>> getDistinctHatcherIds({
    String? customerId,
    String? flockId,
  }) async {
    final db = await _dbHelper.db;
    final filter = DashboardFilter(customerId: customerId, flockId: flockId);
    final (:clause, :args) = _where(filter, 'hatcher_optimizing');
    final rows = await db.rawQuery(
      'SELECT DISTINCT hatcherId FROM hatcher_optimizing $clause AND hatcherId IS NOT NULL ORDER BY hatcherId',
      args,
    );
    return rows.map((row) => row['hatcherId']?.toString()).nonNulls.toList();
  }

  Future<HatchAnalysisAvg?> getHatchAnalysisAvg(DashboardFilter filter) async {
    final db = await _dbHelper.db;
    final (:clause, :args) = _where(
      filter,
      'residue_breakout',
      bmkColumn: 'bmkAgeWeeks',
    );
    final rows = await db.rawQuery('''
      SELECT
        COUNT(hatchabilityPct) AS rowCount,
        AVG(hatchabilityPct) AS hatchabilityPct,
        AVG(fertilityPct) AS fertilityPct,
        AVG(hofPct) AS hofPct,
        AVG(culledPct) AS culledPct,
        AVG(deadPct) AS deadPct
      FROM residue_breakout
      $clause
      ''', args);
    if (rows.isEmpty || (rows.first['rowCount'] as int? ?? 0) == 0) {
      return null;
    }
    return HatchAnalysisAvg.fromMap(rows.first);
  }

  Future<List<HatchAnalysisTrend>?> getHatchAnalysisTrend(
    DashboardFilter filter,
  ) async {
    final db = await _dbHelper.db;
    final (:clause, :args) = _where(
      filter,
      'residue_breakout',
      bmkColumn: 'bmkAgeWeeks',
    );
    final rows = await db.rawQuery('''
      SELECT
        date,
        AVG(hatchabilityPct) AS hatchabilityPct,
        AVG(fertilityPct) AS fertilityPct,
        AVG(hofPct) AS hofPct,
        AVG(culledPct) AS culledPct,
        AVG(deadPct) AS deadPct
      FROM residue_breakout
      $clause
      GROUP BY date
      ORDER BY date ASC
      ''', args);
    if (rows.isEmpty) return null;
    return rows.map(HatchAnalysisTrend.fromMap).toList();
  }

  Future<EggBreakoutAvg?> getEggBreakoutAvg(
    DashboardFilter filter,
    String breakoutType,
  ) async {
    final table = _breakoutTable(breakoutType);
    final db = await _dbHelper.db;
    final (:clause, :args) = _where(filter, table, bmkColumn: 'bmkAgeWeeks');
    final rows = await db.rawQuery('''
      SELECT
        COUNT(traySize) AS rowCount,
        AVG(traySize) AS traySize,
        AVG(infertileCount) AS infertileCount,
        ${_avgFor(table, 'earlyDeadCount', fallback: 'early24hCount')} AS earlyDeadCount,
        ${_avgFor(table, 'midDeadCount', fallback: 'early48hCount')} AS midDeadCount,
        ${_avgFor(table, 'lateDeadCount', fallback: 'bloodRingCount')} AS lateDeadCount,
        0.0 AS internalPipCount,
        ${_avgFor(table, 'externalPipCount')} AS externalPipCount,
        ${_avgFor(table, 'crackedCount')} AS crackedCount,
        ${_avgFor(table, 'contaminatedCount')} AS contaminatedCount,
        0.0 AS malpositionCount,
        0.0 AS exposedBrainCount,
        0.0 AS crossedBeakCount,
        ${_avgFor(table, 'culledCount')} AS culledDeadCount,
        AVG(infertilePct) AS infertilePct,
        ${_avgFor(table, 'earlyDeadPct', fallback: 'early24hPct')} AS earlyDeadPct,
        ${_avgFor(table, 'midDeadPct', fallback: 'early48hPct')} AS midDeadPct,
        ${_avgFor(table, 'lateDeadPct', fallback: 'bloodRingPct')} AS lateDeadPct,
        0.0 AS internalPipPct,
        ${_avgFor(table, 'externalPipPct')} AS externalPipPct,
        ${_avgFor(table, 'crackedPct')} AS crackedPct,
        ${_avgFor(table, 'contaminatedPct')} AS contamPct,
        0.0 AS malpositionPct,
        0.0 AS exposedBrainPct,
        0.0 AS crossedBeakPct,
        ${_avgFor(table, 'culledPct')} AS cullPct
      FROM $table
      $clause
      ''', args);
    if (rows.isEmpty || (rows.first['rowCount'] as int? ?? 0) == 0) {
      return null;
    }
    return EggBreakoutAvg.fromMap(rows.first, breakoutType);
  }

  Future<List<EggBreakoutTrend>?> getEggBreakoutTrend(
    DashboardFilter filter,
    String breakoutType,
  ) async {
    final table = _breakoutTable(breakoutType);
    final db = await _dbHelper.db;
    final (:clause, :args) = _where(filter, table, bmkColumn: 'bmkAgeWeeks');
    final rows = await db.rawQuery('''
      SELECT
        date,
        AVG(infertilePct) AS infertilePct,
        ${_avgFor(table, 'earlyDeadPct', fallback: 'early24hPct')} AS earlyDeadPct,
        ${_avgFor(table, 'midDeadPct', fallback: 'early48hPct')} AS midDeadPct,
        ${_avgFor(table, 'lateDeadPct', fallback: 'bloodRingPct')} AS lateDeadPct,
        0.0 AS internalPipPct,
        ${_avgFor(table, 'externalPipPct')} AS externalPipPct,
        ${_avgFor(table, 'crackedPct')} AS crackedPct,
        ${_avgFor(table, 'contaminatedPct')} AS contamPct,
        0.0 AS malpositionPct,
        0.0 AS exposedBrainPct,
        0.0 AS crossedBeakPct,
        ${_avgFor(table, 'culledPct')} AS cullPct
      FROM $table
      $clause
      GROUP BY date
      ORDER BY date ASC
      ''', args);
    if (rows.isEmpty) return null;
    return rows
        .map((row) => EggBreakoutTrend.fromMap(row, breakoutType))
        .toList();
  }

  Future<List<String>> getPhotoPaths(
    DashboardFilter filter,
    String panelName,
    String fieldKey,
  ) async {
    final db = await _dbHelper.db;
    final parts = <String>['p.panelName = ?', 'p.fieldKey = ?'];
    final args = <Object?>[panelName, fieldKey];
    if (filter.customerId != null) {
      parts.add('s.customerId = ?');
      args.add(filter.customerId);
    }
    if (filter.flockId != null) {
      parts.add('s.flockId = ?');
      args.add(filter.flockId);
    }
    final rows = await db.rawQuery('''
      SELECT p.filePath
      FROM photos p
      LEFT JOIN audit_sessions s ON s.id = p.sessionId
      WHERE ${parts.join(' AND ')}
      ORDER BY p.createdAt DESC
      ''', args);
    return rows.map((row) => row['filePath']?.toString()).nonNulls.toList();
  }

  Future<List<String>> getEggStorageEstPhotoPaths(
    DashboardFilter filter,
  ) async {
    return getPhotoPaths(filter, 'egg_storage', 'shell_temp');
  }

  Future<EggStorageEstEvidence?> getLatestEggStorageEstEvidence(
    DashboardFilter filter,
  ) async {
    final db = await _dbHelper.db;
    final (:clause, :args) = _where(filter, 'egg_storage', tableAlias: 's');
    final rows = await db.rawQuery('''
      SELECT estReadingsJson
      FROM egg_storage s
      $clause
      ORDER BY date DESC, updatedAt DESC
      LIMIT 1
      ''', args);
    if (rows.isEmpty) return null;
    return EggStorageEstEvidence.fromJsonStrings(
      readingsJson: rows.first['estReadingsJson']?.toString(),
    );
  }

  Future<List<ChickWeightTrend>?> getChickWeightTrend(
    DashboardFilter filter,
  ) async {
    final db = await _dbHelper.db;
    final (:clause, :args) = _where(
      filter,
      'chick_weights',
      bmkColumn: 'bmkAgeWeeks',
    );
    final rows = await db.rawQuery('''
      SELECT date, weightsJson, avgWeight, uniformityPct, cvPct
      FROM chick_weights
      $clause
      ORDER BY date ASC, sampleIndex ASC, createdAt ASC
      ''', args);
    if (rows.isEmpty) return null;
    final weightsByDate = <String, List<double>>{};
    final summariesByDate = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      final date = row['date']?.toString();
      if (date == null || date.isEmpty) continue;
      final weights = _weightsFromJson(row['weightsJson']);
      if (weights.isNotEmpty) {
        weightsByDate.putIfAbsent(date, () => <double>[]).addAll(weights);
      } else {
        summariesByDate.putIfAbsent(date, () => []).add(row);
      }
    }
    final dates = {...weightsByDate.keys, ...summariesByDate.keys}.toList()
      ..sort();
    if (dates.isEmpty) return null;
    return [
      for (final date in dates)
        if ((weightsByDate[date] ?? const []).isNotEmpty)
          _chickWeightTrendFor(date, weightsByDate[date]!)
        else
          ChickWeightTrend(
            date: date,
            avgWeightG: _avg(summariesByDate[date]!, 'avgWeight'),
            uniformityPct: _avg(summariesByDate[date]!, 'uniformityPct'),
            cvPct: _avg(summariesByDate[date]!, 'cvPct'),
          ),
    ];
  }

  Future<PasgarAvg?> getPasgarAvg(DashboardFilter filter) async {
    final db = await _dbHelper.db;
    final (:clause, :args) = _where(filter, 'chick_pasgar');
    final rows = await db.rawQuery('''
      SELECT
        COUNT(finalScore) AS rowCount,
        AVG(finalScore) AS score,
        AVG(reflexesPct) AS reflexesPct,
        AVG(beakPct) AS beakPct,
        AVG(navelPct) AS navelPct,
        AVG(bellyPct) AS bellyPct,
        AVG(legPct) AS legPct,
        AVG(featherDevPct) AS featherDevPct
      FROM chick_pasgar
      $clause
      ''', args);
    if (rows.isEmpty || (rows.first['rowCount'] as int? ?? 0) == 0) {
      return null;
    }
    return PasgarAvg.fromMap(rows.first);
  }

  Future<CvtAvg?> getCvtAvg(DashboardFilter filter) async {
    final db = await _dbHelper.db;
    final (:clause, :args) = _where(filter, 'chick_cvt');
    final rows = await db.rawQuery('''
      SELECT COUNT(avgTemp) AS rowCount, AVG(avgTemp) AS avgTempF, AVG(cvPct) AS cvPct
      FROM chick_cvt
      $clause
      ''', args);
    if (rows.isEmpty || (rows.first['rowCount'] as int? ?? 0) == 0) {
      return null;
    }
    return CvtAvg.fromMap(rows.first);
  }

  Future<List<YfbmTrend>?> getYfbmTrend(DashboardFilter filter) async {
    final db = await _dbHelper.db;
    final (:clause, :args) = _where(filter, 'chick_yfbm');
    final rows = await db.rawQuery('''
      SELECT date, AVG(avgPct) AS avgPct, AVG(cvPct) AS cvPct
      FROM chick_yfbm
      $clause
      GROUP BY date
      ORDER BY date ASC
      ''', args);
    if (rows.isEmpty) return null;
    return rows.map(YfbmTrend.fromMap).toList();
  }

  Future<List<ChaEnvironmentalTrend>?> getChaEnvironmentalTrend(
    DashboardFilter filter,
  ) async {
    return null;
  }

  Future<List<EggStorageTrend>?> getEggStorageTrend(
    DashboardFilter filter,
  ) async {
    final db = await _dbHelper.db;
    final (:clause, :args) = _where(filter, 'egg_storage', tableAlias: 's');
    final rows = await db.rawQuery('''
      SELECT
        s.date,
        AVG(q.eggAvgWeight) AS avgWeightG,
        AVG(q.eggUniformityPct) AS uniformityPct,
        AVG(q.eggCvPct) AS cvPct,
        AVG(s.shellTemp) AS shellTempC,
        AVG(q.uvAffectedPct) AS uvAffectedPct,
        0.0 AS co2,
        AVG(s.estAvg) AS estAvgF,
        AVG(s.estCvPct) AS estCvPct
      FROM egg_storage s
      LEFT JOIN egg_quality q ON q.sessionId = s.sessionId AND q.sampleIndex = s.sampleIndex
      $clause
      GROUP BY s.date
      ORDER BY s.date ASC
      ''', args);
    if (rows.isEmpty) return null;
    return rows.map(EggStorageTrend.fromMap).toList();
  }

  Future<List<SetterComparison>?> getSetterComparisons(
    DashboardFilter filter,
    List<String> setterIds,
  ) async {
    if (setterIds.isEmpty) return [];
    final db = await _dbHelper.db;
    final (:clause, :args) = _where(filter, 'setter_optimizing');
    final placeholders = List.filled(setterIds.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT
        setterId,
        AVG(estAvg) AS estAvgF,
        AVG(estCvPct) AS estCvPct,
        AVG(turningAngle) AS turningAngle
      FROM setter_optimizing
      $clause AND setterId IN ($placeholders)
      GROUP BY setterId
      ''',
      [...args, ...setterIds],
    );
    if (rows.isEmpty) return [];
    return rows.map(SetterComparison.fromMap).toList();
  }

  Future<List<HatcherComparison>?> getHatcherComparisons(
    DashboardFilter filter,
    List<String> hatcherIds,
  ) async {
    if (hatcherIds.isEmpty) return [];
    final db = await _dbHelper.db;
    final (:clause, :args) = _where(filter, 'hatcher_optimizing');
    final placeholders = List.filled(hatcherIds.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT
        hatcherId,
        AVG(cvtAvg) AS cvtAvgF,
        AVG(cvtCvPct) AS cvtCvPct,
        MAX(meconium) AS meconium
      FROM hatcher_optimizing
      $clause AND hatcherId IN ($placeholders)
      GROUP BY hatcherId
      ''',
      [...args, ...hatcherIds],
    );
    if (rows.isEmpty) return [];
    return rows.map(HatcherComparison.fromMap).toList();
  }

  Future<Map<String, List<Map<String, dynamic>>>> getPanelRowsBySession(
    String sessionId,
  ) async {
    final db = await _dbHelper.db;
    final rowsByPanel = <String, List<Map<String, dynamic>>>{};
    for (final panel in PanelSampleSchema.panels) {
      final rows = await db.query(
        panel.tableName,
        where: 'sessionId = ?',
        whereArgs: [sessionId],
        orderBy: 'sampleIndex ASC, updatedAt ASC',
      );
      rowsByPanel[panel.tableName] = rows
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }
    return rowsByPanel;
  }

  ({String clause, List<Object?> args}) _where(
    DashboardFilter filter,
    String table, {
    String? bmkColumn,
    String? tableAlias,
  }) {
    final prefix = tableAlias == null ? '' : '$tableAlias.';
    final parts = <String>['1 = 1'];
    final args = <Object?>[];
    if (filter.customerId != null) {
      parts.add('${prefix}customerId = ?');
      args.add(filter.customerId);
    }
    if (filter.flockId != null) {
      parts.add('${prefix}flockId = ?');
      args.add(filter.flockId);
    }
    if (filter.bmkAge != null) {
      if (bmkColumn != null) {
        parts.add('$prefix$bmkColumn = ?');
      } else {
        parts.add('${prefix}flockAgeWeeks = ?');
      }
      args.add(filter.bmkAge);
    }
    return (clause: 'WHERE ${parts.join(' AND ')}', args: args);
  }

  String _breakoutTable(String breakoutType) {
    return switch (breakoutType) {
      'fresh' || 'freshEggBreakout' => 'fresh_egg_breakout',
      'candled' || 'candledEggBreakout' => 'candled_egg_breakout',
      _ => 'residue_breakout',
    };
  }

  String _avgFor(String table, String column, {String? fallback}) {
    final columns = PanelSampleSchema.byTable(table).measurementColumns
        .map((definition) => definition.split(' ').first)
        .toSet();
    if (columns.contains(column)) return 'AVG($column)';
    if (fallback != null && columns.contains(fallback)) return 'AVG($fallback)';
    return '0.0';
  }

  ChickWeightTrend _chickWeightTrendFor(String date, List<double> weights) {
    final avgWeight = CalculationUtils.average(weights);
    final minRange = avgWeight * 0.9;
    final maxRange = avgWeight * 1.1;
    return ChickWeightTrend(
      date: date,
      avgWeightG: avgWeight,
      uniformityPct: CalculationUtils.uniformityPercent(
        weights,
        minRange,
        maxRange,
      ),
      cvPct: CalculationUtils.cvPercent(weights),
    );
  }

  List<double> _weightsFromJson(Object? rawJson) {
    if (rawJson == null) return const [];
    try {
      final decoded = jsonDecode(rawJson.toString());
      if (decoded is List) {
        return decoded
            .map(_asDouble)
            .where((value) => value != null && value > 0)
            .cast<double>()
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  double _avg(List<Map<String, Object?>> rows, String column) {
    final values = rows.map((row) => _asDouble(row[column])).nonNulls.toList();
    if (values.isEmpty) return 0;
    return CalculationUtils.average(values);
  }

  double? _asDouble(Object? raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString());
  }

  int? _asInt(Object? raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    return int.tryParse(raw.toString());
  }
}
