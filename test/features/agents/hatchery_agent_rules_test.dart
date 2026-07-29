import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/features/agents/services/hatchery_agent_rules.dart';
import 'package:sqflite/sqflite.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDirectory;

  setUpAll(() async {
    databaseDirectory = await useIsolatedAppDatabase();
  });

  setUp(() async {
    await resetAppDatabase();
    await _seedComparableContext();
  });

  tearDownAll(() async {
    await resetAppDatabase();
    if (databaseDirectory.existsSync()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  test('calculates hatchability from total production and eggs placed', () {
    expect(
      calculateHatchabilityPct(totalProduction: 11518, eggsPlaced: 19200),
      closeTo(59.9895, 0.0001),
    );
  });

  test('returns null hatchability when eggs placed is zero', () {
    expect(
      calculateHatchabilityPct(totalProduction: 100, eggsPlaced: 0),
      isNull,
    );
  });

  test(
    'returns null hatchability for missing denominator or negative production',
    () {
      expect(
        calculateHatchabilityPct(totalProduction: null, eggsPlaced: 100),
        isNull,
      );
      expect(
        calculateHatchabilityPct(totalProduction: 100, eggsPlaced: null),
        isNull,
      );
      expect(
        calculateHatchabilityPct(totalProduction: -1, eggsPlaced: 100),
        isNull,
      );
    },
  );

  test('allows zero production with a valid egg count', () {
    expect(calculateHatchabilityPct(totalProduction: 0, eggsPlaced: 100), 0);
  });

  test('flags a three point historical increase', () {
    final warning = buildHistoricalWarning(
      currentPct: 83,
      previousPct: 80,
      thresholdPoints: 3,
    );

    expect(warning, isNotNull);
    expect(warning!.kind, HatcheryRowWarningKind.historicalChange);
    expect(warning.severity, HatcheryRowWarningSeverity.review);
  });

  test('flags a ratio-derived historical change of exactly three points', () {
    final warning = buildHistoricalWarning(
      currentPct: calculateHatchabilityPct(
        totalProduction: 259,
        eggsPlaced: 300,
      )!,
      previousPct: calculateHatchabilityPct(
        totalProduction: 250,
        eggsPlaced: 300,
      ),
      thresholdPoints: 3,
    );

    expect(warning, isNotNull);
  });

  test('does not flag a two point historical increase', () {
    expect(
      buildHistoricalWarning(
        currentPct: 82,
        previousPct: 80,
        thresholdPoints: 3,
      ),
      isNull,
    );
  });

  test(
    'flags an equal-sized historical decrease with an absolute point change',
    () {
      final warning = buildHistoricalWarning(currentPct: 77, previousPct: 80);

      expect(warning, isNotNull);
      expect(warning!.previousPct, 80);
      expect(warning.currentPct, 77);
      expect(warning.messageEn, contains('3.0'));
    },
  );

  test('does not create a historical warning without a comparable row', () {
    expect(buildHistoricalWarning(currentPct: 83, previousPct: null), isNull);
  });

  test('BMK calms a rising hatchability warning when current is below BMK', () {
    final warning = buildBmkWarning(
      currentPct: 85,
      previousPct: 80,
      bmkPct: 88,
      flockAgeWeeks: 30,
    );

    expect(warning, isNotNull);
    expect(warning!.kind, HatcheryRowWarningKind.bmkContext);
    expect(warning.messageEn, contains('may be consistent'));
  });

  test('does not add BMK context when a result is not rising below BMK', () {
    expect(
      buildBmkWarning(
        currentPct: 80,
        previousPct: 85,
        bmkPct: 88,
        flockAgeWeeks: 30,
      ),
      isNull,
    );
    expect(
      buildBmkWarning(
        currentPct: 89,
        previousPct: 80,
        bmkPct: 88,
        flockAgeWeeks: 30,
      ),
      isNull,
    );
  });

  test(
    'reports missing flock age only for a requested rising BMK comparison',
    () {
      final warning = buildBmkWarning(
        currentPct: 85,
        previousPct: 80,
        bmkPct: null,
        flockAgeWeeks: null,
      );

      expect(warning, isNotNull);
      expect(warning!.kind, HatcheryRowWarningKind.missingFlockAge);
      expect(warning.severity, HatcheryRowWarningSeverity.info);
      expect(
        buildBmkWarning(
          currentPct: 80,
          previousPct: null,
          bmkPct: null,
          flockAgeWeeks: null,
        ),
        isNull,
      );
    },
  );

  test(
    'reports a missing BMK when age is available for a rising comparison',
    () {
      final warning = buildBmkWarning(
        currentPct: 85,
        previousPct: 80,
        bmkPct: null,
        flockAgeWeeks: 30,
      );

      expect(warning, isNotNull);
      expect(warning!.kind, HatcheryRowWarningKind.missingBmk);
      expect(warning.severity, HatcheryRowWarningSeverity.info);
    },
  );

  test('warning JSON round-trips every contextual field', () {
    const warning = HatcheryRowWarning(
      kind: HatcheryRowWarningKind.bmkContext,
      severity: HatcheryRowWarningSeverity.info,
      messageEn: 'Context',
      messageAr: 'سياق',
      previousPct: 80,
      currentPct: 85,
      bmkPct: 88,
      flockAgeWeeks: 30,
    );

    final copy = HatcheryRowWarning.fromJson(warning.toJson());

    expect(copy.kind, HatcheryRowWarningKind.bmkContext);
    expect(copy.severity, HatcheryRowWarningSeverity.info);
    expect(copy.messageEn, 'Context');
    expect(copy.messageAr, 'سياق');
    expect(copy.previousPct, 80);
    expect(copy.currentPct, 85);
    expect(copy.bmkPct, 88);
    expect(copy.flockAgeWeeks, 30);
  });

  test('identity-resolution warnings from Telegram drafts are readable', () {
    final warning = HatcheryRowWarning.fromJson({
      'kind': 'identityResolution',
      'severity': 'review',
      'messageEn': 'More than one customer matches this name.',
      'messageAr': 'يوجد أكثر من عميل يطابق هذا الاسم.',
    });

    expect(warning.kind, HatcheryRowWarningKind.identityResolution);
    expect(warning.severity, HatcheryRowWarningSeverity.review);
  });

  test('warning JSON rejects an unknown warning kind', () {
    expect(
      () => HatcheryRowWarning.fromJson({
        'kind': 'futureWarningKind',
        'severity': 'info',
      }),
      throwsFormatException,
    );
  });

  test('warning JSON rejects an unknown warning severity', () {
    expect(
      () => HatcheryRowWarning.fromJson({
        'kind': 'historicalChange',
        'severity': 'futureWarningSeverity',
      }),
      throwsFormatException,
    );
  });

  test('review engine combines comparable and BMK warnings', () async {
    final db = await DatabaseHelper().db;
    await _insertDailyRecord(
      db,
      id: 'previous',
      hatchDate: DateTime.utc(2026, 7, 20),
      hatchabilityPct: 80,
    );
    await db.update(
      'bmk_breeds',
      {'hatchabilityPct': 88.0},
      where: 'breed = ? AND ageWeek = ?',
      whereArgs: const ['Ross308', 30],
    );
    final engine = HatcheryAgentRuleEngine();

    final warnings = await engine.buildReviewWarnings(
      customerId: 'customer-1',
      flockId: 'flock-1',
      stationName: 'Station A',
      breed: 'Ross308',
      hatchDate: DateTime.utc(2026, 7, 27),
      currentHatchabilityPct: 85,
      flockAgeWeeks: 30,
    );

    expect(warnings.map((warning) => warning.kind), [
      HatcheryRowWarningKind.historicalChange,
      HatcheryRowWarningKind.bmkContext,
    ]);
  });

  test(
    'review engine preserves the selected nearest BMK age in its context',
    () async {
      final db = await DatabaseHelper().db;
      await _insertDailyRecord(
        db,
        id: 'previous',
        hatchDate: DateTime.utc(2026, 7, 20),
        hatchabilityPct: 80,
      );

      final warnings = await HatcheryAgentRuleEngine().buildReviewWarnings(
        customerId: 'customer-1',
        flockId: 'flock-1',
        stationName: 'Station A',
        breed: 'Ross308',
        hatchDate: DateTime.utc(2026, 7, 27),
        currentHatchabilityPct: 85,
        flockAgeWeeks: 20,
      );

      final bmkWarning = warnings.singleWhere(
        (warning) => warning.kind == HatcheryRowWarningKind.bmkContext,
      );
      expect(bmkWarning.flockAgeWeeks, 25);
      expect(bmkWarning.messageEn, contains('at 25 weeks'));
      expect(bmkWarning.toJson()['flockAgeWeeks'], 25);
    },
  );

  test(
    'review engine treats nonpositive flock ages as missing BMK input',
    () async {
      final db = await DatabaseHelper().db;
      await _insertDailyRecord(
        db,
        id: 'previous',
        hatchDate: DateTime.utc(2026, 7, 20),
        hatchabilityPct: 80,
      );

      for (final flockAgeWeeks in [0, -1]) {
        final warnings = await HatcheryAgentRuleEngine().buildReviewWarnings(
          customerId: 'customer-1',
          flockId: 'flock-1',
          stationName: 'Station A',
          breed: 'Ross308',
          hatchDate: DateTime.utc(2026, 7, 27),
          currentHatchabilityPct: 85,
          flockAgeWeeks: flockAgeWeeks,
        );

        expect(warnings.map((warning) => warning.kind), [
          HatcheryRowWarningKind.historicalChange,
          HatcheryRowWarningKind.missingFlockAge,
        ]);
      }
    },
  );

  test(
    'review engine returns missing age context for a rising comparable result',
    () async {
      final db = await DatabaseHelper().db;
      await _insertDailyRecord(
        db,
        id: 'previous',
        hatchDate: DateTime.utc(2026, 7, 20),
        hatchabilityPct: 80,
      );

      final warnings = await HatcheryAgentRuleEngine().buildReviewWarnings(
        customerId: 'customer-1',
        flockId: 'flock-1',
        stationName: 'Station A',
        breed: 'Ross308',
        hatchDate: DateTime.utc(2026, 7, 27),
        currentHatchabilityPct: 85,
        flockAgeWeeks: null,
      );

      expect(warnings.map((warning) => warning.kind), [
        HatcheryRowWarningKind.historicalChange,
        HatcheryRowWarningKind.missingFlockAge,
      ]);
    },
  );
}

Future<void> _seedComparableContext() async {
  final db = await DatabaseHelper().db;
  await db.insert('customers', {
    'id': 'customer-1',
    'name': 'Customer One',
    'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  await db.insert('flocks', {
    'id': 'flock-1',
    'customerId': 'customer-1',
    'flockId': 'Ross 1',
    'breed': 'Ross308',
    'entryDate': DateTime.utc(2025, 12, 1).toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

Future<void> _insertDailyRecord(
  Database db, {
  required String id,
  required DateTime hatchDate,
  required double hatchabilityPct,
}) {
  return db.insert('hatchery_daily_records', {
    'id': id,
    'customerId': 'customer-1',
    'flockId': 'flock-1',
    'stationName': 'Station A',
    'breed': 'Ross308',
    'eggsPlaced': 1000,
    'hatchDate': hatchDate.toIso8601String(),
    'totalProduction': hatchabilityPct * 10,
    'hatchabilityPct': hatchabilityPct,
  });
}
