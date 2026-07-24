import 'package:flutter/foundation.dart';

import '../../../data/models/broiler_daily_record_models.dart';
import '../../../data/models/broiler_target_models.dart';
import '../../../data/models/corrective_action_models.dart';
import '../../../data/models/customer_model.dart';
import '../../../data/models/farm_visit_models.dart';
import '../../../data/models/flock_model.dart';
import '../../../data/models/performance_concern_models.dart';
import '../../../data/models/poultry_hierarchy_models.dart';
import '../../../data/repositories/broiler_daily_record_repository.dart';
import '../../../data/repositories/broiler_target_repository.dart';
import '../../../data/repositories/corrective_action_repository.dart';
import '../../../data/repositories/customer_repository.dart';
import '../../../data/repositories/farm_visit_repository.dart';
import '../../../data/repositories/flock_repository.dart';
import '../../../data/repositories/performance_concern_repository.dart';
import '../../../data/repositories/poultry_hierarchy_repository.dart';
import '../models/broiler_performance_models.dart';
import '../services/broiler_kpi_calculator.dart';

class PerformanceTrendPoint {
  const PerformanceTrendPoint({required this.date, required this.values});

  final DateTime date;
  final Map<String, double?> values;
}

class PerformanceWorkspaceSnapshot {
  const PerformanceWorkspaceSnapshot({
    required this.metrics,
    required this.trendPoints,
    required this.concerns,
    required this.visits,
    required this.actions,
    required this.rangeStart,
    required this.rangeEnd,
    required this.verificationStatus,
    required this.reportedData,
    this.targetSourceLabel,
  });

  final Map<String, PerformanceMetric> metrics;
  final List<PerformanceTrendPoint> trendPoints;
  final List<PerformanceConcern> concerns;
  final List<FarmVisitSession> visits;
  final List<CorrectiveAction> actions;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final VerificationStatus verificationStatus;
  final bool reportedData;
  final String? targetSourceLabel;

  static PerformanceWorkspaceSnapshot empty({
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) {
    return PerformanceWorkspaceSnapshot(
      metrics: const {},
      trendPoints: const [],
      concerns: const [],
      visits: const [],
      actions: const [],
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      verificationStatus: VerificationStatus.pendingEntry,
      reportedData: false,
    );
  }
}

abstract class PerformanceWorkspaceDataSource {
  Future<List<CustomerModel>> listBroilerCustomers();

  Future<List<FarmModel>> listBroilerFarms(String customerId);

  Future<List<FlockModel>> listBroilerFlocks(String customerId, String farmId);

  Future<PerformanceWorkspaceSnapshot> loadSnapshot({
    required FlockModel flock,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  });
}

class SqlitePerformanceWorkspaceDataSource
    implements PerformanceWorkspaceDataSource {
  SqlitePerformanceWorkspaceDataSource({
    CustomerRepository? customerRepository,
    FlockRepository? flockRepository,
    PoultryHierarchyRepository? hierarchyRepository,
    BroilerDailyRecordRepository? dailyRepository,
    BroilerTargetRepository? targetRepository,
    PerformanceConcernRepository? concernRepository,
    FarmVisitRepository? visitRepository,
    CorrectiveActionRepository? actionRepository,
    BroilerKpiCalculator calculator = const BroilerKpiCalculator(),
  }) : _customerRepository = customerRepository ?? CustomerRepository(),
       _flockRepository = flockRepository ?? FlockRepository(),
       _hierarchyRepository =
           hierarchyRepository ?? PoultryHierarchyRepository(),
       _dailyRepository = dailyRepository ?? BroilerDailyRecordRepository(),
       _targetRepository = targetRepository ?? BroilerTargetRepository(),
       _concernRepository = concernRepository ?? PerformanceConcernRepository(),
       _visitRepository = visitRepository ?? FarmVisitRepository(),
       _actionRepository = actionRepository ?? CorrectiveActionRepository(),
       _calculator = calculator;

  final CustomerRepository _customerRepository;
  final FlockRepository _flockRepository;
  final PoultryHierarchyRepository _hierarchyRepository;
  final BroilerDailyRecordRepository _dailyRepository;
  final BroilerTargetRepository _targetRepository;
  final PerformanceConcernRepository _concernRepository;
  final FarmVisitRepository _visitRepository;
  final CorrectiveActionRepository _actionRepository;
  final BroilerKpiCalculator _calculator;

  @override
  Future<List<CustomerModel>> listBroilerCustomers() async {
    final customers = await _customerRepository.getAllCustomers();
    final eligible = <CustomerModel>[];
    for (final customer in customers) {
      final sectors = await _hierarchyRepository.listCustomerSectors(
        customer.id,
      );
      if (sectors.any(
        (membership) =>
            membership.sector == PoultrySector.broiler && membership.isActive,
      )) {
        eligible.add(customer);
      }
    }
    eligible.sort((left, right) => left.name.compareTo(right.name));
    return eligible;
  }

  @override
  Future<List<FarmModel>> listBroilerFarms(String customerId) {
    return _hierarchyRepository.listFarms(
      customerId,
      sector: PoultrySector.broiler,
    );
  }

  @override
  Future<List<FlockModel>> listBroilerFlocks(
    String customerId,
    String farmId,
  ) async {
    final flocks = await _flockRepository.getFlocksByCustomer(customerId);
    return flocks
        .where(
          (flock) =>
              flock.farmId == farmId && flock.sector == PoultrySector.broiler,
        )
        .toList()
      ..sort((left, right) => right.entryDate.compareTo(left.entryDate));
  }

  @override
  Future<PerformanceWorkspaceSnapshot> loadSnapshot({
    required FlockModel flock,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    final records = await _dailyRepository.listCurrentForFlock(
      flock.id,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
    );
    final placements = await _hierarchyRepository.listPlacements(flock.id);
    final days = _aggregateDays(records);
    final targetContext = await _loadTargetContext(flock, days);
    final input = BroilerPerformanceInput(
      entryDate: flock.entryDate,
      placedBirds: placements.fold(
        0,
        (total, placement) => total + placement.placedBirds,
      ),
      days: days,
      targets: targetContext.targets,
      cycleCompleted: flock.isSold,
    );
    final result = _calculator.calculate(input);
    final concerns = await _concernRepository.listConcerns(
      customerId: flock.customerId,
      farmId: flock.farmId,
      flockId: flock.id,
    );
    final visits = flock.farmId == null
        ? const <FarmVisitSession>[]
        : await _visitRepository.listVisits(
            customerId: flock.customerId,
            farmId: flock.farmId,
            flockId: flock.id,
          );
    final actions = <CorrectiveAction>[];
    for (final concern in concerns) {
      actions.addAll(await _actionRepository.listForConcern(concern.id));
    }

    return PerformanceWorkspaceSnapshot(
      metrics: Map.unmodifiable(result.metrics),
      trendPoints: List.unmodifiable(_buildTrends(input)),
      concerns: List.unmodifiable(concerns),
      visits: List.unmodifiable(visits),
      actions: List.unmodifiable(actions),
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      verificationStatus: _verificationStatus(records),
      reportedData: records.any(
        (saved) =>
            saved.revision.facts.reportedBy?.trim().isNotEmpty == true ||
            saved.revision.facts.dataSourceType != DailyDataSourceType.manual,
      ),
      targetSourceLabel: targetContext.sourceLabel,
    );
  }

  Future<_TargetContext> _loadTargetContext(
    FlockModel flock,
    List<BroilerPerformanceDay> days,
  ) async {
    await _targetRepository.ensureOfficialCatalogueSeeded();
    final profiles = await _targetRepository.listProfiles(
      breed: flock.breed,
      sexProfile: flock.sexProfile,
      activeOnly: true,
    );
    BroilerTargetProfile? profile;
    if (flock.targetProfileId != null) {
      final all = await _targetRepository.listProfiles();
      for (final candidate in all) {
        if (candidate.id == flock.targetProfileId) {
          profile = candidate;
          break;
        }
      }
    }
    profile ??= profiles.isEmpty ? null : profiles.first;
    if (profile == null) return const _TargetContext();

    final ages = days
        .map((day) => _calendarDays(flock.entryDate, day.recordDate))
        .toSet();
    final targets = <BroilerPerformanceTargetDay>[];
    for (final age in ages) {
      final row = await _targetRepository.getRow(profile.id, age);
      if (row != null) {
        targets.add(
          BroilerPerformanceTargetDay(
            ageDay: row.ageDay,
            bodyWeightG: row.bodyWeightG,
            dailyFeedIntakeGPerLivingBird: row.dailyFeedIntakeGPerLivingBird,
            fcr: row.fcr,
          ),
        );
      }
    }
    return _TargetContext(
      targets: targets,
      sourceLabel: '${profile.sourceTitle} · ${profile.publicationVersion}',
    );
  }

  List<BroilerPerformanceDay> _aggregateDays(
    List<SavedBroilerDailyRevision> records,
  ) {
    final grouped = <String, List<BroilerDailyRecordDraft>>{};
    for (final saved in records) {
      grouped
          .putIfAbsent(dateKey(saved.record.recordDate), () => [])
          .add(saved.revision.facts);
    }
    final days = <BroilerPerformanceDay>[];
    for (final entry in grouped.entries) {
      final facts = entry.value;
      final weights = facts
          .expand((fact) => fact.individualWeightsG)
          .toList(growable: false);
      days.add(
        BroilerPerformanceDay(
          recordDate: DateTime.parse(entry.key),
          openingBirds: _sumInts(facts.map((fact) => fact.openingBirdCount)),
          closingBirds: _sumInts(
            facts.map((fact) => fact.closingLiveBirdCount),
          ),
          mortality: _sumInts(facts.map((fact) => fact.dailyMortality)),
          culls: _sumInts(facts.map((fact) => fact.dailyCulls)),
          feedConsumedKg: _sumDoubles(
            facts.map((fact) => fact.dailyFeedConsumedKg),
          ),
          waterConsumedLiters: _sumDoubles(
            facts.map((fact) => fact.waterConsumedLiters),
          ),
          averageBodyWeightG: _weightedAverage(
            facts,
            (fact) => fact.averageBodyWeightG,
            (fact) => fact.birdsWeighed,
          ),
          uniformityPct: _average(facts.map((fact) => fact.uniformityPct)),
          cvPct: _average(facts.map((fact) => fact.cvPct)),
          individualWeightsG: weights,
        ),
      );
    }
    days.sort((left, right) => left.recordDate.compareTo(right.recordDate));
    return days;
  }

  List<PerformanceTrendPoint> _buildTrends(BroilerPerformanceInput input) {
    final points = <PerformanceTrendPoint>[];
    for (var index = 0; index < input.days.length; index += 1) {
      final prefix = input.days.sublist(0, index + 1);
      final result = _calculator.calculate(input.copyWith(days: prefix));
      final day = prefix.last;
      points.add(
        PerformanceTrendPoint(
          date: day.recordDate,
          values: Map.unmodifiable({
            'daily_mortality_pct': result.dailyMortalityPct,
            'cumulative_mortality_pct': result.cumulativeMortalityPct,
            'feed_kg': day.feedConsumedKg,
            'water_l': day.waterConsumedLiters,
            'weight_g': day.averageBodyWeightG,
            'uniformity_pct': result.uniformityPct,
            'fcr': result.fcr,
          }),
        ),
      );
    }
    return points;
  }

  VerificationStatus _verificationStatus(
    List<SavedBroilerDailyRevision> records,
  ) {
    if (records.isEmpty) return VerificationStatus.pendingEntry;
    final latestDate = records
        .map((saved) => saved.record.recordDate)
        .reduce((left, right) => left.isAfter(right) ? left : right);
    final latest = records
        .where(
          (saved) => dateKey(saved.record.recordDate) == dateKey(latestDate),
        )
        .map((saved) => saved.revision.verificationStatus)
        .toList();
    if (latest.every((status) => status == VerificationStatus.verified)) {
      return VerificationStatus.verified;
    }
    if (latest.contains(VerificationStatus.requiresClarification)) {
      return VerificationStatus.requiresClarification;
    }
    if (latest.contains(VerificationStatus.corrected)) {
      return VerificationStatus.corrected;
    }
    if (latest.contains(VerificationStatus.reviewed)) {
      return VerificationStatus.reviewed;
    }
    return VerificationStatus.entered;
  }
}

class PerformanceProvider extends ChangeNotifier {
  PerformanceProvider({PerformanceWorkspaceDataSource? dataSource})
    : _dataSource = dataSource ?? SqlitePerformanceWorkspaceDataSource(),
      _rangeEnd = _dateOnly(DateTime.now()),
      _rangeStart = _dateOnly(
        DateTime.now().subtract(const Duration(days: 13)),
      ) {
    _snapshot = PerformanceWorkspaceSnapshot.empty(
      rangeStart: _rangeStart,
      rangeEnd: _rangeEnd,
    );
  }

  PerformanceProvider.debug({required PerformanceWorkspaceSnapshot snapshot})
    : _dataSource = const _EmptyPerformanceWorkspaceDataSource(),
      _rangeStart = snapshot.rangeStart,
      _rangeEnd = snapshot.rangeEnd,
      _snapshot = snapshot;

  final PerformanceWorkspaceDataSource _dataSource;
  late DateTime _rangeStart;
  late DateTime _rangeEnd;
  late PerformanceWorkspaceSnapshot _snapshot;
  List<CustomerModel> _customers = const [];
  List<FarmModel> _farms = const [];
  List<FlockModel> _flocks = const [];
  String? _selectedCustomerId;
  String? _selectedFarmId;
  String? _selectedFlockId;
  bool _isLoading = false;
  String? _error;

  List<CustomerModel> get customers => _customers;
  List<FarmModel> get farms => _farms;
  List<FlockModel> get flocks => _flocks;
  String? get selectedCustomerId => _selectedCustomerId;
  String? get selectedFarmId => _selectedFarmId;
  String? get selectedFlockId => _selectedFlockId;
  DateTime get rangeStart => _rangeStart;
  DateTime get rangeEnd => _rangeEnd;
  PerformanceWorkspaceSnapshot get snapshot => _snapshot;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> load() async {
    await _runLoading(() async {
      _customers = await _dataSource.listBroilerCustomers();
      _farms = const [];
      _flocks = const [];
      _selectedCustomerId = null;
      _selectedFarmId = null;
      _selectedFlockId = null;
      _resetSnapshot();
    });
  }

  Future<void> selectCustomer(String? customerId) async {
    _selectedCustomerId = customerId;
    _selectedFarmId = null;
    _selectedFlockId = null;
    _farms = const [];
    _flocks = const [];
    _resetSnapshot();
    notifyListeners();
    if (customerId == null) return;
    await _runLoading(() async {
      _farms = await _dataSource.listBroilerFarms(customerId);
    });
  }

  Future<void> selectFarm(String? farmId) async {
    _selectedFarmId = farmId;
    _selectedFlockId = null;
    _flocks = const [];
    _resetSnapshot();
    notifyListeners();
    if (farmId == null || _selectedCustomerId == null) return;
    await _runLoading(() async {
      _flocks = await _dataSource.listBroilerFlocks(
        _selectedCustomerId!,
        farmId,
      );
    });
  }

  Future<void> selectFlock(String? flockId) async {
    _selectedFlockId = flockId;
    _resetSnapshot();
    notifyListeners();
    if (flockId == null) return;
    await refresh();
  }

  Future<void> setDateRange(DateTime start, DateTime end) async {
    final normalizedStart = _dateOnly(start);
    final normalizedEnd = _dateOnly(end);
    if (normalizedEnd.isBefore(normalizedStart)) {
      throw ArgumentError('Date range end must not precede its start');
    }
    _rangeStart = normalizedStart;
    _rangeEnd = normalizedEnd;
    if (_selectedFlockId == null) {
      _resetSnapshot();
      notifyListeners();
      return;
    }
    await refresh();
  }

  Future<void> refresh() async {
    final flock = _selectedFlock();
    if (flock == null) return;
    await _runLoading(() async {
      _snapshot = await _dataSource.loadSnapshot(
        flock: flock,
        rangeStart: _rangeStart,
        rangeEnd: _rangeEnd,
      );
    });
  }

  FlockModel? _selectedFlock() {
    for (final flock in _flocks) {
      if (flock.id == _selectedFlockId) return flock;
    }
    return null;
  }

  void _resetSnapshot() {
    _snapshot = PerformanceWorkspaceSnapshot.empty(
      rangeStart: _rangeStart,
      rangeEnd: _rangeEnd,
    );
  }

  Future<void> _runLoading(Future<void> Function() operation) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await operation();
    } catch (error) {
      _error = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}

class _TargetContext {
  const _TargetContext({this.targets = const [], this.sourceLabel});

  final List<BroilerPerformanceTargetDay> targets;
  final String? sourceLabel;
}

class _EmptyPerformanceWorkspaceDataSource
    implements PerformanceWorkspaceDataSource {
  const _EmptyPerformanceWorkspaceDataSource();

  @override
  Future<List<CustomerModel>> listBroilerCustomers() async => const [];

  @override
  Future<List<FarmModel>> listBroilerFarms(String customerId) async => const [];

  @override
  Future<List<FlockModel>> listBroilerFlocks(
    String customerId,
    String farmId,
  ) async => const [];

  @override
  Future<PerformanceWorkspaceSnapshot> loadSnapshot({
    required FlockModel flock,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async => PerformanceWorkspaceSnapshot.empty(
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
  );
}

int _calendarDays(DateTime start, DateTime end) {
  final startDay = DateTime.utc(start.year, start.month, start.day);
  final endDay = DateTime.utc(end.year, end.month, end.day);
  return endDay.difference(startDay).inDays;
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

int? _sumInts(Iterable<int?> values) {
  var total = 0;
  var hasValue = false;
  for (final value in values) {
    if (value == null) return null;
    total += value;
    hasValue = true;
  }
  return hasValue ? total : null;
}

double? _sumDoubles(Iterable<double?> values) {
  var total = 0.0;
  var hasValue = false;
  for (final value in values) {
    if (value == null) return null;
    total += value;
    hasValue = true;
  }
  return hasValue ? total : null;
}

double? _average(Iterable<double?> values) {
  final available = values.whereType<double>().toList();
  if (available.isEmpty) return null;
  return available.reduce((left, right) => left + right) / available.length;
}

double? _weightedAverage(
  List<BroilerDailyRecordDraft> values,
  double? Function(BroilerDailyRecordDraft) valueOf,
  int? Function(BroilerDailyRecordDraft) weightOf,
) {
  var weightedTotal = 0.0;
  var weightTotal = 0;
  final unweighted = <double>[];
  for (final item in values) {
    final value = valueOf(item);
    if (value == null) continue;
    unweighted.add(value);
    final weight = weightOf(item);
    if (weight != null && weight > 0) {
      weightedTotal += value * weight;
      weightTotal += weight;
    }
  }
  if (weightTotal > 0) return weightedTotal / weightTotal;
  if (unweighted.isEmpty) return null;
  return unweighted.reduce((left, right) => left + right) / unweighted.length;
}
