import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/lab_analysis_models.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/features/lab_analysis/providers/lab_analysis_provider.dart';
import 'package:hatchaudit/features/lab_analysis/screens/lab_analysis_screen.dart';
import 'package:provider/provider.dart';

class _StaticLabAnalysisProvider extends LabAnalysisProvider {
  _StaticLabAnalysisProvider(this.batch);

  final LabAnalysisBatch batch;

  @override
  bool get isLoading => false;

  @override
  List<LabAnalysisBatch> get batches => [batch];

  @override
  List<CustomerModel> get customers => [
    CustomerModel(
      id: 'customer-1',
      name: 'Test customer',
      createdAt: DateTime(2026),
      createdBy: 'test',
    ),
  ];

  @override
  List<FlockModel> get flocks => [
    FlockModel(
      id: 'flock-1',
      customerId: 'customer-1',
      flockId: 'Test flock',
      breed: 'Test breed',
      entryDate: DateTime(2025),
    ),
  ];

  @override
  String? get selectedCustomerId => 'customer-1';

  @override
  String? get selectedFlockId => 'flock-1';

  @override
  Future<void> init({currentUser}) async {}

  @override
  Future<void> reload() async {}
}

void main() {
  testWidgets(
    'laboratory stays editable and culture is separate from sensitivity',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime(2026, 7, 20);
      final report = LabAnalysisReportModel(
        id: 'report-form',
        customerId: 'customer-1',
        flockId: 'flock-1',
        reportDate: now,
        labName: 'Existing lab',
        sampleType: 'Serum / Plasma',
        createdAt: now,
        updatedAt: now,
      );
      final provider = _StaticLabAnalysisProvider(
        LabAnalysisBatch(
          report: report,
          groups: const [],
          rowsByGroupId: const {},
        ),
      );
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider<LabAnalysisProvider>.value(value: provider),
          ],
          child: const MaterialApp(home: LabAnalysisScreen()),
        ),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Add lab result'));
      await tester.pumpAndSettle();

      Finder laboratoryTextField() => find.ancestor(
        of: find.text('Laboratory'),
        matching: find.byType(TextFormField),
      );
      Finder laboratoryDropdown() => find.ancestor(
        of: find.text('Laboratory'),
        matching: find.byType(DropdownButtonFormField<String>),
      );

      expect(laboratoryTextField(), findsOneWidget);
      expect(laboratoryDropdown(), findsNothing);

      expect(find.byKey(const ValueKey('Assay kit-IDvet')), findsOneWidget);

      for (final type in const ['PCR', 'HI', 'Bacterial Culture']) {
        await tester.tap(find.text(type));
        await tester.pumpAndSettle();
        expect(laboratoryTextField(), findsOneWidget, reason: type);
        expect(laboratoryDropdown(), findsNothing, reason: type);
      }

      expect(find.text('Culture / isolation test'), findsOneWidget);
      expect(find.text('Bacterial organism'), findsOneWidget);
      expect(find.text('Culture result'), findsOneWidget);

      await tester.tap(find.text('Sensitivity'));
      await tester.pumpAndSettle();
      expect(laboratoryTextField(), findsOneWidget);
      expect(laboratoryDropdown(), findsNothing);
      expect(find.text('Bacterial organism'), findsNothing);
      expect(find.text('Antimicrobial'), findsOneWidget);
      expect(find.text('Interpretation'), findsOneWidget);
    },
  );

  testWidgets(
    'ELISA card shows compact formatted summary and expands sample details',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime(2026, 7, 16);
      final report = LabAnalysisReportModel(
        id: 'report-1',
        customerId: 'customer-1',
        flockId: 'flock-1',
        reportDate: now,
        labName: 'IDVet',
        sampleType: 'Serum / Plasma',
        createdAt: now,
        updatedAt: now,
      );
      final group = LabAnalysisGroupModel(
        id: 'group-1',
        reportId: report.id,
        customerId: report.customerId,
        flockId: report.flockId,
        reportDate: now,
        testType: LabTestType.elisa,
        groupLabel: 'Infectious Bronchitis Indirect 2.0',
        analyte: 'Infectious Bronchitis',
        sampleCount: 40,
        meanTiter: 18958,
        minTiter: 1234,
        maxTiter: 24567,
        gmtTiter: 18312,
        cvPct: 20,
        positiveCount: 40,
        negativeCount: 0,
        interpretation: 'Review with the vaccination history.',
        severity: LabSeverity.watch,
        createdAt: now,
        updatedAt: now,
      );
      final rows = [
        LabAnalysisRowModel(
          id: 'row-1',
          groupId: group.id,
          reportId: report.id,
          customerId: report.customerId,
          flockId: report.flockId,
          reportDate: now,
          testType: LabTestType.elisa,
          rowLabel: '01',
          result: 'P',
          odValue: 1.31,
          spRatio: 2.5,
          titer: 18312,
          createdAt: now,
          updatedAt: now,
        ),
        LabAnalysisRowModel(
          id: 'row-2',
          groupId: group.id,
          reportId: report.id,
          customerId: report.customerId,
          flockId: report.flockId,
          reportDate: now,
          testType: LabTestType.elisa,
          rowLabel: '02',
          result: 'P',
          odValue: 3.94,
          spRatio: 7.95,
          titer: 24567,
          createdAt: now,
          updatedAt: now,
        ),
      ];
      final provider = _StaticLabAnalysisProvider(
        LabAnalysisBatch(
          report: report,
          groups: [group],
          rowsByGroupId: {group.id: rows},
        ),
      );
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider<LabAnalysisProvider>.value(value: provider),
          ],
          child: const MaterialApp(home: LabAnalysisScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('Sample size'), findsOneWidget);
      expect(find.text('Mean'), findsOneWidget);
      expect(find.text('GMT'), findsOneWidget);
      expect(find.text('CV%'), findsOneWidget);
      expect(find.text('Positive / Negative'), findsOneWidget);
      expect(find.text('Minimum'), findsOneWidget);
      expect(find.text('Maximum'), findsOneWidget);
      expect(find.text('18,958'), findsOneWidget);
      expect(find.text('18,312'), findsOneWidget);
      expect(find.text('1,234'), findsOneWidget);
      expect(find.text('24,567'), findsOneWidget);
      expect(find.text('40 / 0'), findsOneWidget);
      expect(find.text('01'), findsNothing);

      final details = find.byKey(const ValueKey('lab-sample-details-group-1'));
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('lab-sample-table-group-1')),
        findsOneWidget,
      );
      expect(find.text('01'), findsOneWidget);
      expect(find.text('02'), findsOneWidget);
      expect(find.text('18,312'), findsNWidgets(2));
      expect(find.text('24,567'), findsNWidgets(2));
    },
  );
}
