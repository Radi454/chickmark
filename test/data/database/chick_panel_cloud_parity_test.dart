import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/services/supabase/sync_meta.dart';

import '../../support/test_database.dart';

/// Safety net for the local <-> cloud shape of the two chick panel tables.
///
/// The cloud column fixture is produced from `information_schema.columns`
/// after the complete Supabase migration chain runs in ephemeral PostgreSQL.
/// `scripts/test_supabase_security_hardening.sh` fails when that checked-in
/// fixture is stale, so this test never has to guess what dynamic SQL creates.
const _cloudColumnsFixture =
    'test/data/database/fixtures/chick_panel_cloud_columns.json';
const _chickPanelTables = ['chick_quality', 'chick_weights'];

/// Only `dirtyAt` is genuinely device-only. The other sync metadata columns
/// are stripped before push but remain in the historical cloud schema.
final _localOnlyColumns = kSyncMetaColumns
    .where((column) => column == 'dirtyAt')
    .toSet();

/// Test-side mirror of the private production key conversion used for push.
String supabaseSnakeCase(String key) {
  final buffer = StringBuffer();
  for (var i = 0; i < key.length; i++) {
    final char = key[i];
    final isUpper = char.toUpperCase() == char && char.toLowerCase() != char;
    if (isUpper && i > 0) buffer.write('_');
    buffer.write(char.toLowerCase());
  }
  return buffer.toString();
}

void main() {
  late Directory dbDir;
  late Map<String, Set<String>> cloudColumns;

  setUpAll(() async {
    dbDir = await useIsolatedAppDatabase();
    final fixture =
        jsonDecode(File(_cloudColumnsFixture).readAsStringSync())
            as Map<String, dynamic>;
    cloudColumns = fixture.map(
      (table, columns) =>
          MapEntry(table, (columns as List<dynamic>).cast<String>().toSet()),
    );
  });

  tearDownAll(() async {
    await resetAppDatabase();
    if (dbDir.existsSync()) dbDir.deleteSync(recursive: true);
  });

  test(
    'the executed-migration fixture covers exactly the chick panel tables',
    () {
      expect(cloudColumns.keys.toSet(), _chickPanelTables.toSet());
      for (final table in _chickPanelTables) {
        expect(cloudColumns[table], isNotEmpty, reason: table);
      }
    },
  );

  for (final table in _chickPanelTables) {
    test('$table has the same columns locally and in Supabase', () async {
      final db = await DatabaseHelper().db;
      final local = (await db.rawQuery(
        'PRAGMA table_info($table)',
      )).map((row) => row['name'].toString()).toSet();
      final remote = cloudColumns[table]!;

      final pushed = local.difference(_localOnlyColumns);
      final expectedRemote = pushed.map(supabaseSnakeCase).toSet();

      expect(
        expectedRemote.difference(remote),
        isEmpty,
        reason: 'local columns with no Supabase column to push into',
      );
      expect(
        remote.difference(expectedRemote),
        isEmpty,
        reason: 'Supabase columns nothing local ever writes',
      );
      for (final column in _localOnlyColumns) {
        expect(local, contains(column));
        expect(remote, isNot(contains(supabaseSnakeCase(column))));
      }
    });
  }
}
