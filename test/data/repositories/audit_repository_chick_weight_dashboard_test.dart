import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/utils/calculation_utils.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/data/repositories/audit_repository.dart';
import 'package:hatchaudit/features/dashboard/models/dashboard_filter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite/sqflite.dart';

class MockDatabase extends Mock implements Database {}

class MockDatabaseHelper extends Mock implements DatabaseHelper {}

void main() {
  late MockDatabaseHelper dbHelper;
  late MockDatabase db;
  late AuditRepository repository;

  setUp(() {
    dbHelper = MockDatabaseHelper();
    db = MockDatabase();
    when(() => dbHelper.db).thenAnswer((_) async => db);
    repository = AuditRepository(dbHelper: dbHelper);
  });

  group('AuditRepository.getChickWeightTrend', () {
    test(
      'aggregates dashboard weights from normalized sample records',
      () async {
        when(() => db.rawQuery(any(), any())).thenAnswer(
          (_) async => [
            _sampleRow('2026-01-01', [40, 50], legacyAvgWeight: 10),
            _sampleRow('2026-01-01', [60, 70], legacyAvgWeight: 99),
          ],
        );

        final trend = await repository.getChickWeightTrend(
          DashboardFilter(customerId: 'customer-1', flockId: 'flock-1'),
        );

        expect(trend, hasLength(1));
        expect(trend!.single.date, '2026-01-01');
        expect(trend.single.avgWeightG, 55);
        expect(
          trend.single.cvPct,
          CalculationUtils.cvPercent([40, 50, 60, 70]),
        );
        expect(trend.single.uniformityPct, 50);

        final sql =
            verify(() => db.rawQuery(captureAny(), captureAny())).captured.first
                as String;
        expect(sql, contains('sample_records'));
        expect(sql, contains('resultSummaryJson'));
        expect(sql, isNot(contains('AVG(chickAvgWeight)')));
        expect(sql, isNot(contains('AVG(chickCvPct)')));
        expect(sql, isNot(contains('AVG(chickUniformityPct)')));
      },
    );

    test(
      'calculates one trend point per date from raw sample weights',
      () async {
        when(() => db.rawQuery(any(), any())).thenAnswer(
          (_) async => [
            _sampleRow('2026-01-02', [55, 65]),
            _sampleRow('2026-01-01', [40, 50]),
          ],
        );

        final trend = await repository.getChickWeightTrend(DashboardFilter());

        expect(trend!.map((point) => point.date), ['2026-01-01', '2026-01-02']);
        expect(trend.map((point) => point.avgWeightG), [45, 60]);
        expect(trend.map((point) => point.cvPct), [
          CalculationUtils.cvPercent([40, 50]),
          CalculationUtils.cvPercent([55, 65]),
        ]);
      },
    );

    test(
      'combines multiple compare samples before calculating averages and CV',
      () async {
        when(() => db.rawQuery(any(), any())).thenAnswer(
          (_) async => [
            _sampleRow('2026-01-01', [41, 42]),
            _sampleRow('2026-01-01', [51, 52]),
            _sampleRow('2026-01-01', [61, 62]),
          ],
        );

        final trend = await repository.getChickWeightTrend(DashboardFilter());

        final allWeights = [41.0, 42.0, 51.0, 52.0, 61.0, 62.0];
        final avg = CalculationUtils.average(allWeights);
        expect(trend!.single.avgWeightG, avg);
        expect(trend.single.cvPct, CalculationUtils.cvPercent(allWeights));
        expect(
          trend.single.uniformityPct,
          CalculationUtils.uniformityPercent(allWeights, avg * 0.9, avg * 1.1),
        );
      },
    );

    test(
      'edited sample summaries replace stale legacy audit dashboard values',
      () async {
        when(() => db.rawQuery(any(), any())).thenAnswer(
          (_) async => [
            _sampleRow(
              '2026-01-01',
              [90, 100],
              legacyAvgWeight: 42,
              legacyCvPct: 2,
              legacyUniformityPct: 70,
            ),
          ],
        );

        final trend = await repository.getChickWeightTrend(DashboardFilter());

        expect(trend!.single.avgWeightG, 95);
        expect(trend.single.cvPct, CalculationUtils.cvPercent([90, 100]));
        expect(trend.single.uniformityPct, 100);
      },
    );
  });
}

Map<String, Object?> _sampleRow(
  String date,
  List<num> weights, {
  num? legacyAvgWeight,
  num? legacyCvPct,
  num? legacyUniformityPct,
}) {
  final summary = <String, Object?>{'chickWeights': weights};
  if (legacyAvgWeight != null) {
    summary['chickAvgWeight'] = legacyAvgWeight;
  }
  if (legacyCvPct != null) {
    summary['chickCvPct'] = legacyCvPct;
  }
  if (legacyUniformityPct != null) {
    summary['chickUniformityPct'] = legacyUniformityPct;
  }
  return {
    'date': date,
    'sectorType': StationSampleModel.sectorChickWeights,
    'resultSummaryJson': jsonEncode(summary),
    'calculatedBmkAgeDays': null,
    'legacyBmkAge': null,
    'avgWeightG': legacyAvgWeight,
    'cvPct': legacyCvPct,
    'uniformityPct': legacyUniformityPct,
  };
}
