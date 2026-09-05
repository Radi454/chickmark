/// Builds the single, direction-agnostic view-model behind the consolidated
/// daily-report table (breeder-flock-performance ticket 19, design doc
/// section 5.3: "The consolidated review table is the same view used for
/// printing and export"). The on-screen review table and the printable PDF
/// both render from a [BreederReportComposition] built by
/// [buildBreederReportComposition] — neither computes its own values, so
/// the two can never drift apart.
///
/// Every derived value here is already formatted as display text following
/// two rules the whole breeder-flock-performance feature shares:
///  - a blank (`—`) prints where a value is missing or a denominator was
///    zero/negative/absent (design section 7.2/14) — never a printed `0`;
///  - a derived value's decimal precision comes from
///    `breeder_metric_definitions.displayPrecision` (ticket 03) via
///    [BreederReportMetricFormatter], never a hard-coded literal.
///
/// RTL correctness (design section 5.3/11: "it must lay out correctly in
/// both Arabic right-to-left and English") is handled at the table-spec
/// level, not by mirroring rendered text: [BreederReportTable.columnsFor]/
/// [rowsFor] reverse column *order* for RTL while leaving every cell's text
/// untouched, so numbers read normally and a header still lines up with its
/// column after the reversal — see the class doc comment below.
library;

import '../../../data/models/breeder_benchmark_models.dart';
import '../../../data/models/breeder_bird_movement_model.dart';
import '../../../data/models/breeder_daily_report_model.dart';
import '../../../data/models/breeder_egg_grade_definition_model.dart';
import '../../../data/models/breeder_egg_production_entry_model.dart';
import '../../../data/models/breeder_feed_entry_model.dart';
import '../../../data/models/breeder_isolation_area_model.dart';
import '../../../data/models/flock_model.dart';
import '../../../data/models/poultry_hierarchy_models.dart';
import '../../../services/breeder/breeder_bird_ledger_service.dart';
import '../../../services/breeder/breeder_egg_inventory_service.dart';
import '../../../services/breeder/breeder_egg_production_service.dart';
import '../../../services/breeder/breeder_flock_lifecycle_service.dart';

/// The text printed for any missing/blank value, matching the review
/// screen's existing convention. Never `0` — see design section 7.2/14.
const String kBreederReportBlank = '—';

/// The official metric code whose `displayPrecision` is reused for every
/// percentage this report prints that has no benchmark metric of its own
/// (egg-grade percent, and this report's own house-scope production
/// percent). There is no dedicated "egg grade percent" or "local
/// production percent" row in `breeder_metric_definitions` — both are
/// paper-report-specific ratios, not official Aviagen metrics — so rather
/// than hard-coding a decimal-places literal for them, this reuses the
/// precision of the nearest published percentage metric. This is a display
/// -precision borrow only: the *label* printed for this report's
/// production percent stays "Production %", never "Hen-Week %", because
/// design section 7.3 documents that this local figure divides by a
/// different denominator than the official hen-week metric.
const String kBreederReportPercentPrecisionMetricCode =
    'hen_week_production_pct';

/// The official metric code whose `displayPrecision` governs printed feed
/// grams-per-bird figures.
const String kBreederReportFeedGramsMetricCode = 'daily_feed_intake_g';

/// The official metric code whose `displayPrecision` governs printed egg
/// weight.
const String kBreederReportEggWeightMetricCode = 'egg_weight_g';

/// Looks up `breeder_metric_definitions.displayPrecision` by metric code
/// (ticket 03) and formats numeric values with it, falling back to a
/// documented default only when the metric table has no matching row (a
/// defensive fallback, not the normal path — the app always seeds these 18
/// rows from `assets/benchmarks/metric_definitions.json`).
class BreederReportMetricFormatter {
  final Map<String, BreederMetricDefinition> _byCode;

  BreederReportMetricFormatter(List<BreederMetricDefinition> definitions)
    : _byCode = {for (final d in definitions) d.code: d};

  /// Formats [value] using metric [code]'s `displayPrecision`, or `—` when
  /// [value] is null (design section 7.2: a missing/zero-denominator
  /// derived value is blank, never `0`).
  String format(double? value, String code, {int fallbackPrecision = 1}) {
    final definition = _byCode[code];
    if (definition != null) return definition.format(value);
    if (value == null) return kBreederReportBlank;
    return value.toStringAsFixed(fallbackPrecision);
  }

  /// Same as [format], with a trailing `%` appended to a real value (never
  /// to a blank — `—%` would misread as a zero-width percentage rather
  /// than "no data").
  String formatPercent(double? value, String code, {int fallbackPrecision = 1}) {
    final formatted = format(value, code, fallbackPrecision: fallbackPrecision);
    return value == null ? formatted : '$formatted%';
  }
}

/// One header key/value pair (design section 5.2: "date and day; breed;
/// calculated total age; official production week; inside temperature;
/// outside temperature; free-text daily notes"). [label] is an
/// English translation key, translated the same way every other on-screen
/// label in this feature is (`context.tr`).
class BreederReportHeaderField {
  final String label;
  final String value;
  const BreederReportHeaderField(this.label, this.value);
}

/// A printable table with a fixed logical (English-reading, left-to-right)
/// column order plus a location label column that is always first in that
/// logical order. [columnsFor]/[rowsFor] reverse column order for RTL
/// without touching any cell's text — the row-label column ends up on the
/// visually-rightmost side (matching how the equivalent Arabic paper form
/// reads), while every numeric string is printed exactly as computed. This
/// is what makes the RTL layout "genuinely correct, not merely mirrored
/// text": mirroring text would reverse the *characters* of a number
/// (turning `15` into a string that reads `51`); this only ever reverses
/// column *order*, so `columnsFor(rtl: true)[i]` always still names
/// `rowsFor(rtl: true)[r][i]` for every row `r`.
class BreederReportTable {
  final String title;

  /// Column header translation keys, logical (LTR) order. Index 0 is
  /// always the row's location/grade label column.
  final List<String> columns;

  /// One list of already-formatted cell strings per row, in the same
  /// logical order as [columns].
  final List<List<String>> rows;

  const BreederReportTable({
    required this.title,
    required this.columns,
    required this.rows,
  });

  List<String> columnsFor({required bool rtl}) =>
      rtl ? columns.reversed.toList(growable: false) : List.of(columns);

  List<List<String>> rowsFor({required bool rtl}) => [
    for (final row in rows) rtl ? row.reversed.toList(growable: false) : row,
  ];
}

/// The full printable/exportable consolidated daily report
/// (breeder-flock-performance ticket 19). One of these is built fresh every
/// time the report is viewed, submitted, approved, or corrected, so it
/// always reflects the header row's current values — which, for an
/// Approved report, are already the latest approved revision: a
/// post-approval correction (ticket 12) mutates the header/child rows in
/// place and bumps [revisionNumber], it never leaves an older value
/// showing (see `BreederDailyReport.revision`'s own doc comment).
class BreederReportComposition {
  final List<BreederReportHeaderField> headerFields;
  final String stateLabel;
  final bool isApproved;
  final int revisionNumber;

  final BreederReportTable femaleMovements;
  final BreederReportTable maleMovements;

  /// Null before the flock has entered the benchmark profile's official
  /// production range (design section 5.1) — the paper form's egg
  /// production/inventory bands do not exist yet for a pre-production
  /// flock.
  final BreederReportTable? eggProduction;
  final BreederReportTable? eggInventory;

  const BreederReportComposition({
    required this.headerFields,
    required this.stateLabel,
    required this.isApproved,
    required this.revisionNumber,
    required this.femaleMovements,
    required this.maleMovements,
    this.eggProduction,
    this.eggInventory,
  });
}

String _locationLabel(String name, {required bool isIsolation}) =>
    isIsolation ? '$name (Isolation)' : name;

List<String> _movementRow(
  String locationName,
  BreederBirdMovement? movement,
  BreederFeedEntry? feedEntry,
  BreederReportMetricFormatter metrics,
) {
  final gramsPerBird = feedEntry == null
      ? null
      : BreederBirdLedgerService.feedGramsPerBird(
          feedKg: feedEntry.feedKg,
          closingLiveBirds: movement?.closing,
        );
  final feedCell = feedEntry == null
      ? kBreederReportBlank
      : feedEntry.feedKg.toString();
  final gramsCell = metrics.format(
    gramsPerBird,
    kBreederReportFeedGramsMetricCode,
    fallbackPrecision: 1,
  );
  if (movement == null) {
    return [
      locationName,
      for (var i = 0; i < 8; i++) kBreederReportBlank,
      feedCell,
      gramsCell,
    ];
  }
  return [
    locationName,
    '${movement.opening}',
    '${movement.mortality}',
    '${movement.culls}',
    '${movement.sale}',
    '${movement.sexSpecificRemoval}',
    '${movement.transferIn}',
    '${movement.transferOut}',
    '${movement.closing}',
    feedCell,
    gramsCell,
  ];
}

BreederReportTable _buildMovementTable({
  required String title,
  required String sex,
  required String removalColumnLabel,
  required List<HouseModel> houses,
  required List<BreederIsolationArea> isolationAreas,
  required List<BreederBirdMovement> movements,
  required List<BreederFeedEntry> feedEntries,
  required BreederReportMetricFormatter metrics,
}) {
  final houseMovements = <String, BreederBirdMovement>{
    for (final m in movements)
      if (m.sex == sex && m.isHouseMovement) m.houseId!: m,
  };
  final isolationMovements = <String, BreederBirdMovement>{
    for (final m in movements)
      if (m.sex == sex && m.isIsolationMovement) m.isolationAreaId!: m,
  };
  final houseFeed = <String, BreederFeedEntry>{
    for (final f in feedEntries)
      if (f.sex == sex && f.isHouseEntry) f.houseId!: f,
  };
  final isolationFeed = <String, BreederFeedEntry>{
    for (final f in feedEntries)
      if (f.sex == sex && f.isIsolationEntry) f.isolationAreaId!: f,
  };
  final columns = [
    'Location',
    'Opening',
    'Mortality',
    'Culls/Sorts',
    'Sale',
    removalColumnLabel,
    'Transfer in',
    'Transfer out',
    'Closing',
    'Feed (kg)',
    'Feed (g/bird)',
  ];
  final rows = <List<String>>[
    for (final house in houses)
      _movementRow(
        house.name,
        houseMovements[house.id],
        houseFeed[house.id],
        metrics,
      ),
    for (final area in isolationAreas)
      _movementRow(
        _locationLabel(area.name, isIsolation: true),
        isolationMovements[area.id],
        isolationFeed[area.id],
        metrics,
      ),
  ];
  return BreederReportTable(title: title, columns: columns, rows: rows);
}

BreederReportTable _buildEggProductionTable({
  required List<HouseModel> houses,
  required List<BreederIsolationArea> isolationAreas,
  required List<BreederEggGradeDefinition> grades,
  required List<BreederEggProductionEntry> eggEntries,
  required List<BreederBirdMovement> movements,
  required BreederReportMetricFormatter metrics,
}) {
  final entriesByLocation = <String, List<BreederEggProductionEntry>>{};
  for (final entry in eggEntries) {
    entriesByLocation.putIfAbsent(entry.locationId, () => []).add(entry);
  }
  final columns = <String>[
    'Location',
    for (final grade in grades) ...[grade.name, '${grade.name} %'],
    'Total eggs',
    'Production %',
    'Egg weight (g)',
  ];

  List<String> rowFor(String locationId, String locationName, bool isIsolation) {
    final entries = entriesByLocation[locationId] ?? const [];
    final countsByGrade = <String, int>{
      for (final e in entries) e.gradeId: e.count,
    };
    final total = BreederEggProductionService.totalEggs(countsByGrade.values);
    final eggWeight = entries.isEmpty ? null : entries.first.eggWeightGrams;
    final closingFemales = isIsolation
        ? BreederEggProductionService.closingFemalesIsolationScope(
            movements.where((m) => m.isolationAreaId == locationId).toList(),
          )
        : BreederEggProductionService.closingFemalesHouseScope(
            movements.where((m) => m.houseId == locationId).toList(),
          );
    final productionPercent = isIsolation
        ? BreederEggProductionService.isolationProductionPercent(
            totalEggsIsolationScope: total,
            closingLiveFemalesIsolationScope: closingFemales,
          )
        : BreederEggProductionService.dailyProductionPercent(
            totalEggsHouseScope: total,
            closingLiveFemalesHouseScope: closingFemales,
          );
    return [
      locationName,
      for (final grade in grades) ...[
        '${countsByGrade[grade.id] ?? 0}',
        metrics.formatPercent(
          BreederEggProductionService.eggGradePercent(
            gradeCount: countsByGrade[grade.id] ?? 0,
            totalEggsForScope: total,
          ),
          kBreederReportPercentPrecisionMetricCode,
        ),
      ],
      '$total',
      metrics.formatPercent(productionPercent, kBreederReportPercentPrecisionMetricCode),
      metrics.format(eggWeight, kBreederReportEggWeightMetricCode),
    ];
  }

  final rows = <List<String>>[
    for (final house in houses) rowFor(house.id, house.name, false),
    for (final area in isolationAreas)
      rowFor(area.id, _locationLabel(area.name, isIsolation: true), true),
  ];
  return BreederReportTable(
    title: 'Egg production',
    columns: columns,
    rows: rows,
  );
}

BreederReportTable _buildEggInventoryTable({
  required List<BreederEggGradeDefinition> grades,
  required List<BreederEggInventoryBalance> inventoryBalances,
}) {
  final columns = <String>[
    'Grade',
    'Previous balance',
    "Today's production",
    'Available balance',
    'Dispatched to hatchery',
    'Sold',
    'Kitchen',
    'Gifts',
    'Closing balance',
  ];
  final balanceByGrade = <String, BreederEggInventoryBalance>{
    for (final b in inventoryBalances) b.gradeId: b,
  };
  final rows = <List<String>>[
    for (final grade in grades)
      () {
        final balance = balanceByGrade[grade.id];
        if (balance == null) {
          return [grade.name, for (var i = 0; i < 7; i++) kBreederReportBlank];
        }
        return [
          grade.name,
          '${balance.previousBalance}',
          '${balance.todaysProduction}',
          '${balance.availableBalance}',
          '${balance.dispatched}',
          '${balance.sold}',
          '${balance.kitchen}',
          '${balance.gifts}',
          '${balance.closingBalance}',
        ];
      }(),
  ];
  return BreederReportTable(title: 'Egg inventory', columns: columns, rows: rows);
}

/// Builds the single composition consumed by both the on-screen review
/// table and the printable PDF (breeder-flock-performance ticket 19).
/// Nothing here recomputes a domain calculation — every derived number
/// comes from the same `BreederBirdLedgerService`/`BreederEggProductionService`
/// static helpers the rest of the feature already uses.
BreederReportComposition buildBreederReportComposition({
  required BreederDailyReport report,
  required FlockModel flock,
  required FlockAgeSummary age,
  required ProductionWeekResult productionWeek,
  required List<HouseModel> houses,
  required List<BreederIsolationArea> isolationAreas,
  required List<BreederBirdMovement> movements,
  required List<BreederFeedEntry> feedEntries,
  required bool hasEggSection,
  required List<BreederEggGradeDefinition> grades,
  required List<BreederEggProductionEntry> eggEntries,
  required List<BreederEggInventoryBalance> inventoryBalances,
  required BreederReportMetricFormatter metrics,
  required String Function(DateTime) formatDate,
  required String Function(DateTime) weekdayName,
}) {
  final headerFields = <BreederReportHeaderField>[
    BreederReportHeaderField('Date', formatDate(report.reportDate)),
    BreederReportHeaderField('Day', weekdayName(report.reportDate)),
    BreederReportHeaderField('Breed', flock.breed),
    BreederReportHeaderField(
      'Age',
      '${age.ageDays} days (${age.ageWeeks} wk)',
    ),
    BreederReportHeaderField(
      'Production week',
      productionWeek.productionWeek?.toString() ?? 'Pre-production',
    ),
    BreederReportHeaderField(
      'Inside (°C)',
      report.insideTemperature?.toString() ?? kBreederReportBlank,
    ),
    BreederReportHeaderField(
      'Outside (°C)',
      report.outsideTemperature?.toString() ?? kBreederReportBlank,
    ),
    BreederReportHeaderField(
      'Light hours',
      report.lightHours?.toString() ?? kBreederReportBlank,
    ),
    if ((report.notes ?? '').isNotEmpty)
      BreederReportHeaderField('Notes', report.notes!),
  ];

  return BreederReportComposition(
    headerFields: headerFields,
    stateLabel: _stateLabel(report.state),
    isApproved: report.isApproved,
    revisionNumber: report.revision,
    femaleMovements: _buildMovementTable(
      title: 'Females',
      sex: BreederBirdMovementSex.female,
      removalColumnLabel: 'Kitchen',
      houses: houses,
      isolationAreas: isolationAreas,
      movements: movements,
      feedEntries: feedEntries,
      metrics: metrics,
    ),
    maleMovements: _buildMovementTable(
      title: 'Males',
      sex: BreederBirdMovementSex.male,
      removalColumnLabel: 'Euthanasia',
      houses: houses,
      isolationAreas: isolationAreas,
      movements: movements,
      feedEntries: feedEntries,
      metrics: metrics,
    ),
    eggProduction: hasEggSection
        ? _buildEggProductionTable(
            houses: houses,
            isolationAreas: isolationAreas,
            grades: grades,
            eggEntries: eggEntries,
            movements: movements,
            metrics: metrics,
          )
        : null,
    eggInventory: hasEggSection
        ? _buildEggInventoryTable(
            grades: grades,
            inventoryBalances: inventoryBalances,
          )
        : null,
  );
}

String _stateLabel(String state) {
  switch (state) {
    case BreederDailyReportState.draft:
      return 'Draft';
    case BreederDailyReportState.submitted:
      return 'Submitted';
    case BreederDailyReportState.approved:
      return 'Approved';
    case BreederDailyReportState.syncConflict:
      return 'Sync Conflict';
    default:
      return state;
  }
}
