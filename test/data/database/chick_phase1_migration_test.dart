import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';

import '../../support/test_database.dart';

Map<String, Object?> _panelRow({
  required String id,
  required String sessionId,
  required String date,
  String? cvtReadingsJson,
  double? cvtAvgTemp,
}) => {
  'id': id,
  'sessionId': sessionId,
  'customerId': 'customer-1',
  'date': date,
  'createdAt': '2026-08-23T00:00:00.000',
  'updatedAt': '2026-08-23T00:00:00.000',
  'syncStatus': 'synced',
  'cvtReadingsJson': cvtReadingsJson,
  'cvtAvgTemp': cvtAvgTemp,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await useIsolatedAppDatabase();
  });

  tearDown(resetAppDatabase);

  test('v63 converts only explicitly Celsius-tagged chick CVT rows', () async {
    final db = await DatabaseHelper().db;
    await db.execute('PRAGMA foreign_keys = OFF');
    await db.insert(
      'chick_quality',
      _panelRow(
        id: 'celsius',
        sessionId: 'session-c',
        date: '2026-08-23',
        cvtReadingsJson: jsonEncode({
          'unit': '°C',
          'readings': {'front_top': 40.0, 'middle_middle': 39.5},
        }),
        cvtAvgTemp: 39.75,
      ),
    );
    await db.insert(
      'chick_quality',
      _panelRow(
        id: 'fahrenheit',
        sessionId: 'session-f',
        date: '2026-08-23',
        cvtReadingsJson: jsonEncode({
          'unit': '°F',
          'readings': {'front_top': 104.0},
        }),
        cvtAvgTemp: 104.0,
      ),
    );
    await db.insert(
      'chick_quality',
      _panelRow(
        id: 'untagged',
        sessionId: 'session-u',
        date: '2026-08-23',
        cvtReadingsJson: jsonEncode({
          'readings': {'front_top': 40.0},
        }),
        cvtAvgTemp: 40.0,
      ),
    );

    await DatabaseHelper().applyV63UpgradeForTest(db);

    final rows = await db.query('chick_quality', orderBy: 'id');
    final byId = {for (final row in rows) row['id'] as String: row};
    final celsius =
        jsonDecode(byId['celsius']!['cvtReadingsJson'] as String)
            as Map<String, dynamic>;
    final celsiusReadings = celsius['readings'] as Map<String, dynamic>;
    expect(celsius['unit'], '°C');
    expect(celsiusReadings['front_top'], closeTo(104.0, 0.001));
    expect(celsiusReadings['middle_middle'], closeTo(103.1, 0.001));
    expect(byId['celsius']!['cvtAvgTemp'], closeTo(103.55, 0.001));
    expect(byId['celsius']!['syncStatus'], 'pending');

    expect(byId['fahrenheit']!['cvtAvgTemp'], 104.0);
    expect(byId['fahrenheit']!['syncStatus'], 'synced');
    expect(byId['untagged']!['cvtAvgTemp'], 40.0);
    expect(byId['untagged']!['syncStatus'], 'synced');
  });

  test('v63 repairs every mismatched panel date from its session', () async {
    final db = await DatabaseHelper().db;
    await db.execute('PRAGMA foreign_keys = OFF');
    await db.insert('audit_sessions', {
      'id': 'session-1',
      'customerId': 'customer-1',
      'flockId': 'flock-1',
      'hatcheryId': 'hatchery-1',
      'date': '2026-08-23T00:00:00.000',
    });

    for (final table in const [
      'egg_storage',
      'egg_quality',
      'chick_quality',
      'chick_weights',
      'fresh_egg_breakout',
      'candled_egg_breakout',
      'residue_breakout',
      'setter_optimizing',
      'hatcher_optimizing',
    ]) {
      final row =
          _panelRow(
            id: '$table-row',
            sessionId: 'session-1',
            date: '2026-08-22',
          )..removeWhere(
            (key, _) => key == 'cvtReadingsJson' || key == 'cvtAvgTemp',
          );
      await db.insert(table, row);
    }

    await DatabaseHelper().applyV63UpgradeForTest(db);

    for (final table in const [
      'egg_storage',
      'egg_quality',
      'chick_quality',
      'chick_weights',
      'fresh_egg_breakout',
      'candled_egg_breakout',
      'residue_breakout',
      'setter_optimizing',
      'hatcher_optimizing',
    ]) {
      final row = (await db.query(table)).single;
      expect(row['date'], '2026-08-23', reason: table);
      expect(row['syncStatus'], 'pending', reason: table);
    }
  });

  test('v63 repairs an unambiguous legacy photo row reference', () async {
    final db = await DatabaseHelper().db;
    await db.execute('PRAGMA foreign_keys = OFF');
    const legacyId = 'session-1:chick_quality:draft-1';
    const persistedId = '$legacyId:sample-1';
    await db.insert(
      'chick_quality',
      _panelRow(id: persistedId, sessionId: 'session-1', date: '2026-08-23'),
    );
    await db.insert('photos', {
      'id': 'photo-1',
      'filePath': '/tmp/pasgar.jpg',
      'createdAt': '2026-08-23T09:00:00.000',
      'sessionId': 'session-1',
      'panelName': 'chick_quality',
      'panelRowId': legacyId,
      'fieldKey': 'pasgarBeakPhoto',
      'uploadStatus': 'synced',
    });

    await DatabaseHelper().applyV63UpgradeForTest(db);

    final photo = (await db.query('photos')).single;
    expect(photo['panelRowId'], persistedId);
    expect(photo['uploadStatus'], 'local');
  });
}
