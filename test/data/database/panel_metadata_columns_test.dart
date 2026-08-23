import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    await useIsolatedAppDatabase();
  });

  tearDown(resetAppDatabase);

  test('every panel table carries the sample and domain metadata columns',
      () async {
    final db = await DatabaseHelper().db;
    const expected = {
      'sampleMode',
      'scopeType',
      'sampleLabel',
      'sampleIndex',
      'sourceDomain',
      'actionDomain',
      'recommendationTarget',
    };
    for (final panel in PanelSampleSchema.panels) {
      final columns = (await db.rawQuery(
        'PRAGMA table_info(${panel.tableName})',
      )).map((row) => row['name'] as String).toSet();
      expect(
        columns.containsAll(expected),
        isTrue,
        reason: '${panel.tableName} is missing ${expected.difference(columns)}',
      );
    }
  });

  test('database version is 62', () async {
    final db = await DatabaseHelper().db;
    expect(await db.getVersion(), 62);
  });
}
