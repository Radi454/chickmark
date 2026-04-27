import '../models/troubleshooting_model.dart';
import '../database/database_helper.dart';

class TroubleshootingRepository {
  final dbHelper = DatabaseHelper();

  Future<TroubleshootingModel?> getByParameter(String parameterId) async {
    final db = await dbHelper.db;
    final result = await db.query(
      'troubleshooting',
      where: 'id = ?',
      whereArgs: [parameterId],
    );
    if (result.isNotEmpty) {
      return TroubleshootingModel.fromMap(result.first);
    }
    return null;
  }

  Future<Map<String, TroubleshootingModel>> getByParameters(
    List<String> parameterIds,
  ) async {
    if (parameterIds.isEmpty) return {};
    final db = await dbHelper.db;
    final placeholders = List.filled(parameterIds.length, '?').join(',');
    final result = await db.query(
      'troubleshooting',
      where: 'id IN ($placeholders)',
      whereArgs: parameterIds,
    );
    return {
      for (final row in result)
        row['id'] as String: TroubleshootingModel.fromMap(row),
    };
  }
}
