import 'package:flutter/foundation.dart';

import '../../../data/models/broiler_daily_record_models.dart';
import '../../../data/models/broiler_target_models.dart';
import '../../../data/models/customer_model.dart';
import '../../../data/models/flock_model.dart';
import '../../../data/models/poultry_hierarchy_models.dart';
import '../../../data/repositories/broiler_daily_record_repository.dart';
import '../../../data/repositories/broiler_target_repository.dart';
import '../../../data/repositories/customer_repository.dart';
import '../../../data/repositories/flock_repository.dart';
import '../../../data/repositories/poultry_hierarchy_repository.dart';

class HouseDailyEntryState {
  const HouseDailyEntryState({
    required this.placement,
    required this.house,
    required this.flock,
    required this.recordDate,
    required this.draft,
    this.previous,
    this.current,
    this.target,
    this.validationErrors = const [],
  });

  final FlockPlacementModel placement;
  final HouseModel house;
  final FlockModel flock;
  final DateTime recordDate;
  final BroilerDailyRecordDraft draft;
  final SavedBroilerDailyRevision? previous;
  final SavedBroilerDailyRevision? current;
  final BroilerTargetRow? target;
  final List<String> validationErrors;

  int get ageDay {
    final start = DateTime.utc(
      flock.entryDate.year,
      flock.entryDate.month,
      flock.entryDate.day,
    );
    final end = DateTime.utc(recordDate.year, recordDate.month, recordDate.day);
    return end.difference(start).inDays;
  }

  int? get currentPopulation =>
      current?.revision.closingLiveBirdCount ??
      previous?.revision.closingLiveBirdCount;

  HouseDailyEntryState copyWith({
    BroilerDailyRecordDraft? draft,
    SavedBroilerDailyRevision? current,
    List<String>? validationErrors,
  }) {
    return HouseDailyEntryState(
      placement: placement,
      house: house,
      flock: flock,
      recordDate: recordDate,
      draft: draft ?? this.draft,
      previous: previous,
      current: current ?? this.current,
      target: target,
      validationErrors: validationErrors ?? this.validationErrors,
    );
  }

  factory HouseDailyEntryState.debug({
    required String placementId,
    required String houseId,
    required String houseName,
    required String flockId,
    required String flockCode,
    required String breed,
    required DateTime entryDate,
    required int placedBirds,
    required DateTime recordDate,
    int? previousMortality,
    double? targetWeightG,
  }) {
    final flock = FlockModel(
      id: flockId,
      customerId: 'debug-customer',
      flockId: flockCode,
      breed: breed,
      entryDate: entryDate,
      farmId: 'debug-farm',
      sector: PoultrySector.broiler,
    );
    final previous = previousMortality == null
        ? null
        : _debugSavedRevision(
            placementId: placementId,
            date: recordDate.subtract(const Duration(days: 1)),
            mortality: previousMortality,
          );
    return HouseDailyEntryState(
      placement: FlockPlacementModel(
        id: placementId,
        flockId: flockId,
        houseId: houseId,
        placedBirds: placedBirds,
        placedAt: entryDate,
      ),
      house: HouseModel(id: houseId, farmId: 'debug-farm', name: houseName),
      flock: flock,
      recordDate: recordDate,
      previous: previous,
      target: targetWeightG == null
          ? null
          : BroilerTargetRow(
              id: 'debug-target-$houseId',
              profileId: 'debug-target',
              ageDay: recordDate.difference(entryDate).inDays,
              bodyWeightG: targetWeightG,
            ),
      draft: BroilerDailyRecordDraft(
        placementId: placementId,
        recordDate: recordDate,
        verificationStatus: VerificationStatus.entered,
        enteredBy: 'debug',
        enteredAt: recordDate,
      ),
    );
  }
}

class DailyEntrySaveSummary {
  const DailyEntrySaveSummary({
    required this.savedPlacementIds,
    required this.errorsByPlacement,
  });

  final List<String> savedPlacementIds;
  final Map<String, List<String>> errorsByPlacement;

  bool get hasErrors => errorsByPlacement.isNotEmpty;
}

class BroilerDailyEntryProvider extends ChangeNotifier {
  BroilerDailyEntryProvider({
    CustomerRepository? customerRepository,
    FlockRepository? flockRepository,
    PoultryHierarchyRepository? hierarchyRepository,
    BroilerDailyRecordRepository? dailyRepository,
    BroilerTargetRepository? targetRepository,
  }) : _customerRepository = customerRepository ?? CustomerRepository(),
       _flockRepository = flockRepository ?? FlockRepository(),
       _hierarchyRepository =
           hierarchyRepository ?? PoultryHierarchyRepository(),
       _dailyRepository = dailyRepository ?? BroilerDailyRecordRepository(),
       _targetRepository = targetRepository ?? BroilerTargetRepository();

  BroilerDailyEntryProvider.debugWithEntries({
    required String enteredBy,
    required List<HouseDailyEntryState> entries,
  }) : _customerRepository = CustomerRepository(),
       _flockRepository = FlockRepository(),
       _hierarchyRepository = PoultryHierarchyRepository(),
       _dailyRepository = BroilerDailyRecordRepository(),
       _targetRepository = BroilerTargetRepository(),
       _enteredBy = enteredBy,
       _houseEntries = entries,
       _selectedDate = entries.isEmpty
           ? DateTime.now()
           : entries.first.recordDate;

  final CustomerRepository _customerRepository;
  final FlockRepository _flockRepository;
  final PoultryHierarchyRepository _hierarchyRepository;
  final BroilerDailyRecordRepository _dailyRepository;
  final BroilerTargetRepository _targetRepository;

  String _enteredBy = '';
  bool _isLoading = false;
  String? _error;
  List<CustomerModel> _customers = const [];
  List<FarmModel> _farms = const [];
  List<FlockModel> _flocks = const [];
  List<HouseDailyEntryState> _houseEntries = const [];
  String? _selectedCustomerId;
  String? _selectedFarmId;
  String? _selectedFlockId;
  DateTime _selectedDate = DateTime.now();
  DailyEntrySaveSummary? _lastSaveSummary;

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<CustomerModel> get customers => _customers;
  List<FarmModel> get farms => _farms;
  List<FlockModel> get flocks => _flocks;
  List<HouseDailyEntryState> get houseEntries => _houseEntries;
  String? get selectedCustomerId => _selectedCustomerId;
  String? get selectedFarmId => _selectedFarmId;
  String? get selectedFlockId => _selectedFlockId;
  DateTime get selectedDate => _selectedDate;
  DailyEntrySaveSummary? get lastSaveSummary => _lastSaveSummary;

  Future<void> load({required String enteredBy}) async {
    _enteredBy = enteredBy;
    await _runLoading(() async {
      final allCustomers = await _customerRepository.getAllCustomers();
      final eligible = <CustomerModel>[];
      for (final customer in allCustomers) {
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
      _customers = eligible;
      _farms = const [];
      _flocks = const [];
      _houseEntries = const [];
    });
  }

  Future<void> selectCustomer(String? customerId) async {
    _selectedCustomerId = customerId;
    _selectedFarmId = null;
    _selectedFlockId = null;
    _farms = const [];
    _flocks = const [];
    _houseEntries = const [];
    notifyListeners();
    if (customerId == null) return;
    await _runLoading(() async {
      _farms = await _hierarchyRepository.listFarms(
        customerId,
        sector: PoultrySector.broiler,
      );
    });
  }

  Future<void> selectFarm(String? farmId) async {
    _selectedFarmId = farmId;
    _selectedFlockId = null;
    _flocks = const [];
    _houseEntries = const [];
    notifyListeners();
    final customerId = _selectedCustomerId;
    if (farmId == null || customerId == null) return;
    await _runLoading(() async {
      final customerFlocks = await _flockRepository.getFlocksByCustomer(
        customerId,
      );
      _flocks =
          customerFlocks
              .where(
                (flock) =>
                    flock.farmId == farmId &&
                    flock.sector == PoultrySector.broiler &&
                    flock.isAvailableForAudit,
              )
              .toList()
            ..sort((left, right) => right.entryDate.compareTo(left.entryDate));
    });
  }

  Future<void> selectFlock(String? flockId) async {
    _selectedFlockId = flockId;
    _houseEntries = const [];
    notifyListeners();
    if (flockId == null) return;
    await _reloadHouseEntries();
  }

  void setDate(DateTime date) {
    _selectedDate = DateTime(date.year, date.month, date.day);
    if (_selectedFlockId != null) {
      _reloadHouseEntries();
    } else {
      notifyListeners();
    }
  }

  void updateDraft(String placementId, BroilerDailyRecordDraft draft) {
    _houseEntries = [
      for (final entry in _houseEntries)
        if (entry.placement.id == placementId)
          entry.copyWith(draft: draft, validationErrors: const [])
        else
          entry,
    ];
    _lastSaveSummary = null;
    notifyListeners();
  }

  Future<DailyEntrySaveSummary> saveValidDrafts() async {
    final saved = <String>[];
    final errors = <String, List<String>>{};
    final updated = <HouseDailyEntryState>[];
    for (final entry in _houseEntries) {
      if (!_hasEnteredFacts(entry.draft) && entry.current == null) {
        updated.add(entry);
        continue;
      }
      try {
        entry.draft.validate();
        final result = await _dailyRepository.saveRevision(entry.draft);
        saved.add(entry.placement.id);
        updated.add(
          entry.copyWith(
            current: result,
            draft: result.revision.facts.copyWith(recordId: result.record.id),
            validationErrors: const [],
          ),
        );
      } on DailyRecordValidationException catch (error) {
        errors[entry.placement.id] = error.errors;
        updated.add(entry.copyWith(validationErrors: error.errors));
      } catch (error) {
        final messages = [error.toString()];
        errors[entry.placement.id] = messages;
        updated.add(entry.copyWith(validationErrors: messages));
      }
    }
    _houseEntries = updated;
    final summary = DailyEntrySaveSummary(
      savedPlacementIds: List.unmodifiable(saved),
      errorsByPlacement: Map.unmodifiable(errors),
    );
    _lastSaveSummary = summary;
    notifyListeners();
    return summary;
  }

  Future<void> _reloadHouseEntries() async {
    final flockId = _selectedFlockId;
    final farmId = _selectedFarmId;
    if (flockId == null || farmId == null) return;
    await _runLoading(() async {
      final flock = _flocks.firstWhere((candidate) => candidate.id == flockId);
      final placements = await _hierarchyRepository.listPlacements(
        flockId,
        activeOnly: true,
      );
      final houses = {
        for (final house in await _hierarchyRepository.listHouses(farmId))
          house.id: house,
      };
      final ageDay = _calendarDays(flock.entryDate, _selectedDate);
      final target = flock.targetProfileId == null
          ? null
          : await _targetRepository.getRow(flock.targetProfileId!, ageDay);
      final entries = <HouseDailyEntryState>[];
      for (final placement in placements) {
        final house = houses[placement.houseId];
        if (house == null) continue;
        final current = await _dailyRepository.getCurrentForPlacementDate(
          placement.id,
          _selectedDate,
        );
        final previous = await _dailyRepository.getPreviousDay(
          placement.id,
          _selectedDate,
        );
        final draft = current == null
            ? BroilerDailyRecordDraft(
                placementId: placement.id,
                recordDate: _selectedDate,
                verificationStatus: VerificationStatus.entered,
                enteredBy: _enteredBy,
                enteredAt: DateTime.now().toUtc(),
              )
            : current.revision.facts.copyWith(
                recordId: current.record.id,
                enteredBy: _enteredBy,
                enteredAt: DateTime.now().toUtc(),
                sources: [
                  for (final source in current.sources)
                    DailyRecordSourceDraft(
                      sourceKind: source.sourceKind,
                      localPath: source.localPath,
                      remoteStoragePath: source.remoteStoragePath,
                      originalFilename: source.originalFilename,
                      checksum: source.checksum,
                      uploadState: source.uploadState,
                      uploadError: source.uploadError,
                    ),
                ],
                events: [
                  for (final event in current.events)
                    BroilerDailyEventDraft(
                      eventType: event.eventType,
                      eventAt: event.eventAt,
                      isAllDay: event.isAllDay,
                      eventState: event.eventState,
                      description: event.description,
                      treatment: event.treatment,
                      vaccination: event.vaccination,
                      feedPhase: event.feedPhase,
                      equipment: event.equipment,
                    ),
                ],
              );
        entries.add(
          HouseDailyEntryState(
            placement: placement,
            house: house,
            flock: flock,
            recordDate: _selectedDate,
            draft: draft,
            previous: previous,
            current: current,
            target: target,
          ),
        );
      }
      _houseEntries = entries;
    });
  }

  Future<void> _runLoading(Future<void> Function() action) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  bool _hasEnteredFacts(BroilerDailyRecordDraft draft) {
    return draft.openingBirdCount != null ||
        draft.dailyMortality != null ||
        draft.dailyCulls != null ||
        draft.closingLiveBirdCount != null ||
        draft.dailyFeedConsumedKg != null ||
        draft.waterConsumedLiters != null ||
        draft.averageBodyWeightG != null ||
        draft.sources.isNotEmpty ||
        draft.events.isNotEmpty;
  }
}

int _calendarDays(DateTime start, DateTime end) {
  final first = DateTime.utc(start.year, start.month, start.day);
  final last = DateTime.utc(end.year, end.month, end.day);
  return last.difference(first).inDays;
}

SavedBroilerDailyRevision _debugSavedRevision({
  required String placementId,
  required DateTime date,
  required int mortality,
}) {
  final draft = BroilerDailyRecordDraft(
    placementId: placementId,
    recordDate: date,
    verificationStatus: VerificationStatus.entered,
    enteredBy: 'debug',
    enteredAt: date,
    dailyMortality: mortality,
  );
  final record = BroilerDailyRecord(
    id: 'debug-record-$placementId-${dateKey(date)}',
    placementId: placementId,
    recordDate: date,
    verificationStatus: VerificationStatus.entered,
    currentRevisionId: 'debug-revision-$placementId-${dateKey(date)}',
  );
  return SavedBroilerDailyRevision(
    record: record,
    revision: BroilerDailyRevision(
      id: record.currentRevisionId!,
      recordId: record.id,
      revisionNumber: 1,
      facts: draft,
      createdAt: date,
    ),
  );
}
