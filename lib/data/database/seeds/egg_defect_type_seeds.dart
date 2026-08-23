import 'package:sqflite/sqflite.dart';

import '../../../features/audits/models/egg_grading.dart';

/// Seeds `egg_defect_types` from the Dart catalogue. Idempotent: re-running it
/// refreshes names and descriptions but never removes a code, because saved
/// defect counts join on `code` and must keep resolving.
Future<void> seedEggDefectTypes(DatabaseExecutor db) async {
  final now = DateTime.now().toIso8601String();
  final batch = db.batch();
  for (final defect in kEggDefectTypes) {
    batch.insert(
      'egg_defect_types',
      {
        'id': 'egg-defect-${defect.code}',
        'code': defect.code,
        'name': defect.name,
        'category': defect.category,
        'isReject': defect.isReject ? 1 : 0,
        'description': defect.description,
        'imageAsset': defect.imageAsset,
        'sortOrder': defect.sortOrder,
        'isActive': 1,
        'createdAt': now,
        'updatedAt': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  await batch.commit(noResult: true);
}
