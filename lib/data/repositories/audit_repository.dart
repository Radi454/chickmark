import '../models/audit_model.dart';
import '../database/database_helper.dart';
import 'package:sqflite/sqflite.dart';
import '../../features/dashboard/models/dashboard_filter.dart';
import '../../features/dashboard/models/hatch_analysis_models.dart';
import '../../features/dashboard/models/egg_breakout_models.dart';
import '../../features/dashboard/models/chick_quality_models.dart';
import '../../features/dashboard/models/egg_storage_models.dart';

class AuditRepository {
  final dbHelper = DatabaseHelper();

  Future<void> insertAudit(AuditModel audit) async {
    final db = await dbHelper.db;
    await db.insert(
      'audits',
      audit.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateAudit(AuditModel audit) async {
    final db = await dbHelper.db;
    await db.update(
      'audits',
      audit.toMap(),
      where: 'id = ?',
      whereArgs: [audit.id],
    );
  }

  Future<List<AuditModel>> getAuditsByCustomer(String customerId) async {
    final db = await dbHelper.db;
    final result = await db.query(
      'audits',
      where: 'customerId = ?',
      whereArgs: [customerId],
      orderBy: 'date DESC, createdAt DESC',
    );
    return result.map((e) => AuditModel.fromMap(e)).toList();
  }

  Future<List<AuditModel>> getAllAudits() async {
    final db = await dbHelper.db;
    final result = await db.query(
      'audits',
      orderBy: 'date DESC, createdAt DESC',
    );
    return result.map((e) => AuditModel.fromMap(e)).toList();
  }

  Future<AuditModel?> getAuditById(String id) async {
    final db = await dbHelper.db;
    final result = await db.query('audits', where: 'id = ?', whereArgs: [id]);
    if (result.isNotEmpty) {
      return AuditModel.fromMap(result.first);
    }
    return null;
  }

  Future<List<AuditModel>> getAuditsByType(String auditType) async {
    final db = await dbHelper.db;
    final result = await db.query(
      'audits',
      where: 'auditType = ?',
      whereArgs: [auditType],
    );
    return result.map((e) => AuditModel.fromMap(e)).toList();
  }

  Future<List<AuditModel>> getAuditsBySession(
    String customerId,
    String flockId,
    String date,
    String auditType,
  ) async {
    final db = await dbHelper.db;
    final result = await db.query(
      'audits',
      where: 'customerId = ? AND flockId = ? AND date = ? AND auditType = ?',
      whereArgs: [customerId, flockId, date, auditType],
      orderBy: 'hatchNumber ASC',
    );
    return result.map((e) => AuditModel.fromMap(e)).toList();
  }

  Future<List<int>> getDistinctBmkAges({
    String? customerId,
    String? flockId,
  }) async {
    final db = await dbHelper.db;
    final filters = <String>[];
    final args = <Object?>[];
    if (customerId != null) {
      filters.add('customerId = ?');
      args.add(customerId);
    }
    if (flockId != null) {
      filters.add('flockId = ?');
      args.add(flockId);
    }
    final filterSql = filters.isEmpty ? '' : '${filters.join(' AND ')} AND ';
    final result = await db.rawQuery('''
      SELECT DISTINCT COALESCE(
        haBmkAge,
        ebBmkAge,
        chickBmkAge,
        esEggBmkAge,
        soIncubationAge,
        hoIncubationAge
      ) AS bmkAge
      FROM audits
      WHERE $filterSql COALESCE(
        haBmkAge,
        ebBmkAge,
        chickBmkAge,
        esEggBmkAge,
        soIncubationAge,
        hoIncubationAge
      ) IS NOT NULL
      ORDER BY bmkAge ASC
      ''', args);
    return result.map((r) => r['bmkAge'] as int).toList();
  }

  Future<BmkReference?> getBmkReferenceForAge(int ageWeek) async {
    final db = await dbHelper.db;
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
    final db = await dbHelper.db;
    final filters = <String>[
      "auditType = 'Setter Optimizing'",
      'COALESCE(soSetterId, setterId) IS NOT NULL',
    ];
    final args = <Object?>[];
    if (customerId != null) {
      filters.add('customerId = ?');
      args.add(customerId);
    }
    if (flockId != null) {
      filters.add('flockId = ?');
      args.add(flockId);
    }
    final result = await db.rawQuery(
      'SELECT DISTINCT COALESCE(soSetterId, setterId) AS setterId FROM audits WHERE ${filters.join(' AND ')} ORDER BY setterId',
      args,
    );
    return result.map((r) => r['setterId'] as String).toList();
  }

  Future<List<String>> getDistinctHatcherIds({
    String? customerId,
    String? flockId,
  }) async {
    final db = await dbHelper.db;
    final filters = <String>[
      "auditType = 'Hatcher Optimizing'",
      'COALESCE(hoHatcherId, hatcherId) IS NOT NULL',
    ];
    final args = <Object?>[];
    if (customerId != null) {
      filters.add('customerId = ?');
      args.add(customerId);
    }
    if (flockId != null) {
      filters.add('flockId = ?');
      args.add(flockId);
    }
    final result = await db.rawQuery(
      'SELECT DISTINCT COALESCE(hoHatcherId, hatcherId) AS hatcherId FROM audits WHERE ${filters.join(' AND ')} ORDER BY hatcherId',
      args,
    );
    return result.map((r) => r['hatcherId'] as String).toList();
  }

  Future<HatchAnalysisAvg?> getHatchAnalysisAvg(DashboardFilter filter) async {
    final db = await dbHelper.db;
    final where = _buildWhere(filter, 'hatch_analysis');
    if (where.isEmpty) return null;
    final result = await db.rawQuery(
      'SELECT AVG(haHatchability) as hatchabilityPct, AVG(haFertility) as fertilityPct, AVG(haHof) as hofPct, AVG(haCulled) as culledPct, AVG(haDead) as deadPct FROM audits $where',
    );
    if (result.isEmpty) return null;
    return HatchAnalysisAvg.fromMap(result.first);
  }

  Future<List<HatchAnalysisTrend>?> getHatchAnalysisTrend(
    DashboardFilter filter,
  ) async {
    final db = await dbHelper.db;
    final where = _buildWhere(filter, 'hatch_analysis');
    if (where.isEmpty) return null;
    final result = await db.rawQuery(
      'SELECT date, AVG(haHatchability) as hatchabilityPct, AVG(haFertility) as fertilityPct, AVG(haHof) as hofPct, AVG(haCulled) as culledPct, AVG(haDead) as deadPct FROM audits $where GROUP BY date ORDER BY date ASC',
    );
    if (result.isEmpty) return null;
    return result.map((r) => HatchAnalysisTrend.fromMap(r)).toList();
  }

  Future<EggBreakoutAvg?> getEggBreakoutAvg(
    DashboardFilter filter,
    String breakoutType,
  ) async {
    final db = await dbHelper.db;
    final where = _buildWhere(filter, 'hatch_analysis');
    if (where.isEmpty) return null;
    final typeClause = _eggBreakoutTypeClause(breakoutType);
    final result = await db.rawQuery('''
      SELECT
        COUNT(ebInfertileCount) as rowCount,
        AVG(ebTraySize) as traySize,
        AVG(ebInfertileCount) as infertileCount,
        AVG(ebEarlyDeadCount) as earlyDeadCount,
        AVG(ebMidDeadCount) as midDeadCount,
        AVG(ebLateDeadCount) as lateDeadCount,
        AVG(ebInternalPipCount) as internalPipCount,
        AVG(ebExternalPipCount) as externalPipCount,
        AVG(ebCrackedCount) as crackedCount,
        AVG(ebContaminatedCount) as contaminatedCount,
        AVG(ebMalpositionCount) as malpositionCount,
        AVG(ebExposedBrainCount) as exposedBrainCount,
        AVG(ebCrossedBeakCount) as crossedBeakCount,
        AVG(ebCulledDeadCount) as culledDeadCount,
        AVG(CASE WHEN ebTraySize > 0 THEN ebInfertileCount * 100.0 / ebTraySize END) as infertilePct,
        AVG(CASE WHEN ebTraySize > 0 THEN ebEarlyDeadCount * 100.0 / ebTraySize END) as earlyDeadPct,
        AVG(CASE WHEN ebTraySize > 0 THEN ebMidDeadCount * 100.0 / ebTraySize END) as midDeadPct,
        AVG(CASE WHEN ebTraySize > 0 THEN ebLateDeadCount * 100.0 / ebTraySize END) as lateDeadPct,
        AVG(CASE WHEN ebTraySize > 0 THEN ebInternalPipCount * 100.0 / ebTraySize END) as internalPipPct,
        AVG(CASE WHEN ebTraySize > 0 THEN ebExternalPipCount * 100.0 / ebTraySize END) as externalPipPct,
        AVG(CASE WHEN ebTraySize > 0 THEN ebCrackedCount * 100.0 / ebTraySize END) as crackedPct,
        AVG(CASE WHEN ebTraySize > 0 THEN ebContaminatedCount * 100.0 / ebTraySize END) as contamPct,
        AVG(CASE WHEN ebTraySize > 0 THEN ebMalpositionCount * 100.0 / ebTraySize END) as malpositionPct,
        AVG(CASE WHEN ebTraySize > 0 THEN ebExposedBrainCount * 100.0 / ebTraySize END) as exposedBrainPct,
        AVG(CASE WHEN ebTraySize > 0 THEN ebCrossedBeakCount * 100.0 / ebTraySize END) as crossedBeakPct,
        AVG(CASE WHEN ebTraySize > 0 THEN ebCulledDeadCount * 100.0 / ebTraySize END) as cullPct
      FROM audits
      $where
        AND ebTraySize IS NOT NULL
        $typeClause
      ''');
    if (result.isEmpty) return null;
    if ((result.first['rowCount'] as int? ?? 0) == 0) return null;
    return EggBreakoutAvg.fromMap(result.first, breakoutType);
  }

  Future<List<EggBreakoutTrend>?> getEggBreakoutTrend(
    DashboardFilter filter,
    String breakoutType,
  ) async {
    final db = await dbHelper.db;
    final where = _buildWhere(filter, 'hatch_analysis');
    if (where.isEmpty) return null;
    final typeClause = _eggBreakoutTypeClause(breakoutType);
    final result = await db.rawQuery('''
      SELECT
        date,
        AVG(CASE WHEN ebTraySize > 0 THEN ebInfertileCount * 100.0 / ebTraySize END) as infertilePct,
        AVG(CASE WHEN ebTraySize > 0 THEN ebEarlyDeadCount * 100.0 / ebTraySize END) as earlyDeadPct,
        AVG(CASE WHEN ebTraySize > 0 THEN ebMidDeadCount * 100.0 / ebTraySize END) as midDeadPct,
        AVG(CASE WHEN ebTraySize > 0 THEN ebLateDeadCount * 100.0 / ebTraySize END) as lateDeadPct,
        AVG(CASE WHEN ebTraySize > 0 THEN ebInternalPipCount * 100.0 / ebTraySize END) as internalPipPct,
        AVG(CASE WHEN ebTraySize > 0 THEN ebExternalPipCount * 100.0 / ebTraySize END) as externalPipPct,
        AVG(CASE WHEN ebTraySize > 0 THEN ebCrackedCount * 100.0 / ebTraySize END) as crackedPct,
        AVG(CASE WHEN ebTraySize > 0 THEN ebContaminatedCount * 100.0 / ebTraySize END) as contamPct,
        AVG(CASE WHEN ebTraySize > 0 THEN ebMalpositionCount * 100.0 / ebTraySize END) as malpositionPct,
        AVG(CASE WHEN ebTraySize > 0 THEN ebExposedBrainCount * 100.0 / ebTraySize END) as exposedBrainPct,
        AVG(CASE WHEN ebTraySize > 0 THEN ebCrossedBeakCount * 100.0 / ebTraySize END) as crossedBeakPct,
        AVG(CASE WHEN ebTraySize > 0 THEN ebCulledDeadCount * 100.0 / ebTraySize END) as cullPct
      FROM audits
      $where
        AND ebTraySize IS NOT NULL
        $typeClause
      GROUP BY date
      ORDER BY date ASC
      ''');
    if (result.isEmpty) return null;
    return result
        .map((r) => EggBreakoutTrend.fromMap(r, breakoutType))
        .toList();
  }

  Future<List<String>> getPhotoPaths(
    DashboardFilter filter,
    String auditType,
    String description,
  ) async {
    final db = await dbHelper.db;
    final where = _buildWhere(filter, auditType);
    if (where.isEmpty) return [];
    final result = await db.rawQuery(
      'SELECT p.filePath FROM photos p INNER JOIN audits a ON p.auditId = a.id $where AND p.description = ? ORDER BY p.createdAt DESC',
      [description],
    );
    return result.map((r) => r['filePath'] as String).toList();
  }

  Future<ChickWeightTrend?> getChickWeightTrend(DashboardFilter filter) async {
    final db = await dbHelper.db;
    final where = _buildWhere(filter, 'chick_quality');
    if (where.isEmpty) return null;
    final result = await db.rawQuery(
      'SELECT date, AVG(chickAvgWeight) as avgWeightG, AVG(chickUniformityPct) as uniformityPct, AVG(chickCvPct) as cvPct FROM audits $where GROUP BY date ORDER BY date ASC',
    );
    if (result.isEmpty) return null;
    return ChickWeightTrend.fromMap(result.last);
  }

  Future<PasgarAvg?> getPasgarAvg(DashboardFilter filter) async {
    final db = await dbHelper.db;
    final where = _buildWhere(filter, 'chick_quality');
    if (where.isEmpty) return null;
    final result = await db.rawQuery(
      'SELECT AVG(pasgarFinalScore) as score, AVG(pasgarReflexes) as reflexesPct, AVG(pasgarBeak) as beakPct, AVG(pasgarNavel) as navelPct, AVG(pasgarBelly) as bellyPct, AVG(pasgarLeg) as legPct, AVG(pasgarFeatherDev) as featherDevPct FROM audits $where',
    );
    if (result.isEmpty) return null;
    return PasgarAvg.fromMap(result.first);
  }

  Future<CvtAvg?> getCvtAvg(DashboardFilter filter) async {
    final db = await dbHelper.db;
    final where = _buildWhere(filter, 'chick_quality');
    if (where.isEmpty) return null;
    final result = await db.rawQuery(
      'SELECT AVG(cvtAvg) as avgTempF, AVG(cvtCvPct) as cvPct FROM audits $where',
    );
    if (result.isEmpty) return null;
    return CvtAvg.fromMap(result.first);
  }

  Future<List<YfbmTrend>?> getYfbmTrend(DashboardFilter filter) async {
    final db = await dbHelper.db;
    final where = _buildWhere(filter, 'chick_quality');
    if (where.isEmpty) return null;
    final result = await db.rawQuery(
      'SELECT date, AVG(yfbmAvgPct) as avgPct, AVG(yfbmCvPct) as cvPct FROM audits $where GROUP BY date ORDER BY date ASC',
    );
    if (result.isEmpty) return null;
    return result.map((r) => YfbmTrend.fromMap(r)).toList();
  }

  Future<List<ChaEnvironmentalTrend>?> getChaEnvironmentalTrend(
    DashboardFilter filter,
  ) async {
    final db = await dbHelper.db;
    final where = _buildWhere(filter, 'chick_quality');
    if (where.isEmpty) return null;
    final result = await db.rawQuery(
      'SELECT date, AVG(chaCo2) as co2, AVG(chaPm10) as pm10, AVG(chaPm25) as pm25, AVG((COALESCE(chaAirVelocitySpot1, 0) + COALESCE(chaAirVelocitySpot2, 0) + COALESCE(chaAirVelocitySpot3, 0)) / NULLIF((chaAirVelocitySpot1 IS NOT NULL) + (chaAirVelocitySpot2 IS NOT NULL) + (chaAirVelocitySpot3 IS NOT NULL), 0)) as airVelocity, AVG(chaNoiseLevel) as noiseLevel FROM audits $where GROUP BY date ORDER BY date ASC',
    );
    if (result.isEmpty) return null;
    return result.map((r) => ChaEnvironmentalTrend.fromMap(r)).toList();
  }

  Future<EggStorageTrend?> getEggStorageTrend(DashboardFilter filter) async {
    final db = await dbHelper.db;
    final where = _buildWhere(filter, 'egg_storage');
    if (where.isEmpty) return null;
    final result = await db.rawQuery(
      'SELECT date, AVG(esEggAvgWeight) as avgWeightG, AVG(esEggUniformityPct) as uniformityPct, AVG(esEggCvPct) as cvPct, AVG(esShellTemp) as shellTempC, AVG(esEggSampleSize) as uvAffectedPct FROM audits $where GROUP BY date ORDER BY date ASC',
    );
    if (result.isEmpty) return null;
    return EggStorageTrend.fromMap(result.last);
  }

  Future<List<SetterComparison>?> getSetterComparisons(
    DashboardFilter filter,
    List<String> setterIds,
  ) async {
    if (setterIds.isEmpty) return [];
    final db = await dbHelper.db;
    final ids = setterIds.map((s) => "'$s'").join(',');
    final where = _buildWhere(filter, 'setter_optimizing');
    if (where.isEmpty) return [];
    final result = await db.rawQuery(
      'SELECT soSetterId as setterId, NULL as hatchabilityPct, NULL as fertilityPct, NULL as hofPct, NULL as culledPct, NULL as deadPct, AVG(soEstAvg) as estAvgF, AVG(soEstCv) as estCvPct FROM audits $where AND soSetterId IN ($ids) GROUP BY soSetterId',
    );
    if (result.isEmpty) return [];
    return result.map((r) => SetterComparison.fromMap(r)).toList();
  }

  Future<List<HatcherComparison>?> getHatcherComparisons(
    DashboardFilter filter,
    List<String> hatcherIds,
  ) async {
    if (hatcherIds.isEmpty) return [];
    final db = await dbHelper.db;
    final ids = hatcherIds.map((s) => "'$s'").join(',');
    final where = _buildWhere(filter, 'hatcher_optimizing');
    if (where.isEmpty) return [];
    final result = await db.rawQuery(
      'SELECT hoHatcherId as hatcherId, NULL as hatchabilityPct, NULL as fertilityPct, NULL as hofPct, NULL as culledPct, NULL as deadPct, AVG(hoCvtAvg) as cvtAvgF, AVG(hoCvtCv) as cvtCvPct FROM audits $where AND hoHatcherId IN ($ids) GROUP BY hoHatcherId',
    );
    if (result.isEmpty) return [];
    return result.map((r) => HatcherComparison.fromMap(r)).toList();
  }

  String _buildWhere(DashboardFilter filter, String auditType) {
    final parts = <String>["auditType = '${_displayAuditType(auditType)}'"];
    if (filter.customerId != null) {
      parts.add("customerId = '${filter.customerId}'");
    }
    if (filter.flockId != null &&
        auditType != 'setter_optimizing' &&
        auditType != 'hatcher_optimizing') {
      parts.add("flockId = '${filter.flockId}'");
    }
    if (filter.bmkAge != null) {
      parts.add(
        'COALESCE(haBmkAge, ebBmkAge, chickBmkAge, esEggBmkAge, soIncubationAge, hoIncubationAge) = ${filter.bmkAge}',
      );
    }
    return 'WHERE ${parts.join(' AND ')}';
  }

  Future<void> upsertAudit(Map<String, dynamic> row) async {
    final db = await dbHelper.db;
    final columns = await _tableColumns(db, 'audits');
    final normalized = _filterColumns(_normalizeAuditRow(row), columns);
    await db.insert(
      'audits',
      normalized,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Set<String>> _tableColumns(Database db, String table) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.map((row) => row['name'] as String).toSet();
  }

  Map<String, dynamic> _filterColumns(
    Map<String, dynamic> row,
    Set<String> columns,
  ) {
    return Map.fromEntries(
      row.entries.where((entry) {
        return columns.contains(entry.key);
      }),
    );
  }

  Map<String, dynamic> _normalizeAuditRow(Map<String, dynamic> row) {
    final normalized = <String, dynamic>{};
    for (final entry in row.entries) {
      normalized[_camelize(entry.key)] = entry.value;
    }

    final auditType = normalized['auditType'];
    if (auditType is String) {
      normalized['auditType'] = _displayAuditType(auditType);
    }

    _copyAlias(normalized, from: 'haHatchabilityPct', to: 'haHatchability');
    _copyAlias(normalized, from: 'haFertilityPct', to: 'haFertility');
    _copyAlias(normalized, from: 'haHofPct', to: 'haHof');
    _copyAlias(normalized, from: 'soEstCvPct', to: 'soEstCv');
    _copyAlias(normalized, from: 'hoCvtCvPct', to: 'hoCvtCv');
    return normalized;
  }

  String _eggBreakoutTypeClause(String breakoutType) {
    final type = switch (breakoutType) {
      'residue' => 'Hatch Residue',
      'fresh' => 'Fresh Egg',
      'candled' => 'Candled Egg',
      _ => breakoutType,
    };
    return "AND ebBreakoutType = '$type'";
  }

  void _copyAlias(
    Map<String, dynamic> row, {
    required String from,
    required String to,
  }) {
    if (!row.containsKey(to) && row.containsKey(from)) {
      row[to] = row[from];
    }
  }

  String _camelize(String key) {
    if (!key.contains('_')) return key;
    final parts = key.split('_');
    return parts.first +
        parts.skip(1).map((part) {
          if (part.isEmpty) return part;
          return part[0].toUpperCase() + part.substring(1);
        }).join();
  }

  String _displayAuditType(String auditType) {
    switch (auditType) {
      case 'chick_quality':
        return 'Chick Quality';
      case 'hatch_analysis':
        return 'Hatch Analysis';
      case 'egg_storage':
        return 'Egg Storage';
      case 'setter_optimizing':
        return 'Setter Optimizing';
      case 'hatcher_optimizing':
        return 'Hatcher Optimizing';
      default:
        return auditType;
    }
  }
}
