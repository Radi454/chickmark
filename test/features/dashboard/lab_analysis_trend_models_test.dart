import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/lab_analysis_models.dart';
import 'package:hatchaudit/features/dashboard/models/lab_analysis_trend_models.dart';

void main() {
  group('LabAnalysisTrendBuilder', () {
    test('keeps pooled repeat summaries separate from house averages', () {
      final may = DateTime(2026, 5, 5);
      final june = DateTime(2026, 6, 4);
      final summaries = [
        _summary(
          id: 'may-house-1',
          date: may,
          scope: 'House 1',
          gmt: 2000,
          cv: 100,
          positive: 3,
          samples: 4,
        ),
        _summary(
          id: 'may-house-2',
          date: may,
          scope: 'House 2',
          gmt: 4000,
          cv: 60,
          positive: 2,
          samples: 3,
        ),
        _summary(
          id: 'may-pool',
          date: may,
          scope: 'Pooled repeat',
          gmt: 9000,
          cv: 20,
          positive: 7,
          samples: 7,
          pooled: true,
        ),
        _summary(
          id: 'june-house-1',
          date: june,
          scope: 'House 1',
          gmt: 10000,
          cv: 30,
          positive: 5,
          samples: 5,
        ),
        _summary(
          id: 'june-house-2',
          date: june,
          scope: 'House 2',
          gmt: 14000,
          cv: 20,
          positive: 5,
          samples: 5,
        ),
        _summary(
          id: 'june-pool',
          date: june,
          scope: 'Pooled repeat',
          gmt: 11900,
          cv: 24,
          positive: 10,
          samples: 10,
          pooled: true,
        ),
      ];

      final series = LabAnalysisTrendBuilder.buildElisa(summaries).single;

      expect(series.points, hasLength(2));
      expect(series.scopePoints, hasLength(4));
      expect(series.scopes, ['House 1', 'House 2']);
      expect(series.points.first.averageGmt, 3000);
      expect(series.points.first.averageCv, 80);
      expect(series.points.first.positivePct, closeTo(71.43, 0.01));
      expect(series.points.first.pooledGmt, 9000);
      expect(series.points.last.averageGmt, 12000);
      expect(series.points.last.pooledGmt, 11900);
    });

    test('requires at least two canonical report dates', () {
      final summaries = [
        _summary(
          id: 'only',
          date: DateTime(2026, 7, 4),
          scope: 'Whole flock',
          gmt: 12000,
          cv: 22,
          positive: 40,
          samples: 40,
        ),
      ];

      expect(LabAnalysisTrendBuilder.buildElisa(summaries), isEmpty);
    });
  });

  test('dashboard severity counters count result groups, not sample rows', () {
    final summary = _summary(
      id: 'watch-group',
      date: DateTime(2026, 7, 4),
      scope: 'House 1',
      gmt: 12000,
      cv: 22,
      positive: 40,
      samples: 40,
      rowSeverities: List.filled(40, LabSeverity.watch),
    );

    expect(summary.watchCount, 1);
    expect(summary.alertCount, 0);
  });
}

LabAnalysisDashboardSummary _summary({
  required String id,
  required DateTime date,
  required String scope,
  required double gmt,
  required double cv,
  required int positive,
  required int samples,
  bool pooled = false,
  List<LabSeverity> rowSeverities = const [],
}) {
  final report = LabAnalysisReportModel(
    id: 'report-$id',
    customerId: 'customer',
    flockId: 'flock',
    reportDate: date,
    createdAt: date,
    updatedAt: date,
  );
  final group = LabAnalysisGroupModel(
    id: 'group-$id',
    reportId: report.id,
    customerId: report.customerId,
    flockId: report.flockId,
    reportDate: date,
    testType: LabTestType.elisa,
    groupLabel: scope,
    sampleScope: pooled ? 'Whole flock repeat plate' : scope,
    analyte: 'Mycoplasma gallisepticum',
    sampleCount: samples,
    gmtTiter: gmt,
    cvPct: cv,
    positiveCount: positive,
    negativeCount: samples - positive,
    positivePct: positive * 100 / samples,
    severity: LabSeverity.watch,
    createdAt: date,
    updatedAt: date,
  );
  return LabAnalysisDashboardSummary(
    report: report,
    group: group,
    rows: [
      for (var index = 0; index < rowSeverities.length; index++)
        LabAnalysisRowModel(
          id: 'row-$id-$index',
          groupId: group.id,
          reportId: report.id,
          customerId: report.customerId,
          flockId: report.flockId,
          reportDate: date,
          testType: LabTestType.elisa,
          severity: rowSeverities[index],
          createdAt: date,
          updatedAt: date,
        ),
    ],
  );
}
