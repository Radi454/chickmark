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
}
