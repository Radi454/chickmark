import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/lab_analysis_models.dart';
import 'package:hatchaudit/features/dashboard/models/lab_analysis_trend_models.dart';
import 'package:hatchaudit/features/dashboard/widgets/lab_analysis_trend_panel.dart';

void main() {
  for (final size in [const Size(390, 1200), const Size(1100, 900)]) {
    testWidgets('ELISA trend panel is responsive at ${size.width}px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: LabAnalysisTrendPanel(series: _series()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mycoplasma gallisepticum · flock trend'), findsOne);
      expect(find.text('House comparison · GMT and uniformity'), findsOne);
      expect(find.text('Pooled repeat'), findsOne);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('CV%'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}

LabElisaTrendSeries _series() {
  final dates = [
    DateTime(2026, 5, 5),
    DateTime(2026, 6, 4),
    DateTime(2026, 6, 21),
  ];
  return LabElisaTrendSeries(
    analyte: 'Mycoplasma gallisepticum',
    points: [
      LabElisaTrendPoint(
        date: dates[0],
        scopeCount: 8,
        averageGmt: 4904,
        minGmt: 2419,
        maxGmt: 11469,
        averageCv: 78.1,
        minCv: 32,
        maxCv: 129,
        positivePct: 91.9,
        minPositivePct: 66.7,
        maxPositivePct: 100,
      ),
      LabElisaTrendPoint(
        date: dates[1],
        scopeCount: 8,
        averageGmt: 11786,
        minGmt: 5490,
        maxGmt: 15649,
        averageCv: 34.3,
        minCv: 2,
        maxCv: 71,
        positivePct: 97.1,
        minPositivePct: 80,
        maxPositivePct: 100,
        pooledGmt: 11289,
        pooledCv: 35,
        pooledPositivePct: 97.1,
      ),
      LabElisaTrendPoint(
        date: dates[2],
        scopeCount: 8,
        averageGmt: 11533,
        minGmt: 8622,
        maxGmt: 13632,
        averageCv: 21.3,
        minCv: 1,
        maxCv: 49,
        positivePct: 100,
        minPositivePct: 100,
        maxPositivePct: 100,
        pooledGmt: 11421,
        pooledCv: 24,
        pooledPositivePct: 100,
      ),
    ],
    scopePoints: [
      for (var house = 1; house <= 8; house++)
        for (var dateIndex = 0; dateIndex < dates.length; dateIndex++)
          LabElisaScopePoint(
            date: dates[dateIndex],
            scope: 'House $house',
            gmtTiter: 2500 + house * 900 + dateIndex * 3200,
            cvPct: 95 - dateIndex * 30 - house * 3,
            positivePct: dateIndex == 0 && house <= 2 ? 75 : 100,
            severity: dateIndex == 0 && house <= 3
                ? LabSeverity.alert
                : LabSeverity.watch,
          ),
    ],
  );
}
