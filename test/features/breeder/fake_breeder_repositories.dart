import 'package:hatchaudit/data/models/breeder_alert_models.dart';
import 'package:hatchaudit/data/models/breeder_bird_movement_model.dart';
import 'package:hatchaudit/data/models/breeder_daily_report_model.dart';
import 'package:hatchaudit/data/models/breeder_benchmark_models.dart';
import 'package:hatchaudit/data/models/breeder_egg_grade_definition_model.dart';
import 'package:hatchaudit/data/models/breeder_egg_inventory_movement_model.dart';
import 'package:hatchaudit/data/models/breeder_egg_production_entry_model.dart';
import 'package:hatchaudit/data/models/breeder_feed_entry_model.dart';
import 'package:hatchaudit/data/models/breeder_isolation_area_model.dart';
import 'package:hatchaudit/data/models/breeder_report_revision_model.dart';
import 'package:hatchaudit/data/models/breeder_weighing_session_model.dart';
import 'package:hatchaudit/data/models/egg_batch_model.dart';
import 'package:hatchaudit/data/models/egg_shipment_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/hatchery_model.dart';
import 'package:hatchaudit/data/models/poultry_hierarchy_models.dart';
import 'package:hatchaudit/data/models/breeder_flock_milestone_model.dart';
import 'package:hatchaudit/data/repositories/breeder_alert_rule_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_performance_alert_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_benchmark_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_bird_movement_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_flock_milestone_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_daily_report_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_egg_grade_definition_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_egg_inventory_movement_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_egg_production_entry_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_feed_entry_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_isolation_area_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_report_revision_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_weighing_sample_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_weighing_session_repository.dart';
import 'package:hatchaudit/data/repositories/egg_batch_repository.dart';
import 'package:hatchaudit/data/repositories/egg_shipment_repository.dart';
import 'package:hatchaudit/data/repositories/flock_repository.dart';
import 'package:hatchaudit/data/repositories/hatchery_repository.dart';
import 'package:hatchaudit/data/repositories/poultry_hierarchy_repository.dart';
import 'package:hatchaudit/data/database/seeds/breeder_egg_grade_definition_seeds.dart';

/// In-memory fakes for the breeder daily-report widget tests
/// (breeder-flock-performance ticket 07; extended by ticket 08 for
/// isolation areas). `testWidgets` hangs against real sqflite (see
/// repo-wide note in AGENTS.md/CLAUDE.md history), so entry and review
/// screen widget tests inject these instead of the real database-backed
/// repositories.
class FakeBreederDailyReportRepository extends BreederDailyReportRepository {
  final Map<String, BreederDailyReport> _byId = {};

  @override
  Future<BreederDailyReport> createDraft({
    required String flockId,
    required DateTime reportDate,
    double? insideTemperature,
    double? outsideTemperature,
    double? lightHours,
    String? notes,
    String? createdBy,
  }) async {
    final existing = await getByFlockAndDate(flockId, reportDate);
    if (existing != null) {
      throw StateError('A report already exists for this flock and date');
    }
    final report = BreederDailyReport(
      id: 'report-${_byId.length + 1}',
      flockId: flockId,
      reportDate: reportDate,
      insideTemperature: insideTemperature,
      outsideTemperature: outsideTemperature,
      lightHours: lightHours,
      notes: notes,
      createdBy: createdBy,
    );
    _byId[report.id] = report;
    return report;
  }

  void seed(BreederDailyReport report) {
    _byId[report.id] = report;
  }

  @override
  Future<BreederDailyReport?> getById(String id) async => _byId[id];

  @override
  Future<BreederDailyReport?> getByFlockAndDate(
    String flockId,
    DateTime reportDate,
  ) async {
    final key = BreederDailyReport.dateKey(reportDate);
    for (final report in _byId.values) {
      if (report.flockId == flockId && report.reportDateKey == key) {
        return report;
      }
    }
    return null;
  }

  @override
  Future<List<BreederDailyReport>> listForFlock(String flockId) async {
    final reports = _byId.values.where((r) => r.flockId == flockId).toList()
      ..sort((a, b) => b.reportDate.compareTo(a.reportDate));
    return reports;
  }

  @override
  Future<void> updateHeader(BreederDailyReport report) async {
    _byId[report.id] = report;
  }

  @override
  Future<BreederDailyReport> bumpRevision(BreederDailyReport report) async {
    final updated = report.copyWith(revision: report.revision + 1);
    _byId[report.id] = updated;
    return updated;
  }

  @override
  Future<BreederDailyReport> applyTransition(
    BreederDailyReport report, {
    required String newState,
    String? submittedBy,
    DateTime? submittedAt,
    String? approvedBy,
    DateTime? approvedAt,
    int? eggProductionDenominatorFemales,
    String? benchmarkProfileVersionAtApproval,
    String? comparisonAxisAtApproval,
  }) async {
    final updated = report.copyWith(
      state: newState,
      revision: report.revision + 1,
      submittedBy: submittedBy ?? report.submittedBy,
      submittedAt: submittedAt ?? report.submittedAt,
      approvedBy: approvedBy ?? report.approvedBy,
      approvedAt: approvedAt ?? report.approvedAt,
      eggProductionDenominatorFemales:
          eggProductionDenominatorFemales ??
          report.eggProductionDenominatorFemales,
      benchmarkProfileVersionAtApproval:
          benchmarkProfileVersionAtApproval ??
          report.benchmarkProfileVersionAtApproval,
      comparisonAxisAtApproval:
          comparisonAxisAtApproval ?? report.comparisonAxisAtApproval,
    );
    _byId[report.id] = updated;
    return updated;
  }
}

class FakeBreederBirdMovementRepository extends BreederBirdMovementRepository {
  FakeBreederBirdMovementRepository(this._reportRepository);

  final FakeBreederDailyReportRepository _reportRepository;
  final Map<String, BreederBirdMovement> _byId = {};
  int _idCounter = 0;

  @override
  Future<List<BreederBirdMovement>> getForReport(String reportId) async {
    return _byId.values.where((m) => m.reportId == reportId).toList()
      ..sort((a, b) => a.locationId.compareTo(b.locationId));
  }

  @override
  Future<BreederBirdMovement?> getById(String id) async => _byId[id];

  @override
  Future<BreederBirdMovement?> getByReportHouseSex(
    String reportId,
    String houseId,
    String sex,
  ) async {
    for (final movement in _byId.values) {
      if (movement.reportId == reportId &&
          movement.houseId == houseId &&
          movement.sex == sex) {
        return movement;
      }
    }
    return null;
  }

  @override
  Future<BreederBirdMovement?> getByReportIsolationAreaSex(
    String reportId,
    String isolationAreaId,
    String sex,
  ) async {
    for (final movement in _byId.values) {
      if (movement.reportId == reportId &&
          movement.isolationAreaId == isolationAreaId &&
          movement.sex == sex) {
        return movement;
      }
    }
    return null;
  }

  @override
  Future<BreederBirdMovement> upsert(BreederBirdMovement movement) async {
    final existing = movement.isHouseMovement
        ? await getByReportHouseSex(
            movement.reportId,
            movement.houseId!,
            movement.sex,
          )
        : await getByReportIsolationAreaSex(
            movement.reportId,
            movement.isolationAreaId!,
            movement.sex,
          );
    if (existing == null) {
      _idCounter += 1;
      final toInsert = movement.copyWith(id: 'movement-$_idCounter');
      _byId[toInsert.id] = toInsert;
      return toInsert;
    }
    final updated = movement.copyWith(id: existing.id);
    _byId[existing.id] = updated;
    return updated;
  }

  @override
  Future<int?> previousClosing({
    required String flockId,
    required String houseId,
    required String sex,
    required DateTime beforeDate,
  }) async {
    BreederBirdMovement? latest;
    DateTime? latestDate;
    for (final movement in _byId.values) {
      if (movement.houseId != houseId || movement.sex != sex) continue;
      final report = await _reportRepository.getById(movement.reportId);
      if (report == null || report.flockId != flockId) continue;
      final date = report.reportDate;
      if (!date.isBefore(beforeDate)) continue;
      if (latestDate == null || date.isAfter(latestDate)) {
        latestDate = date;
        latest = movement;
      }
    }
    return latest?.closing;
  }

  @override
  Future<int?> previousClosingForIsolationArea({
    required String flockId,
    required String isolationAreaId,
    required String sex,
    required DateTime beforeDate,
  }) async {
    BreederBirdMovement? latest;
    DateTime? latestDate;
    for (final movement in _byId.values) {
      if (movement.isolationAreaId != isolationAreaId ||
          movement.sex != sex) {
        continue;
      }
      final report = await _reportRepository.getById(movement.reportId);
      if (report == null || report.flockId != flockId) continue;
      final date = report.reportDate;
      if (!date.isBefore(beforeDate)) continue;
      if (latestDate == null || date.isAfter(latestDate)) {
        latestDate = date;
        latest = movement;
      }
    }
    return latest?.closing;
  }
}

class FakeBreederFeedEntryRepository extends BreederFeedEntryRepository {
  final Map<String, BreederFeedEntry> _byId = {};
  int _idCounter = 0;

  @override
  Future<List<BreederFeedEntry>> getForReport(String reportId) async {
    return _byId.values.where((e) => e.reportId == reportId).toList()
      ..sort((a, b) => a.locationId.compareTo(b.locationId));
  }

  @override
  Future<BreederFeedEntry?> getById(String id) async => _byId[id];

  @override
  Future<BreederFeedEntry?> getByReportHouseSex(
    String reportId,
    String houseId,
    String sex,
  ) async {
    for (final entry in _byId.values) {
      if (entry.reportId == reportId &&
          entry.houseId == houseId &&
          entry.sex == sex) {
        return entry;
      }
    }
    return null;
  }

  @override
  Future<BreederFeedEntry?> getByReportIsolationAreaSex(
    String reportId,
    String isolationAreaId,
    String sex,
  ) async {
    for (final entry in _byId.values) {
      if (entry.reportId == reportId &&
          entry.isolationAreaId == isolationAreaId &&
          entry.sex == sex) {
        return entry;
      }
    }
    return null;
  }

  @override
  Future<BreederFeedEntry> upsert(BreederFeedEntry entry) async {
    final existing = entry.isHouseEntry
        ? await getByReportHouseSex(entry.reportId, entry.houseId!, entry.sex)
        : await getByReportIsolationAreaSex(
            entry.reportId,
            entry.isolationAreaId!,
            entry.sex,
          );
    if (existing == null) {
      _idCounter += 1;
      final toInsert = entry.copyWith(id: 'feed-$_idCounter');
      _byId[toInsert.id] = toInsert;
      return toInsert;
    }
    final updated = entry.copyWith(id: existing.id);
    _byId[existing.id] = updated;
    return updated;
  }
}

class FakeHouseRepository extends PoultryHierarchyRepository {
  final List<HouseModel> houses;

  FakeHouseRepository(this.houses);

  @override
  Future<List<HouseModel>> listHouses(
    String flockId, {
    bool activeOnly = true,
  }) async {
    return houses.where((h) => h.flockId == flockId).toList();
  }

  @override
  Future<void> saveHouse(HouseModel house) async {
    houses
      ..removeWhere((h) => h.id == house.id)
      ..add(house);
  }
}

class FakeIsolationAreaRepository extends BreederIsolationAreaRepository {
  final List<BreederIsolationArea> areas;

  FakeIsolationAreaRepository(this.areas);

  @override
  Future<List<BreederIsolationArea>> listAreas(
    String flockId, {
    bool activeOnly = true,
  }) async {
    return areas.where((a) => a.flockId == flockId).toList();
  }

  @override
  Future<BreederIsolationArea?> getById(String id) async {
    for (final area in areas) {
      if (area.id == id) return area;
    }
    return null;
  }

  @override
  Future<BreederIsolationArea> saveArea(BreederIsolationArea area) async {
    areas
      ..removeWhere((a) => a.id == area.id)
      ..add(area);
    return area;
  }
}

/// Fake benchmark repository (breeder-flock-performance ticket 06,
/// extended by ticket 10). Returns no active profile by default — the
/// pre-production behaviour every earlier ticket's widget tests rely on
/// (`BreederFlockLifecycleService.hasEnteredProductionRange` reads false
/// with no profile). Ticket 10's egg-section widget tests set
/// [inProduction] to exercise the "flock has entered production" path
/// without wiring a real benchmark profile through sqflite.
class FakeBreederBenchmarkRepository extends BreederBenchmarkRepository {
  bool inProduction = false;

  final BreederBenchmarkProfile _profile = BreederBenchmarkProfile(
    id: 'fake-profile-1',
    profileKey: 'fake_profile',
    company: 'Fake Co',
    breed: 'Ross308',
    product: 'Parent Stock',
    guideVersion: 'Fake Guide v1',
    publicationDate: null,
    sourceUrl: 'https://example.com',
    effectiveAgeStartDays: 0,
    effectiveAgeEndDays: null,
    lifecycleCoverage: 'rearing,production',
    state: 'active',
  );

  @override
  Future<BreederBenchmarkProfile?> getActiveProfileForBreed(
    String breed,
  ) async => inProduction ? _profile : null;

  @override
  Future<int?> getOfficialProductionWeek({
    required String profileId,
    required int ageWeek,
  }) async => inProduction ? 1 : null;

  @override
  Future<int?> getOfficialProductionStartAgeWeek(String profileId) async =>
      inProduction ? 25 : null;

  static const _bodyWeightMetricId = 'fake-metric-body-weight';
  static const _henWeekProductionPctMetricId =
      'fake-metric-hen-week-production-pct';
  static const _dailyFeedIntakeMetricId = 'fake-metric-daily-feed-intake';
  static const _eggWeightMetricId = 'fake-metric-egg-weight';

  /// weightTargets[(sex, ageWeek)] -> targetValue, consulted by
  /// `getValuesForProfile` for weighing widget tests
  /// (breeder-flock-performance ticket 13). Empty by default (no target
  /// published for anything), matching a fresh fake before a test seeds it.
  final Map<(String, int), double> weightTargets = {};

  /// productionPctTargets[ageWeek] -> targetValue for the female
  /// `hen_week_production_pct` metric, consulted by `getValuesForProfile`
  /// for the flock-overview widget tests (breeder-flock-performance ticket
  /// 18). Empty by default (no official production-percent target
  /// published), matching a fresh fake before a test seeds it.
  final Map<int, double> productionPctTargets = {};

  @override
  Future<List<BreederMetricDefinition>> getMetricDefinitions() async {
    return (await getMetricDefinitionsById()).values.toList();
  }

  @override
  Future<Map<String, BreederMetricDefinition>> getMetricDefinitionsById() async {
    return {
      _bodyWeightMetricId: const BreederMetricDefinition(
        id: _bodyWeightMetricId,
        code: 'body_weight_g',
        label: 'Body weight',
        unit: 'g',
        sexScope: 'both',
        periodType: 'weekly',
        aggregationMethod: 'average',
        displayPrecision: 0,
      ),
      _henWeekProductionPctMetricId: const BreederMetricDefinition(
        id: _henWeekProductionPctMetricId,
        code: 'hen_week_production_pct',
        label: 'Hen-Week Production',
        unit: '%',
        sexScope: 'female',
        periodType: 'weekly',
        aggregationMethod: 'average',
        displayPrecision: 1,
      ),
      // Feed grams-per-bird and egg-weight precision for the printable
      // consolidated report (breeder-flock-performance ticket 19).
      _dailyFeedIntakeMetricId: const BreederMetricDefinition(
        id: _dailyFeedIntakeMetricId,
        code: 'daily_feed_intake_g',
        label: 'Daily Feed Intake',
        unit: 'g/bird/day',
        sexScope: 'both',
        periodType: 'daily',
        aggregationMethod: 'average',
        displayPrecision: 0,
      ),
      _eggWeightMetricId: const BreederMetricDefinition(
        id: _eggWeightMetricId,
        code: 'egg_weight_g',
        label: 'Egg Weight',
        unit: 'g',
        sexScope: 'female',
        periodType: 'weekly',
        aggregationMethod: 'average',
        displayPrecision: 1,
      ),
    };
  }

  @override
  Future<List<BreederBenchmarkValue>> getValuesForProfile(String profileId) async {
    return [
      for (final entry in weightTargets.entries)
        BreederBenchmarkValue(
          id: 'fake-value-${entry.key.$1}-${entry.key.$2}',
          profileId: profileId,
          metricId: _bodyWeightMetricId,
          sex: entry.key.$1,
          ageDays: entry.key.$2 * 7,
          ageWeek: entry.key.$2,
          productionWeek: null,
          periodType: 'weekly',
          targetValue: entry.value,
          lowerBound: null,
          upperBound: null,
        ),
      for (final entry in productionPctTargets.entries)
        BreederBenchmarkValue(
          id: 'fake-production-value-${entry.key}',
          profileId: profileId,
          metricId: _henWeekProductionPctMetricId,
          sex: 'female',
          ageDays: entry.key * 7,
          ageWeek: entry.key,
          productionWeek: entry.key,
          periodType: 'weekly',
          targetValue: entry.value,
          lowerBound: null,
          upperBound: null,
        ),
    ];
  }
}

/// In-memory fake for `breeder_flock_milestones` (breeder-flock-performance
/// ticket 06). Always reports no recorded milestones — `testWidgets` hangs
/// against real sqflite past the first gesture (repo convention), and
/// ticket 10's egg-section widget tests exercise `comparisonAxes` (via the
/// review screen's approval snapshot), which would otherwise touch the real
/// database through `BreederFlockLifecycleService`.
class FakeBreederFlockMilestoneRepository extends BreederFlockMilestoneRepository {
  @override
  Future<List<BreederFlockMilestone>> getForFlock(String flockId) async => [];

  @override
  Future<BreederFlockMilestone?> getByType(
    String flockId,
    String eventType,
  ) async => null;
}

/// In-memory fake for `breeder_egg_grade_definitions` (breeder-flock
/// -performance ticket 10). Seeded from the same
/// `kBreederEggGradeDefinitionSeeds` the real database seeds, so widget
/// tests see the genuine priority order without touching sqflite.
class FakeBreederEggGradeDefinitionRepository
    extends BreederEggGradeDefinitionRepository {
  final List<BreederEggGradeDefinition> grades = List.of(
    kBreederEggGradeDefinitionSeeds,
  );

  @override
  Future<List<BreederEggGradeDefinition>> listActiveGrades() async {
    final active = grades.where((g) => g.isActive).toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
    return active;
  }

  @override
  Future<BreederEggGradeDefinition?> getById(String id) async {
    for (final grade in grades) {
      if (grade.id == id) return grade;
    }
    return null;
  }

  @override
  Future<BreederEggGradeDefinition?> getByCode(String code) async {
    for (final grade in grades) {
      if (grade.code == code) return grade;
    }
    return null;
  }
}

class FakeBreederEggProductionEntryRepository
    extends BreederEggProductionEntryRepository {
  FakeBreederEggProductionEntryRepository([this._reportRepository]);

  /// Optional, since most tests never touch flock/date-scoped sums; the two
  /// methods that need it (breeder-flock-performance ticket 11) throw a
  /// clear error if a test calls them without one, rather than silently
  /// returning 0.
  final FakeBreederDailyReportRepository? _reportRepository;

  final Map<String, BreederEggProductionEntry> _byId = {};
  int _idCounter = 0;

  @override
  Future<List<BreederEggProductionEntry>> getForReport(String reportId) async {
    return _byId.values.where((e) => e.reportId == reportId).toList()
      ..sort((a, b) => a.locationId.compareTo(b.locationId));
  }

  @override
  Future<BreederEggProductionEntry?> getById(String id) async => _byId[id];

  /// The fake counterpart of the real repository's SQL sum
  /// (breeder-flock-performance ticket 11).
  @override
  Future<int> sumCountForReportAndGrade(String reportId, String gradeId) async {
    var total = 0;
    for (final entry in _byId.values) {
      if (entry.reportId == reportId && entry.gradeId == gradeId) {
        total += entry.count;
      }
    }
    return total;
  }

  @override
  Future<int> sumCountForFlockGradeBeforeDate({
    required String flockId,
    required String gradeId,
    required DateTime beforeDate,
  }) async {
    final reportRepository = _reportRepository;
    if (reportRepository == null) {
      throw StateError(
        'FakeBreederEggProductionEntryRepository needs a report repository '
        'to answer sumCountForFlockGradeBeforeDate',
      );
    }
    var total = 0;
    for (final entry in _byId.values) {
      if (entry.gradeId != gradeId) continue;
      final report = await reportRepository.getById(entry.reportId);
      if (report == null || report.flockId != flockId) continue;
      if (!report.reportDate.isBefore(beforeDate)) continue;
      total += entry.count;
    }
    return total;
  }

  @override
  Future<BreederEggProductionEntry?> getByReportHouseGrade(
    String reportId,
    String houseId,
    String gradeId,
  ) async {
    for (final entry in _byId.values) {
      if (entry.reportId == reportId &&
          entry.houseId == houseId &&
          entry.gradeId == gradeId) {
        return entry;
      }
    }
    return null;
  }

  @override
  Future<BreederEggProductionEntry?> getByReportIsolationAreaGrade(
    String reportId,
    String isolationAreaId,
    String gradeId,
  ) async {
    for (final entry in _byId.values) {
      if (entry.reportId == reportId &&
          entry.isolationAreaId == isolationAreaId &&
          entry.gradeId == gradeId) {
        return entry;
      }
    }
    return null;
  }

  @override
  Future<BreederEggProductionEntry> upsert(
    BreederEggProductionEntry entry,
  ) async {
    final existing = entry.isHouseEntry
        ? await getByReportHouseGrade(
            entry.reportId,
            entry.houseId!,
            entry.gradeId,
          )
        : await getByReportIsolationAreaGrade(
            entry.reportId,
            entry.isolationAreaId!,
            entry.gradeId,
          );
    if (existing == null) {
      _idCounter += 1;
      final toInsert = entry.copyWith(id: 'egg-entry-$_idCounter');
      _byId[toInsert.id] = toInsert;
      return toInsert;
    }
    final updated = entry.copyWith(id: existing.id);
    _byId[existing.id] = updated;
    return updated;
  }
}

/// In-memory fake for `breeder_egg_inventory_movements`
/// (breeder-flock-performance ticket 11). `testWidgets` hangs against real
/// sqflite (repo convention), so entry/review screen widget tests inject
/// this instead of the real database-backed repository.
class FakeBreederEggInventoryMovementRepository
    extends BreederEggInventoryMovementRepository {
  FakeBreederEggInventoryMovementRepository(this._reportRepository);

  final FakeBreederDailyReportRepository _reportRepository;
  final Map<String, BreederEggInventoryMovement> _byId = {};
  int _idCounter = 0;

  @override
  Future<List<BreederEggInventoryMovement>> getForReport(
    String reportId,
  ) async {
    return _byId.values.where((m) => m.reportId == reportId).toList();
  }

  @override
  Future<List<BreederEggInventoryMovement>> getForReportAndGrade(
    String reportId,
    String gradeId,
  ) async {
    return _byId.values
        .where((m) => m.reportId == reportId && m.gradeId == gradeId)
        .toList();
  }

  @override
  Future<BreederEggInventoryMovement?> getEditableRow(
    String reportId,
    String gradeId,
    String kind,
  ) async {
    for (final movement in _byId.values) {
      if (movement.reportId == reportId &&
          movement.gradeId == gradeId &&
          movement.kind == kind &&
          !movement.isReversal) {
        return movement;
      }
    }
    return null;
  }

  @override
  Future<BreederEggInventoryMovement?> getById(String id) async => _byId[id];

  @override
  Future<List<BreederEggInventoryMovement>> getForFlockGradeBeforeDate({
    required String flockId,
    required String gradeId,
    required DateTime beforeDate,
  }) async {
    final result = <BreederEggInventoryMovement>[];
    for (final movement in _byId.values) {
      if (movement.gradeId != gradeId) continue;
      final report = await _reportRepository.getById(movement.reportId);
      if (report == null || report.flockId != flockId) continue;
      if (!report.reportDate.isBefore(beforeDate)) continue;
      result.add(movement);
    }
    return result;
  }

  @override
  Future<BreederEggInventoryMovement> upsert(
    BreederEggInventoryMovement movement,
  ) async {
    final existing = await getEditableRow(
      movement.reportId,
      movement.gradeId,
      movement.kind,
    );
    if (existing == null) {
      _idCounter += 1;
      final toInsert = BreederEggInventoryMovement(
        id: 'inventory-$_idCounter',
        reportId: movement.reportId,
        gradeId: movement.gradeId,
        kind: movement.kind,
        quantity: movement.quantity,
        adjustmentDirection: movement.adjustmentDirection,
        reason: movement.reason,
        actorUserId: movement.actorUserId,
        occurredAt: movement.occurredAt,
        reversedMovementId: movement.reversedMovementId,
      );
      _byId[toInsert.id] = toInsert;
      return toInsert;
    }
    final updated = BreederEggInventoryMovement(
      id: existing.id,
      reportId: movement.reportId,
      gradeId: movement.gradeId,
      kind: movement.kind,
      quantity: movement.quantity,
      adjustmentDirection: movement.adjustmentDirection,
      reason: movement.reason,
      actorUserId: movement.actorUserId,
      occurredAt: movement.occurredAt,
      reversedMovementId: movement.reversedMovementId,
    );
    _byId[existing.id] = updated;
    return updated;
  }

  @override
  Future<BreederEggInventoryMovement> insertAppend(
    BreederEggInventoryMovement movement,
  ) async {
    _idCounter += 1;
    final toInsert = BreederEggInventoryMovement(
      id: 'inventory-$_idCounter',
      reportId: movement.reportId,
      gradeId: movement.gradeId,
      kind: movement.kind,
      quantity: movement.quantity,
      adjustmentDirection: movement.adjustmentDirection,
      reason: movement.reason,
      actorUserId: movement.actorUserId,
      occurredAt: movement.occurredAt,
      reversedMovementId: movement.reversedMovementId,
    );
    _byId[toInsert.id] = toInsert;
    return toInsert;
  }
}

/// In-memory fake for `breeder_report_revisions`
/// (breeder-flock-performance ticket 12). `testWidgets` hangs against real
/// sqflite (repo convention), so the review screen's correction/revision
/// -history widget tests inject this instead of the real database-backed
/// repository. Mirrors the real repository's insert-and-read-only surface —
/// there is deliberately no update or delete method to fake.
class FakeBreederReportRevisionRepository
    extends BreederReportRevisionRepository {
  final List<BreederReportRevision> _rows = [];
  int _idCounter = 0;

  @override
  String newId() {
    _idCounter += 1;
    return 'fake-revision-$_idCounter';
  }

  @override
  Future<BreederReportRevision> insert(BreederReportRevision revision) async {
    _rows.add(revision);
    return revision;
  }

  @override
  Future<List<BreederReportRevision>> getForReport(String reportId) async {
    final rows = _rows.where((r) => r.reportId == reportId).toList()
      ..sort((a, b) => a.revisionAfter.compareTo(b.revisionAfter));
    return rows;
  }
}

/// In-memory fake for `breeder_weighing_sessions`
/// (breeder-flock-performance ticket 13). `testWidgets` hangs against real
/// sqflite (repo convention), so the weighing entry/list widget tests
/// inject this instead of the real database-backed repository.
class FakeBreederWeighingSessionRepository
    extends BreederWeighingSessionRepository {
  final Map<String, BreederWeighingSession> _byId = {};
  int _idCounter = 0;

  @override
  Future<BreederWeighingSession> create({
    required String flockId,
    required String houseId,
    required DateTime sessionDate,
    required String sex,
    required String method,
    required int sampleSize,
    String? notes,
  }) async {
    _idCounter += 1;
    final session = BreederWeighingSession(
      id: 'fake-session-$_idCounter',
      flockId: flockId,
      houseId: houseId,
      sessionDate: sessionDate,
      sex: sex,
      method: method,
      sampleSize: sampleSize,
      notes: notes,
    );
    _byId[session.id] = session;
    return session;
  }

  @override
  Future<void> update(BreederWeighingSession session) async {
    _byId[session.id] = session;
  }

  @override
  Future<BreederWeighingSession?> getById(String id) async => _byId[id];

  @override
  Future<List<BreederWeighingSession>> listForFlock(String flockId) async {
    final rows = _byId.values.where((s) => s.flockId == flockId).toList()
      ..sort((a, b) => b.sessionDate.compareTo(a.sessionDate));
    return rows;
  }

  @override
  Future<void> delete(String id) async {
    _byId.remove(id);
  }
}

/// In-memory fake for `breeder_weighing_samples`
/// (breeder-flock-performance ticket 13).
class FakeBreederWeighingSampleRepository
    extends BreederWeighingSampleRepository {
  final Map<String, List<BreederWeighingSample>> _bySession = {};
  int _idCounter = 0;

  @override
  Future<List<BreederWeighingSample>> getForSession(String sessionId) async {
    return List.of(_bySession[sessionId] ?? const []);
  }

  @override
  Future<BreederWeighingSample> add({
    required String sessionId,
    required double weightGrams,
  }) async {
    _idCounter += 1;
    final sample = BreederWeighingSample(
      id: 'fake-sample-$_idCounter',
      sessionId: sessionId,
      weightGrams: weightGrams,
    );
    _bySession.putIfAbsent(sessionId, () => []).add(sample);
    return sample;
  }

  @override
  Future<List<BreederWeighingSample>> replaceForSession({
    required String sessionId,
    required List<double> weights,
  }) async {
    final created = weights.map((w) {
      _idCounter += 1;
      return BreederWeighingSample(
        id: 'fake-sample-$_idCounter',
        sessionId: sessionId,
        weightGrams: w,
      );
    }).toList();
    _bySession[sessionId] = created;
    return created;
  }

  @override
  Future<void> deleteForSession(String sessionId) async {
    _bySession.remove(sessionId);
  }
}

/// In-memory fake for `flocks`, only as far as `EggBatchDispatchService`
/// (breeder-flock-performance ticket 14) needs it: looking up a flock's
/// `customerId` to check a shipment's hatchery belongs to the same
/// customer.
class FakeFlockRepository extends FlockRepository {
  FakeFlockRepository(this.flocks);

  final List<FlockModel> flocks;

  @override
  Future<FlockModel?> getFlockById(String id) async {
    for (final flock in flocks) {
      if (flock.id == id) return flock;
    }
    return null;
  }
}

/// In-memory fake for `hatcheries`, only as far as `EggBatchDispatchService`
/// (breeder-flock-performance ticket 14) needs it.
class FakeHatcheryRepository extends HatcheryRepository {
  FakeHatcheryRepository(this.hatcheries);

  final List<HatcheryModel> hatcheries;

  @override
  Future<HatcheryModel?> getById(String id) async {
    for (final hatchery in hatcheries) {
      if (hatchery.id == id) return hatchery;
    }
    return null;
  }

  @override
  Future<List<HatcheryModel>> getHatcheriesByCustomer(String customerId) async {
    return hatcheries.where((h) => h.customerId == customerId).toList();
  }
}

/// In-memory fake for `egg_batches` (breeder-flock-performance ticket 14).
class FakeEggBatchRepository extends EggBatchRepository {
  final Map<String, EggBatch> _byId = {};

  @override
  Future<EggBatch?> getById(String id) async => _byId[id];

  @override
  Future<EggBatch?> getByFlockDateGrade(
    String flockId,
    DateTime collectionDate,
    String gradeId,
  ) async {
    final key = EggBatch.dateKey(collectionDate);
    for (final batch in _byId.values) {
      if (batch.flockId == flockId &&
          EggBatch.dateKey(batch.collectionDate) == key &&
          batch.gradeId == gradeId) {
        return batch;
      }
    }
    return null;
  }

  @override
  Future<List<EggBatch>> listForFlock(String flockId) async {
    final rows = _byId.values.where((b) => b.flockId == flockId).toList()
      ..sort((a, b) => b.collectionDate.compareTo(a.collectionDate));
    return rows;
  }

  @override
  Future<EggBatch> insert(EggBatch batch) async {
    // Preserves the id the caller assigned (matching the real repository,
    // which inserts `batch.toMap()` — including its own `id` — verbatim)
    // rather than minting a new one, since callers (EggBatchDispatchService)
    // keep using their own in-memory copy's id afterward.
    _byId[batch.id] = batch;
    return batch;
  }

  @override
  Future<void> update(EggBatch batch) async {
    _byId[batch.id] = batch;
  }
}

/// In-memory fake for `egg_batch_house_sources` (breeder-flock-performance
/// ticket 14). Enforces the house-belongs-to-flock invariant the real
/// database trigger enforces, given the batch's owning flock via
/// [batchRepository] — mirrors the real schema's
/// `trg_egg_batch_house_sources_house_scope_*` behaviour (throwing
/// [StateError] rather than a `DatabaseException`, since there is no
/// database here).
class FakeEggBatchHouseSourceRepository extends EggBatchHouseSourceRepository {
  FakeEggBatchHouseSourceRepository(this._batchRepository, this._houses);

  final FakeEggBatchRepository _batchRepository;
  final List<HouseModel> _houses;
  final Map<String, List<EggBatchHouseSource>> _byBatch = {};
  int _idCounter = 0;

  @override
  Future<List<EggBatchHouseSource>> getForBatch(String batchId) async {
    return List.of(_byBatch[batchId] ?? const []);
  }

  @override
  Future<EggBatchHouseSource> insert(EggBatchHouseSource source) async {
    final batch = await _batchRepository.getById(source.batchId);
    HouseModel? house;
    for (final h in _houses) {
      if (h.id == source.houseId) house = h;
    }
    if (batch == null || house == null || house.flockId != batch.flockId) {
      throw StateError('Egg batch house source does not belong to the batch flock');
    }
    _idCounter += 1;
    final toInsert = EggBatchHouseSource(
      id: 'fake-house-source-$_idCounter',
      batchId: source.batchId,
      houseId: source.houseId,
      eggCount: source.eggCount,
    );
    _byBatch.putIfAbsent(source.batchId, () => []).add(toInsert);
    return toInsert;
  }
}

/// In-memory fake for `egg_shipments` (breeder-flock-performance ticket 14).
class FakeEggShipmentRepository extends EggShipmentRepository {
  final Map<String, EggShipment> _byId = {};

  @override
  Future<EggShipment?> getById(String id) async => _byId[id];

  @override
  Future<List<EggShipment>> listForFlock(String flockId) async {
    final rows = _byId.values.where((s) => s.flockId == flockId).toList()
      ..sort((a, b) => b.shipmentDate.compareTo(a.shipmentDate));
    return rows;
  }

  @override
  Future<EggShipment> insert(EggShipment shipment) async {
    // Preserves the caller-assigned id, matching the real repository
    // (EggBatchDispatchService.createShipment keeps using its own copy's
    // id after calling insert).
    _byId[shipment.id] = shipment;
    return shipment;
  }

  @override
  Future<void> update(EggShipment shipment) async {
    _byId[shipment.id] = shipment;
  }
}

/// In-memory fake for `egg_shipment_batches` (breeder-flock-performance
/// ticket 14).
class FakeEggShipmentBatchRepository extends EggShipmentBatchRepository {
  FakeEggShipmentBatchRepository(this._shipmentRepository);

  final FakeEggShipmentRepository _shipmentRepository;
  final Map<String, EggShipmentBatch> _byId = {};

  @override
  Future<EggShipmentBatch?> getById(String id) async => _byId[id];

  @override
  Future<List<EggShipmentBatch>> getForShipment(String shipmentId) async {
    return _byId.values.where((l) => l.shipmentId == shipmentId).toList();
  }

  @override
  Future<List<EggShipmentBatch>> getActiveForBatch(String batchId) async {
    final result = <EggShipmentBatch>[];
    for (final line in _byId.values) {
      if (line.batchId != batchId) continue;
      final shipment = await _shipmentRepository.getById(line.shipmentId);
      if (shipment == null || shipment.isCancelled) continue;
      result.add(line);
    }
    return result;
  }

  @override
  Future<EggShipmentBatch> insert(EggShipmentBatch line) async {
    // Preserves the caller-assigned id, matching the real repository
    // (EggBatchDispatchService.addBatchToShipment keeps using its own
    // copy's id after calling insert).
    _byId[line.id] = line;
    return line;
  }

  @override
  Future<void> delete(String id) async {
    _byId.remove(id);
  }
}

/// In-memory fake for `egg_batch_receipts` (breeder-flock-performance
/// ticket 14).
class FakeEggBatchReceiptRepository extends EggBatchReceiptRepository {
  final Map<String, EggBatchReceipt> _byShipmentBatch = {};
  int _idCounter = 0;

  @override
  Future<EggBatchReceipt?> getByShipmentBatch(String shipmentBatchId) async =>
      _byShipmentBatch[shipmentBatchId];

  @override
  Future<List<EggBatchReceipt>> getForShipmentBatches(
    List<String> shipmentBatchIds,
  ) async {
    return [
      for (final id in shipmentBatchIds)
        if (_byShipmentBatch[id] != null) _byShipmentBatch[id]!,
    ];
  }

  @override
  Future<EggBatchReceipt> upsert(EggBatchReceipt receipt) async {
    final existing = _byShipmentBatch[receipt.shipmentBatchId];
    final id = existing?.id ?? 'fake-receipt-${++_idCounter}';
    final toStore = EggBatchReceipt(
      id: id,
      shipmentBatchId: receipt.shipmentBatchId,
      receivedQuantity: receipt.receivedQuantity,
      variance: receipt.variance,
      recordedBy: receipt.recordedBy,
      recordedAt: receipt.recordedAt,
      notes: receipt.notes,
    );
    _byShipmentBatch[receipt.shipmentBatchId] = toStore;
    return toStore;
  }
}

/// In-memory fake for `breeder_alert_rules` (breeder-flock-performance
/// ticket 17). Seeded explicitly by tests via [seed] rather than mirroring
/// `seedBreederAlertRules`, so a test controls exactly which rules exist.
class FakeBreederAlertRuleRepository extends BreederAlertRuleRepository {
  final Map<String, BreederAlertRule> _byId = {};

  void seed(BreederAlertRule rule) {
    _byId[rule.id] = rule;
  }

  @override
  Future<List<BreederAlertRule>> getActiveRules() async {
    return _byId.values.where((r) => r.isActive).toList();
  }

  @override
  Future<BreederAlertRule?> getById(String id) async => _byId[id];

  @override
  Future<BreederAlertRule?> findRule({
    required String metricCode,
    required String scope,
    required String periodType,
    required String direction,
  }) async {
    for (final rule in _byId.values) {
      if (rule.metricCode == metricCode &&
          rule.scope == scope &&
          rule.periodType == periodType &&
          rule.direction == direction &&
          rule.isActive) {
        return rule;
      }
    }
    return null;
  }
}

/// In-memory fake for `breeder_performance_alerts`
/// (breeder-flock-performance ticket 17). Mirrors the real repository's
/// dedupe-by-key lookup ([findOpenAlert]) in plain Dart, but — unlike the
/// real schema — enforces no uniqueness constraint of its own, so a test
/// exercising `BreederAlertEvaluationService` is exactly what proves the
/// service-level dedupe path (rather than the schema's partial unique
/// index, which has its own dedicated real-database test).
class FakeBreederPerformanceAlertRepository
    extends BreederPerformanceAlertRepository {
  final Map<String, BreederPerformanceAlert> _byId = {};
  int _idCounter = 0;

  List<BreederPerformanceAlert> get all => _byId.values.toList();

  @override
  String newId() {
    _idCounter += 1;
    return 'fake-alert-$_idCounter';
  }

  @override
  Future<BreederPerformanceAlert?> getById(String id) async => _byId[id];

  @override
  Future<BreederPerformanceAlert?> findOpenAlert({
    String? customerId,
    required String flockId,
    String? houseId,
    required String metricCode,
    required String periodType,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    for (final alert in _byId.values) {
      if (alert.isOpen &&
          alert.customerId == customerId &&
          alert.flockId == flockId &&
          alert.houseId == houseId &&
          alert.metricCode == metricCode &&
          alert.periodType == periodType &&
          _sameDay(alert.periodStart, periodStart) &&
          _sameDay(alert.periodEnd, periodEnd)) {
        return alert;
      }
    }
    return null;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Future<BreederPerformanceAlert> insert(
    BreederPerformanceAlert alert,
  ) async {
    _byId[alert.id] = alert;
    return alert;
  }

  @override
  Future<BreederPerformanceAlert> updateObservation(
    String id, {
    required double actualValue,
    double? officialTargetValue,
    double? officialLowerBound,
    double? officialUpperBound,
    required bool thresholdIsOfficial,
    required double deviationValue,
    double? deviationPct,
    required String severity,
    required int consecutiveObservationCount,
    String? benchmarkProfileId,
    String? benchmarkProfileVersion,
    String? comparisonAxisKind,
    int? comparisonAxisOffsetWeeks,
    required List<DateTime> evidenceReportDates,
  }) async {
    final existing = _byId[id];
    if (existing == null) {
      throw ArgumentError.value(id, 'id', 'No such performance alert');
    }
    final updated = existing.copyWith(
      actualValue: actualValue,
      officialTargetValue: officialTargetValue,
      officialLowerBound: officialLowerBound,
      officialUpperBound: officialUpperBound,
      thresholdIsOfficial: thresholdIsOfficial,
      deviationValue: deviationValue,
      deviationPct: deviationPct,
      severity: severity,
      consecutiveObservationCount: consecutiveObservationCount,
      benchmarkProfileId: benchmarkProfileId,
      benchmarkProfileVersion: benchmarkProfileVersion,
      comparisonAxisKind: comparisonAxisKind,
      comparisonAxisOffsetWeeks: comparisonAxisOffsetWeeks,
      evidenceReportDates: evidenceReportDates,
      updatedAt: DateTime.now(),
    );
    _byId[id] = updated;
    return updated;
  }

  @override
  Future<List<BreederPerformanceAlert>> listForFlock(
    String flockId, {
    bool openOnly = false,
  }) async {
    return _byId.values
        .where((a) => a.flockId == flockId && (!openOnly || a.isOpen))
        .toList();
  }

  @override
  Future<List<BreederPerformanceAlert>> findOpenCoveringEvidenceDate(
    String flockId,
    DateTime date,
  ) async {
    return _byId.values
        .where(
          (a) =>
              a.flockId == flockId &&
              a.isOpen &&
              a.evidenceReportDates.any((d) => _sameDay(d, date)),
        )
        .toList();
  }

  @override
  Future<BreederPerformanceAlert> markSeen(String id) => _transition(
    id,
    state: BreederPerformanceAlertState.seen,
  );

  @override
  Future<BreederPerformanceAlert> close(String id, {required String reason}) =>
      _transition(
        id,
        state: BreederPerformanceAlertState.closed,
        closedReason: reason,
        closedAt: DateTime.now(),
      );

  @override
  Future<BreederPerformanceAlert> acknowledge(
    String id, {
    required String actorUserId,
  }) => _transition(
    id,
    state: BreederPerformanceAlertState.seen,
    acknowledgedAt: DateTime.now(),
    acknowledgedBy: actorUserId,
  );

  Future<BreederPerformanceAlert> _transition(
    String id, {
    required String state,
    String? closedReason,
    DateTime? closedAt,
    DateTime? acknowledgedAt,
    String? acknowledgedBy,
  }) async {
    final existing = _byId[id];
    if (existing == null) {
      throw ArgumentError.value(id, 'id', 'No such performance alert');
    }
    final updated = existing.copyWith(
      state: state,
      closedReason: closedReason,
      closedAt: closedAt,
      acknowledgedAt: acknowledgedAt,
      acknowledgedBy: acknowledgedBy,
      updatedAt: DateTime.now(),
    );
    _byId[id] = updated;
    return updated;
  }
}
