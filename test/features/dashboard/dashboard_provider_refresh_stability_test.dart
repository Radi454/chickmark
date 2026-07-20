import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/hatchery_model.dart';
import 'package:hatchaudit/data/models/lab_analysis_models.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/data/repositories/customer_repository.dart';
import 'package:hatchaudit/data/repositories/flock_repository.dart';
import 'package:hatchaudit/data/repositories/hatchery_repository.dart';
import 'package:hatchaudit/data/repositories/lab_analysis_repository.dart';
import 'package:hatchaudit/data/repositories/panel_dashboard_repository.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';

class _StaticCustomerRepository extends CustomerRepository {
  @override
  Future<List<CustomerModel>> getAllCustomers() async => const [];
}

class _StaticFlockRepository extends FlockRepository {
  @override
  Future<List<FlockModel>> getAllFlocks() async => const [];
}

class _StaticHatcheryRepository extends HatcheryRepository {
  @override
  Future<List<HatcheryModel>> getAllHatcheries() async => const [];
}

class _StaticPanelDashboardRepository extends PanelDashboardRepository {
  @override
  Future<List<int>> getDistinctBmkAges({
    String? customerId,
    String? hatcheryId,
    String? flockId,
  }) async => const [];
}

class _ControlledLabAnalysisRepository extends LabAnalysisRepository {
  _ControlledLabAnalysisRepository(this.summaries);

  final List<LabAnalysisDashboardSummary> summaries;
  final Completer<void> secondCallGate = Completer<void>();
  int calls = 0;
  int activeCalls = 0;
  int maxActiveCalls = 0;

  @override
  Future<List<LabAnalysisDashboardSummary>> getDashboardSummaries({
    String? customerId,
    String? flockId,
    int limit = 120,
  }) async {
    calls++;
    activeCalls++;
    if (activeCalls > maxActiveCalls) maxActiveCalls = activeCalls;
    try {
      if (calls == 2) await secondCallGate.future;
      return summaries;
    } finally {
      activeCalls--;
    }
  }
}

void main() {
  test(
    'background refresh preserves lab content and coalesces overlapping reloads',
    () async {
      final now = DateTime.utc(2026, 7, 21);
      final report = LabAnalysisReportModel(
        id: 'report-1',
        customerId: 'customer-1',
        flockId: 'flock-1',
        reportDate: now,
        labName: 'IDvet',
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
        groupLabel: 'House 1',
        analyte: 'Mycoplasma gallisepticum',
        gmtTiter: 11533,
        createdAt: now,
        updatedAt: now,
      );
      final summaries = [
        LabAnalysisDashboardSummary(
          report: report,
          group: group,
          rows: const [],
        ),
      ];
      final labRepository = _ControlledLabAnalysisRepository(summaries);
      final provider = DashboardProvider(
        customerRepository: _StaticCustomerRepository(),
        flockRepository: _StaticFlockRepository(),
        hatcheryRepository: _StaticHatcheryRepository(),
        panelDashboardRepository: _StaticPanelDashboardRepository(),
        labAnalysisRepository: labRepository,
      );
      addTearDown(provider.dispose);
      final user = UserModel(
        id: 'admin-1',
        fullName: 'Admin',
        email: 'admin@example.com',
        role: 'admin',
        status: 'approved',
        createdAt: now,
      );

      await provider.init(currentUser: user);
      expect(provider.labAnalysisSummaries, hasLength(1));
      expect(labRepository.calls, 1);

      final visibleCounts = <int>[];
      provider.addListener(() {
        visibleCounts.add(provider.labAnalysisSummaries.length);
      });

      final firstRefresh = provider.refresh();
      while (labRepository.calls < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(provider.isLoadingLabAnalysis, isTrue);
      expect(provider.labAnalysisSummaries, hasLength(1));

      final overlappingRefresh = provider.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(labRepository.calls, 2);
      expect(labRepository.maxActiveCalls, 1);

      labRepository.secondCallGate.complete();
      await Future.wait([firstRefresh, overlappingRefresh]);

      expect(labRepository.calls, 3);
      expect(labRepository.maxActiveCalls, 1);
      expect(provider.labAnalysisSummaries, hasLength(1));
      expect(visibleCounts, isNot(contains(0)));
    },
  );
}
