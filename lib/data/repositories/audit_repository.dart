import '../models/audit_model.dart';
import '../database/database_helper.dart';
import 'package:sqflite/sqflite.dart';
import '../../features/dashboard/models/dashboard_filter.dart';
import '../../features/dashboard/models/hatch_analysis_models.dart';
import '../../features/dashboard/models/egg_breakout_models.dart';
import '../../features/dashboard/models/chick_quality_models.dart';
import '../../features/dashboard/models/egg_storage_models.dart';
import '../../features/audits/models/audit_filter.dart';

class AuditRepository {
  final dbHelper = DatabaseHelper();

  Future<void> insertAudit(AuditModel audit) async {
    await dbHelper.assertForeignKeys(
      customerId: audit.customerId,
      flockId: audit.flockId,
    );
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

  Future<void> deleteAudit(String id) async {
    final db = await dbHelper.db;
    await db.transaction((txn) async {
      await txn.delete('photos', where: 'auditId = ?', whereArgs: [id]);
      await txn.delete('audits', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> deleteAuditsByCustomer(String customerId) async {
    final db = await dbHelper.db;
    await db.transaction((txn) async {
      await txn.delete(
        'photos',
        where: 'auditId IN (SELECT id FROM audits WHERE customerId = ?)',
        whereArgs: [customerId],
      );
      await txn.delete(
        'audits',
        where: 'customerId = ?',
        whereArgs: [customerId],
      );
    });
  }

  Future<List<AuditModel>> getAuditsByCustomer(
    String customerId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await dbHelper.db;
    final result = await db.query(
      'audits',
      where: 'customerId = ?',
      whereArgs: [customerId],
      orderBy: 'date DESC, createdAt DESC',
      limit: limit,
      offset: offset,
    );
    return result.map((e) => AuditModel.fromMap(e)).toList();
  }

  Future<List<AuditModel>> getAllAudits({
    int limit = 50,
    int offset = 0,
    String? customerId,
  }) async {
    final db = await dbHelper.db;
    final result = await db.query(
      'audits',
      where: customerId == null ? null : 'customerId = ?',
      whereArgs: customerId == null ? null : [customerId],
      orderBy: 'date DESC, createdAt DESC',
      limit: limit,
      offset: offset,
    );
    return result.map((e) => AuditModel.fromMap(e)).toList();
  }

  Future<List<AuditModel>> getFilteredAudits(
    AuditFilter filter, {
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await dbHelper.db;
    final parts = <String>[];
    final args = <Object?>[];

    if (filter.dateFrom != null) {
      parts.add('date >= ?');
      args.add(_dateOnly(filter.dateFrom!));
    }
    if (filter.dateTo != null) {
      parts.add('date <= ?');
      args.add(_dateOnly(filter.dateTo!));
    }
    if (filter.auditTypes.isNotEmpty) {
      final placeholders = List.filled(filter.auditTypes.length, '?').join(',');
      parts.add('auditType IN ($placeholders)');
      args.addAll(filter.auditTypes);
    }
    if (filter.customerId != null) {
      parts.add('customerId = ?');
      args.add(filter.customerId);
    }
    if (filter.flockId != null) {
      parts.add('flockId = ?');
      args.add(filter.flockId);
    }
    if (filter.status != null) {
      parts.add('status = ?');
      args.add(filter.status);
    }

    final result = await db.query(
      'audits',
      where: parts.isEmpty ? null : parts.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'date DESC, createdAt DESC',
      limit: limit,
      offset: offset,
    );
    return result.map(AuditModel.fromMap).toList();
  }

  Future<List<AuditModel>> getAuditsSince(
    String date, {
    String? customerId,
  }) async {
    final db = await dbHelper.db;
    final whereParts = <String>['date >= ?'];
    final args = <Object?>[date];
    if (customerId != null) {
      whereParts.add('customerId = ?');
      args.add(customerId);
    }
    final result = await db.query(
      'audits',
      where: whereParts.join(' AND '),
      whereArgs: args,
      orderBy: 'date DESC, createdAt DESC',
    );
    return result.map((e) => AuditModel.fromMap(e)).toList();
  }

  Future<List<AuditModel>> getRecentAudits({
    int limit = 5,
    String? customerId,
  }) async {
    final db = await dbHelper.db;
    final result = await db.query(
      'audits',
      where: customerId == null ? null : 'customerId = ?',
      whereArgs: customerId == null ? null : [customerId],
      orderBy: 'date DESC, createdAt DESC',
      limit: limit,
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

  Future<Map<String, dynamic>?> getAuditRowById(String id) async {
    final db = await dbHelper.db;
    final result = await db.query('audits', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return result.first;
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

  Future<List<AuditModel>> getAuditsBySessionId(String sessionId) async {
    final db = await dbHelper.db;
    final result = await db.query(
      'audits',
      where: 'sessionId = ?',
      whereArgs: [sessionId],
      orderBy: 'auditType ASC, hatchNumber ASC',
    );
    return result.map((e) => AuditModel.fromMap(e)).toList();
  }

  Future<int> getAuditCountBySessionId(String sessionId) async {
    final db = await dbHelper.db;
    final result = await db.query(
      'audits',
      columns: ['COUNT(*) as cnt'],
      where: 'sessionId = ?',
      whereArgs: [sessionId],
    );
    return (result.first['cnt'] as int? ?? 0);
  }

  Future<void> linkAuditToSession(
    String auditId,
    String sessionId,
  ) async {
    final db = await dbHelper.db;
    await db.update(
      'audits',
      {'sessionId': sessionId},
      where: 'id = ?',
      whereArgs: [auditId],
    );
  }

  Future<void> unlinkAuditsFromSession(String sessionId) async {
    final db = await dbHelper.db;
    await db.update(
      'audits',
      {'sessionId': null},
      where: 'sessionId = ?',
      whereArgs: [sessionId],
    );
  }

  Future<List<AuditModel>> getAuditsBySession(
    String customerId,
    String flockId,
    String date,
    String auditType,
  ) async {
    final db = await dbHelper.db;
    final flockPredicate = flockId.isEmpty
        ? '(flockId IS NULL OR flockId = ?)'
        : 'flockId = ?';
    final result = await db.query(
      'audits',
      where:
          'customerId = ? AND $flockPredicate AND date = ? AND auditType = ?',
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
    final (:clause, :args) = _buildWhereWithArgs(filter, 'hatch_analysis');
    final result = await db.rawQuery(
      'SELECT AVG(haHatchability) as hatchabilityPct, AVG(haFertility) as fertilityPct, AVG(haHof) as hofPct, AVG(haCulled) as culledPct, AVG(haDead) as deadPct FROM audits $clause',
      args,
    );
    if (result.isEmpty) return null;
    return HatchAnalysisAvg.fromMap(result.first);
  }

  Future<List<HatchAnalysisTrend>?> getHatchAnalysisTrend(
    DashboardFilter filter,
  ) async {
    final db = await dbHelper.db;
    final (:clause, :args) = _buildWhereWithArgs(filter, 'hatch_analysis');
    final result = await db.rawQuery(
      'SELECT date, AVG(haHatchability) as hatchabilityPct, AVG(haFertility) as fertilityPct, AVG(haHof) as hofPct, AVG(haCulled) as culledPct, AVG(haDead) as deadPct FROM audits $clause GROUP BY date ORDER BY date ASC',
      args,
    );
    if (result.isEmpty) return null;
    return result.map((r) => HatchAnalysisTrend.fromMap(r)).toList();
  }

  Future<EggBreakoutAvg?> getEggBreakoutAvg(
    DashboardFilter filter,
    String breakoutType,
  ) async {
    final db = await dbHelper.db;
    final (:clause, :args) = _buildWhereWithArgs(filter, 'hatch_analysis');
    final typeFilter = _eggBreakoutTypeArg(breakoutType);
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
      $clause
        AND ebTraySize IS NOT NULL
        ${typeFilter.clause}
      ''', [...args, typeFilter.arg]);
    if (result.isEmpty) return null;
    if ((result.first['rowCount'] as int? ?? 0) == 0) return null;
    return EggBreakoutAvg.fromMap(result.first, breakoutType);
  }

  Future<List<EggBreakoutTrend>?> getEggBreakoutTrend(
    DashboardFilter filter,
    String breakoutType,
  ) async {
    final db = await dbHelper.db;
    final (:clause, :args) = _buildWhereWithArgs(filter, 'hatch_analysis');
    final typeFilter = _eggBreakoutTypeArg(breakoutType);
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
      $clause
        AND ebTraySize IS NOT NULL
        ${typeFilter.clause}
      GROUP BY date
      ORDER BY date ASC
      ''', [...args, typeFilter.arg]);
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
    final (:clause, :args) = _buildWhereWithArgs(
      filter,
      auditType,
      tableAlias: 'a',
    );
    final result = await db.rawQuery(
      'SELECT p.filePath FROM photos p INNER JOIN audits a ON p.auditId = a.id $clause AND p.description = ? ORDER BY p.createdAt DESC',
      [...args, description],
    );
    return result.map((r) => r['filePath'] as String).toList();
  }

  Future<List<ChickWeightTrend>?> getChickWeightTrend(DashboardFilter filter) async {
    final db = await dbHelper.db;
    final (:clause, :args) = _buildWhereWithArgs(filter, 'chick_quality');
    final result = await db.rawQuery(
      'SELECT date, AVG(chickAvgWeight) as avgWeightG, AVG(chickUniformityPct) as uniformityPct, AVG(chickCvPct) as cvPct FROM audits $clause GROUP BY date ORDER BY date ASC',
      args,
    );
    if (result.isEmpty) return null;
    return result.map((r) => ChickWeightTrend.fromMap(r)).toList();
  }

  Future<PasgarAvg?> getPasgarAvg(DashboardFilter filter) async {
    final db = await dbHelper.db;
    final (:clause, :args) = _buildWhereWithArgs(filter, 'chick_quality');
    final result = await db.rawQuery(
      'SELECT AVG(pasgarFinalScore) as score, AVG(pasgarReflexes) as reflexesPct, AVG(pasgarBeak) as beakPct, AVG(pasgarNavel) as navelPct, AVG(pasgarBelly) as bellyPct, AVG(pasgarLeg) as legPct, AVG(pasgarFeatherDev) as featherDevPct FROM audits $clause',
      args,
    );
    if (result.isEmpty) return null;
    return PasgarAvg.fromMap(result.first);
  }

  Future<CvtAvg?> getCvtAvg(DashboardFilter filter) async {
    final db = await dbHelper.db;
    final (:clause, :args) = _buildWhereWithArgs(filter, 'chick_quality');
    final result = await db.rawQuery(
      'SELECT AVG(cvtAvg) as avgTempF, AVG(cvtCvPct) as cvPct FROM audits $clause',
      args,
    );
    if (result.isEmpty) return null;
    return CvtAvg.fromMap(result.first);
  }

  Future<List<YfbmTrend>?> getYfbmTrend(DashboardFilter filter) async {
    final db = await dbHelper.db;
    final (:clause, :args) = _buildWhereWithArgs(filter, 'chick_quality');
    final result = await db.rawQuery(
      'SELECT date, AVG(yfbmAvgPct) as avgPct, AVG(yfbmCvPct) as cvPct FROM audits $clause GROUP BY date ORDER BY date ASC',
      args,
    );
    if (result.isEmpty) return null;
    return result.map((r) => YfbmTrend.fromMap(r)).toList();
  }

  Future<List<ChaEnvironmentalTrend>?> getChaEnvironmentalTrend(
    DashboardFilter filter,
  ) async {
    final db = await dbHelper.db;
    final (:clause, :args) = _buildWhereWithArgs(filter, 'chick_quality');
    final result = await db.rawQuery(
      'SELECT date, AVG(chaCo2) as co2, AVG(chaPm10) as pm10, AVG(chaPm25) as pm25, AVG((COALESCE(chaAirVelocitySpot1, 0) + COALESCE(chaAirVelocitySpot2, 0) + COALESCE(chaAirVelocitySpot3, 0)) / NULLIF((chaAirVelocitySpot1 IS NOT NULL) + (chaAirVelocitySpot2 IS NOT NULL) + (chaAirVelocitySpot3 IS NOT NULL), 0)) as airVelocity, AVG(chaNoiseLevel) as noiseLevel FROM audits $clause GROUP BY date ORDER BY date ASC',
      args,
    );
    if (result.isEmpty) return null;
    return result.map((r) => ChaEnvironmentalTrend.fromMap(r)).toList();
  }

  Future<List<EggStorageTrend>?> getEggStorageTrend(DashboardFilter filter) async {
    final db = await dbHelper.db;
    final (:clause, :args) = _buildWhereWithArgs(filter, 'egg_storage');
    final result = await db.rawQuery(
      'SELECT date, AVG(esEggAvgWeight) as avgWeightG, AVG(esEggUniformityPct) as uniformityPct, AVG(esEggCvPct) as cvPct, AVG(esShellTemp) as shellTempC, AVG(esEggSampleSize) as uvAffectedPct, AVG(esCo2) as co2, AVG(esEstAvg) as estAvgF, AVG(esEstCv) as estCvPct FROM audits $clause GROUP BY date ORDER BY date ASC',
      args,
    );
    if (result.isEmpty) return null;
    return result.map((r) => EggStorageTrend.fromMap(r)).toList();
  }

  Future<List<SetterComparison>?> getSetterComparisons(
    DashboardFilter filter,
    List<String> setterIds,
  ) async {
    if (setterIds.isEmpty) return [];
    final db = await dbHelper.db;
    final (:clause, :args) = _buildWhereWithArgs(filter, 'setter_optimizing');
    final idPlaceholders = List.filled(setterIds.length, '?').join(',');
    final result = await db.rawQuery(
      'SELECT soSetterId as setterId, NULL as hatchabilityPct, NULL as fertilityPct, NULL as hofPct, NULL as culledPct, NULL as deadPct, AVG(soEstAvg) as estAvgF, AVG(soEstCv) as estCvPct, AVG(soTurningAngle) as turningAngle FROM audits $clause AND soSetterId IN ($idPlaceholders) GROUP BY soSetterId',
      [...args, ...setterIds],
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
    final (:clause, :args) = _buildWhereWithArgs(filter, 'hatcher_optimizing');
    final idPlaceholders = List.filled(hatcherIds.length, '?').join(',');
    final result = await db.rawQuery(
      'SELECT hoHatcherId as hatcherId, NULL as hatchabilityPct, NULL as fertilityPct, NULL as hofPct, NULL as culledPct, NULL as deadPct, AVG(hoCvtAvg) as cvtAvgF, AVG(hoCvtCv) as cvtCvPct, hoMeconium as meconium, hoTransferDay as transferDay FROM audits $clause AND hoHatcherId IN ($idPlaceholders) GROUP BY hoHatcherId',
      [...args, ...hatcherIds],
    );
    if (result.isEmpty) return [];
    return result.map((r) => HatcherComparison.fromMap(r)).toList();
  }

  // SECURITY: never interpolate user data into SQL. Use ? placeholders only.
  ({String clause, List<Object?> args}) _buildWhereWithArgs(
    DashboardFilter filter,
    String auditType, {
    String? tableAlias,
  }) {
    final prefix = tableAlias == null ? '' : '$tableAlias.';
    final parts = <String>['${prefix}auditType = ?'];
    final args = <Object?>[_displayAuditType(auditType)];
    if (filter.customerId != null) {
      parts.add('${prefix}customerId = ?');
      args.add(filter.customerId);
    }
    if (filter.flockId != null) {
      parts.add('${prefix}flockId = ?');
      args.add(filter.flockId);
    }
    if (filter.bmkAge != null) {
      parts.add(
        'COALESCE(${prefix}haBmkAge, ${prefix}ebBmkAge, ${prefix}chickBmkAge, ${prefix}esEggBmkAge, ${prefix}soIncubationAge, ${prefix}hoIncubationAge) = ?',
      );
      args.add(filter.bmkAge);
    }
    return (clause: 'WHERE ${parts.join(' AND ')}', args: args);
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

  // SECURITY: never interpolate user data into SQL. Use ? placeholders only.
  Future<Set<String>> _tableColumns(Database db, String table) async {
    assert(
      RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(table),
      'Invalid table name',
    );
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
    _applyUnderscoreAliases(normalized);
    return normalized;
  }

  void _applyUnderscoreAliases(Map<String, dynamic> row) {
    final prefixMappings = {
      'pm_': [
        'sampleSize', 'collectionPoint',
        'omphalitisCount', 'omphalitisSeverity',
        'gaseousCecaCount', 'gaseousCecaSeverity',
        'unabsorbedYolkCount', 'unabsorbedYolkSeverity',
        'perihepatitisCount', 'perihepatitisSeverity',
        'pericarditisCount', 'pericarditisSeverity',
        'airsacAcuteCount', 'airsacAcuteSeverity',
        'airsacChronicCount', 'airsacChronicSeverity',
        'pulmonaryGranulomaCount', 'pulmonaryGranulomaSeverity',
        'swollenJointsCount', 'swollenJointsSeverity',
        'stuntedOrgansCount', 'stuntedOrgansSeverity',
        'pulmonaryHemorrhageCount', 'pulmonaryHemorrhageSeverity',
        'gaspingPresent', 'gaspingType',
        'exposedBrainCount', 'ectopicVisceraCount',
        'extraLegsCount', 'crossedBeakCount',
        'absentEyeBothCount', 'absentEyeOneCount',
        'smallEyeCount', 'hydrocephalyCount',
        'starGazerCount', 'curledToesCount',
        'shortLegsCount', 'spinalDeformityCount',
        'cardiacAnomalyCount', 'conjoinedCount',
        'otherDeformityCount', 'otherDeformityText',
        'suspectedCauseAuto', 'suspectedCauseManual',
        'photosJson',
      ],
      'es_': [
        'estReadingsJson', 'estAvg', 'estCv',
        'uvSampleSize', 'uvCuticleDamageCount',
        'uvWashingEvidenceCount', 'uvFecalCount',
        'uvMottledCount', 'uvOtherCount', 'uvPhotosJson',
        'crackPct', 'brokenPct', 'misshapedPct',
        'paleShellPct', 'roughTexturePct', 'floorEggPct',
        'eggColorDistJson', 'eggOrientation',
        'traySpacing', 'coolerProximity', 'wallProximity',
        'condensation',
      ],
      'so_': ['machineType', 'turningAngle'],
      'ho_': ['meconium', 'transferDay'],
    };

    for (final entry in prefixMappings.entries) {
      final prefix = entry.key;
      for (final field in entry.value) {
        final camelKey = '${prefix.substring(0, 2)}${field[0].toUpperCase()}${field.substring(1)}';
        final dbKey = '$prefix$field';
        if (row.containsKey(camelKey) && !row.containsKey(dbKey)) {
          row[dbKey] = row[camelKey];
          row.remove(camelKey);
        }
      }
    }
  }

  ({String clause, Object? arg}) _eggBreakoutTypeArg(String breakoutType) {
    final type = switch (breakoutType) {
      'residue' => 'Hatch Residue',
      'fresh' => 'Fresh Egg',
      'candled' => 'Candled Egg',
      _ => breakoutType,
    };
    return (clause: 'AND ebBreakoutType = ?', arg: type);
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

  String _dateOnly(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
