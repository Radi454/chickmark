import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/station_sample_model.dart';

class StationSampleRepository {
  StationSampleRepository({DatabaseHelper? dbHelper});

  static const detailTables = <String>[];

  Future<void> upsertSample(StationSampleModel sample) async {}

  Future<void> upsertSampleInTransaction(
    DatabaseExecutor executor,
    StationSampleModel sample,
  ) async {}

  Future<StationSampleModel?> getSampleById(String id) async => null;

  Future<List<StationSampleModel>> getSamplesBySessionId(
    String auditSessionId,
  ) async => const [];

  Future<List<StationSampleModel>> getSamplesForStation(
    String auditSessionId,
    String stationType,
  ) async => const [];

  Future<List<StationSampleModel>> getSamplesByGroupKey(
    String auditSessionId,
    String groupKey,
  ) async => const [];

  Future<List<StationSampleModel>> getSamplesByLegacyAuditId(
    String legacyRowId,
  ) async => const [];

  Future<void> deleteSample(String id) async {}

  Future<void> upsertSampleRow(Map<String, dynamic> row) async {}

  Future<List<Map<String, dynamic>>> getAllSampleRecordRows() async => const [];

  Future<Map<String, dynamic>?> getSampleRecordRowById(String id) async => null;

  Future<List<Map<String, dynamic>>> getAllDetailRows(String table) async =>
      const [];

  Future<void> upsertDetailRow(String table, Map<String, dynamic> row) async {}
}
