import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/broiler_daily_record_models.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/poultry_hierarchy_models.dart';
import 'package:hatchaudit/features/performance/models/broiler_performance_models.dart';
import 'package:hatchaudit/features/performance/providers/performance_provider.dart';

void main() {
  test(
    'customer farm and flock scope load an immutable workspace snapshot',
    () async {
      final source = _FakePerformanceDataSource();
      final provider = PerformanceProvider(dataSource: source);

      await provider.load();
      await provider.selectCustomer('customer-1');
      await provider.selectFarm('farm-1');
      await provider.selectFlock('flock-1');

      expect(provider.customers.single.name, 'Customer');
      expect(provider.farms.single.name, 'Farm');
      expect(provider.flocks.single.flockId, 'F-1');
      expect(provider.snapshot.metrics['age_day']!.value, 24);
      expect(provider.snapshot.targetSourceLabel, 'Ross 308 AP 2022');

      final firstSnapshot = provider.snapshot;
      await provider.setDateRange(
        DateTime.utc(2026, 7, 10),
        DateTime.utc(2026, 7, 24),
      );
      expect(source.snapshotLoads, 2);
      expect(provider.snapshot, isNot(same(firstSnapshot)));
    },
  );
}

class _FakePerformanceDataSource implements PerformanceWorkspaceDataSource {
  int snapshotLoads = 0;

  final customer = CustomerModel(
    id: 'customer-1',
    name: 'Customer',
    createdAt: DateTime.utc(2026, 1, 1),
    createdBy: 'test',
  );
  final farm = FarmModel(
    id: 'farm-1',
    customerId: 'customer-1',
    sector: PoultrySector.broiler,
    name: 'Farm',
  );
  final flock = FlockModel(
    id: 'flock-1',
    customerId: 'customer-1',
    flockId: 'F-1',
    breed: 'Ross 308 AP',
    entryDate: DateTime.utc(2026, 6, 30),
    farmId: 'farm-1',
    sector: PoultrySector.broiler,
  );

  @override
  Future<List<CustomerModel>> listBroilerCustomers() async => [customer];

  @override
  Future<List<FarmModel>> listBroilerFarms(String customerId) async => [farm];

  @override
  Future<List<FlockModel>> listBroilerFlocks(
    String customerId,
    String farmId,
  ) async => [flock];

  @override
  Future<PerformanceWorkspaceSnapshot> loadSnapshot({
    required FlockModel flock,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    snapshotLoads += 1;
    return PerformanceWorkspaceSnapshot(
      metrics: const {
        'age_day': PerformanceMetric(
          key: 'age_day',
          value: 24,
          unit: 'day',
          quality: PerformanceDataQuality.complete,
        ),
      },
      trendPoints: const [],
      concerns: const [],
      visits: const [],
      actions: const [],
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      verificationStatus: VerificationStatus.verified,
      reportedData: true,
      targetSourceLabel: 'Ross 308 AP 2022',
    );
  }
}
