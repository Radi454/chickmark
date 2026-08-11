import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/lab_analysis_models.dart';
import 'package:hatchaudit/data/repositories/lab_analysis_repository.dart';

import '../../support/test_database.dart';

void main() {
  late Directory tempDir;
  late LabAnalysisRepository repository;

  setUp(() async {
    tempDir = await useIsolatedAppDatabase();
    repository = LabAnalysisRepository();
    final db = await DatabaseHelper().db;
    await db.insert('customers', {
      'id': 'customer-1',
      'name': 'الغريب',
      'createdAt': DateTime.utc(2026, 6, 1).toIso8601String(),
    });
    await db.insert('flocks', {
      'id': 'flock-1',
      'customerId': 'customer-1',
      'flockId': 'السلام',
      'breed': 'COBB',
      'entryDate': DateTime.utc(2025, 9, 1).toIso8601String(),
      'isAgeEstimated': 0,
      'status': 'active',
      'depletionAgeWeeks': 65,
    });
  });

  tearDown(() async {
    await resetAppDatabase();
    await tempDir.delete(recursive: true);
  });

  test('saves ELISA group with full sample rows for dashboard use', () async {
    final now = DateTime.utc(2026, 6, 4);
    final report = LabAnalysisReportModel(
      id: 'report-1',
      customerId: 'customer-1',
      flockId: 'flock-1',
      reportDate: now,
      receivedDate: now,
      labName: 'IDvet',
      sampleType: 'Serum / Plasma',
      flockAgeWeeks: 40,
      createdAt: now,
      updatedAt: now,
    );
    final group = LabAnalysisGroupModel(
      id: 'group-1',
      reportId: report.id,
      customerId: report.customerId,
      flockId: report.flockId,
      reportDate: report.reportDate,
      testType: LabTestType.elisa,
      groupLabel: 'عنبر 1',
      analyte: 'MG',
      productCode: 'MG/0416',
      sampleCount: 4,
      meanTiter: 10795,
      gmtTiter: 8891,
      cvPct: 56,
      positiveCount: 4,
      createdAt: now,
      updatedAt: now,
    );
    final rows = [
      LabAnalysisRowModel(
        id: 'sample-1',
        groupId: group.id,
        reportId: report.id,
        customerId: report.customerId,
        flockId: report.flockId,
        reportDate: report.reportDate,
        testType: LabTestType.elisa,
        rowLabel: '01',
        result: 'P',
        odValue: 0.624,
        spRatio: 1.819,
        titer: 2731,
        titerGroup: 2,
        createdAt: now,
        updatedAt: now,
      ),
      LabAnalysisRowModel(
        id: 'sample-2',
        groupId: group.id,
        reportId: report.id,
        customerId: report.customerId,
        flockId: report.flockId,
        reportDate: report.reportDate,
        testType: LabTestType.elisa,
        rowLabel: '02',
        result: 'P',
        odValue: 2.347,
        spRatio: 7.29,
        titer: 9662,
        titerGroup: 6,
        createdAt: now,
        updatedAt: now,
      ),
    ];

    await repository.saveBatch(report: report, group: group, rows: rows);

    final batches = await repository.getBatches(
      customerId: 'customer-1',
      flockId: 'flock-1',
    );
    expect(batches, hasLength(1));
    expect(batches.single.groups.single.positivePct, 100);
    expect(batches.single.rowsByGroupId['group-1'], hasLength(2));
    expect(batches.single.groups.single.severity, LabSeverity.watch);

    final summaries = await repository.getDashboardSummaries(
      customerId: 'customer-1',
      flockId: 'flock-1',
    );
    expect(summaries, hasLength(1));
    expect(summaries.single.group.groupLabel, 'عنبر 1');
    expect(summaries.single.rows.first.spRatio, 1.819);
  });

  test(
    'saves bacterial culture findings independently of sensitivity',
    () async {
      final now = DateTime.utc(2026, 7, 19);
      final report = LabAnalysisReportModel(
        id: 'culture-report',
        customerId: 'customer-1',
        flockId: 'flock-1',
        reportDate: now,
        labName: 'معمل أبو العمايم',
        sampleType: 'Broiler chicks',
        createdAt: now,
        updatedAt: now,
      );
      final group = LabAnalysisGroupModel(
        id: 'culture-group',
        reportId: report.id,
        customerId: report.customerId,
        flockId: report.flockId,
        reportDate: report.reportDate,
        testType: LabTestType.culture,
        groupLabel: 'Whole flock / pooled',
        analyte: 'Salmonella spp.',
        method: 'Salmonella isolation',
        createdAt: now,
        updatedAt: now,
      );
      final row = LabAnalysisRowModel(
        id: 'culture-row',
        groupId: group.id,
        reportId: report.id,
        customerId: report.customerId,
        flockId: report.flockId,
        reportDate: report.reportDate,
        testType: LabTestType.culture,
        rowLabel: 'Salmonella spp.',
        analyte: 'Salmonella spp.',
        result: 'Negative',
        resultCategory: 'Negative',
        createdAt: now,
        updatedAt: now,
      );

      await repository.saveBatch(report: report, group: group, rows: [row]);

      final batches = await repository.getBatches(
        customerId: 'customer-1',
        flockId: 'flock-1',
      );
      final savedGroup = batches.single.groups.single;
      final savedRow = batches.single.rowsByGroupId[savedGroup.id]!.single;

      expect(savedGroup.testType, LabTestType.culture);
      expect(savedGroup.method, 'Salmonella isolation');
      expect(savedGroup.sampleCount, 1);
      expect(savedGroup.positiveCount, 0);
      expect(savedGroup.negativeCount, 1);
      expect(savedGroup.severity, LabSeverity.normal);
      expect(savedRow.analyte, 'Salmonella spp.');
      expect(savedRow.result, 'Negative');
      expect(savedRow.interpretation, contains('not isolated'));
    },
  );

  group('mark-synced race protection', () {
    LabAnalysisReportModel report(String id, DateTime now) =>
        LabAnalysisReportModel(
          id: id,
          customerId: 'customer-1',
          flockId: 'flock-1',
          reportDate: now,
          labName: 'IDvet',
          sampleType: 'Serum / Plasma',
          createdAt: now,
          updatedAt: now,
        );

    LabAnalysisGroupModel group(String id, LabAnalysisReportModel report) =>
        LabAnalysisGroupModel(
          id: id,
          reportId: report.id,
          customerId: report.customerId,
          flockId: report.flockId,
          reportDate: report.reportDate,
          testType: LabTestType.elisa,
          groupLabel: 'Race group',
          createdAt: report.createdAt,
          updatedAt: report.updatedAt,
        );

    test('a report edited mid-push stays pending after markRowsSynced',
        () async {
      final now = DateTime.utc(2026, 6, 4);
      final r = report('race-report', now);
      final g = group('race-group', r);

      await repository.saveBatch(report: r, group: g, rows: const []);
      await repository.getDirtyRows(
        LabAnalysisRepository.reportsTable,
      ); // capture cutoff
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repository.saveBatch(
        report: r,
        group: g,
        rows: const [],
      ); // mid-push edit
      await repository.markRowsSynced(LabAnalysisRepository.reportsTable, [
        'race-report',
      ]);

      final row = await repository.getRowById(
        LabAnalysisRepository.reportsTable,
        'race-report',
      );
      expect(row!['syncStatus'], 'pending');
      expect(row['dirtyAt'], isNotNull);
    });

    test('an unedited report is cleared by markRowsSynced', () async {
      final now = DateTime.utc(2026, 6, 4);
      final r = report('race-report-2', now);
      final g = group('race-group-2', r);

      await repository.saveBatch(report: r, group: g, rows: const []);
      await repository.getDirtyRows(LabAnalysisRepository.reportsTable);
      await repository.markRowsSynced(LabAnalysisRepository.reportsTable, [
        'race-report-2',
      ]);

      final row = await repository.getRowById(
        LabAnalysisRepository.reportsTable,
        'race-report-2',
      );
      expect(row!['syncStatus'], 'synced');
    });
  });
}
