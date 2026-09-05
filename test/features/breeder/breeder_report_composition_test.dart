import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/models/breeder_benchmark_models.dart';
import 'package:hatchaudit/data/models/breeder_bird_movement_model.dart';
import 'package:hatchaudit/data/models/breeder_daily_report_model.dart';
import 'package:hatchaudit/data/models/breeder_egg_grade_definition_model.dart';
import 'package:hatchaudit/data/models/breeder_egg_production_entry_model.dart';
import 'package:hatchaudit/data/models/breeder_feed_entry_model.dart';
import 'package:hatchaudit/data/models/breeder_isolation_area_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/poultry_hierarchy_models.dart';
import 'package:hatchaudit/features/breeder/services/breeder_report_composition.dart';
import 'package:hatchaudit/services/breeder/breeder_egg_inventory_service.dart';
import 'package:hatchaudit/services/breeder/breeder_flock_lifecycle_service.dart';

/// Unit coverage for the printable-report composition
/// (breeder-flock-performance ticket 19). This is where the "single source
/// of truth for print and screen", "blank not zero", "metric-definition
/// precision", and "genuinely correct RTL" requirements are testable as
/// plain data assertions, independent of any widget tree or PDF renderer.
void main() {
  final flock = FlockModel(
    id: 'flock-1',
    customerId: 'customer-1',
    flockId: 'FLK-1',
    breed: 'Ross308',
    entryDate: DateTime(2026, 1, 1),
  );
  const age = FlockAgeSummary(ageDays: 200, ageWeeks: 28);
  const productionWeek = ProductionWeekResult(
    profile: null,
    axis: ComparisonAxis.official(),
    ageDays: 200,
    ageWeeks: 28,
    guideAgeWeeks: 28,
    productionWeek: 3,
  );
  final houseA = HouseModel(
    id: 'house-a',
    flockId: 'flock-1',
    name: 'House A',
    openingFemales: 100,
    openingMales: 10,
  );
  final isolationX = BreederIsolationArea(
    id: 'iso-x',
    flockId: 'flock-1',
    name: 'Sick Bay',
  );
  final metrics = BreederReportMetricFormatter(const [
    BreederMetricDefinition(
      id: 'm1',
      code: 'daily_feed_intake_g',
      label: 'Daily Feed Intake',
      unit: 'g/bird/day',
      sexScope: 'both',
      periodType: 'daily',
      aggregationMethod: 'average',
      displayPrecision: 0,
    ),
    BreederMetricDefinition(
      id: 'm2',
      code: 'hen_week_production_pct',
      label: 'Hen-Week Production',
      unit: '%',
      sexScope: 'female',
      periodType: 'weekly',
      aggregationMethod: 'average',
      displayPrecision: 1,
    ),
    BreederMetricDefinition(
      id: 'm3',
      code: 'egg_weight_g',
      label: 'Egg Weight',
      unit: 'g',
      sexScope: 'female',
      periodType: 'weekly',
      aggregationMethod: 'average',
      displayPrecision: 1,
    ),
  ]);

  BreederDailyReport report({
    String state = BreederDailyReportState.draft,
    int revision = 1,
  }) {
    return BreederDailyReport(
      id: 'report-1',
      flockId: 'flock-1',
      reportDate: DateTime(2026, 6, 1), // a Monday
      insideTemperature: 24.5,
      outsideTemperature: 30,
      lightHours: 16,
      notes: 'All quiet',
      state: state,
      revision: revision,
    );
  }

  BreederReportComposition compose({
    BreederDailyReport? reportOverride,
    List<BreederBirdMovement> movements = const [],
    List<BreederFeedEntry> feedEntries = const [],
    bool hasEggSection = false,
    List<BreederEggGradeDefinition> grades = const [],
    List<BreederEggProductionEntry> eggEntries = const [],
    List<BreederEggInventoryBalance> inventoryBalances = const [],
    List<BreederIsolationArea> isolationAreas = const [],
  }) {
    return buildBreederReportComposition(
      report: reportOverride ?? report(),
      flock: flock,
      age: age,
      productionWeek: productionWeek,
      houses: [houseA],
      isolationAreas: isolationAreas,
      movements: movements,
      feedEntries: feedEntries,
      hasEggSection: hasEggSection,
      grades: grades,
      eggEntries: eggEntries,
      inventoryBalances: inventoryBalances,
      metrics: metrics,
      formatDate: (d) => '${d.year}-${d.month}-${d.day}',
      weekdayName: (d) => const [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ][d.weekday - 1],
    );
  }

  group('header', () {
    test('includes date, day, breed, age, production week, temps, notes', () {
      final composition = compose();
      final byLabel = {
        for (final f in composition.headerFields) f.label: f.value,
      };
      expect(byLabel['Date'], '2026-6-1');
      expect(byLabel['Day'], 'Monday');
      expect(byLabel['Breed'], 'Ross308');
      expect(byLabel['Age'], '200 days (28 wk)');
      expect(byLabel['Production week'], '3');
      expect(byLabel['Inside (°C)'], '24.5');
      expect(byLabel['Outside (°C)'], '30.0');
      expect(byLabel['Light hours'], '16.0');
      expect(byLabel['Notes'], 'All quiet');
    });

    test('a missing temperature prints blank, never 0', () {
      final composition = compose(
        reportOverride: BreederDailyReport(
          id: 'report-2',
          flockId: 'flock-1',
          reportDate: DateTime(2026, 6, 2),
        ),
      );
      final byLabel = {
        for (final f in composition.headerFields) f.label: f.value,
      };
      expect(byLabel['Inside (°C)'], kBreederReportBlank);
      expect(byLabel['Outside (°C)'], kBreederReportBlank);
      expect(byLabel.containsKey('Notes'), isFalse);
    });

    test(
      'an approved report exposes its state and latest revision number',
      () {
        final composition = compose(
          reportOverride: report(
            state: BreederDailyReportState.approved,
            revision: 4,
          ),
        );
        expect(composition.isApproved, isTrue);
        expect(composition.stateLabel, 'Approved');
        expect(composition.revisionNumber, 4);
      },
    );

    test('a draft report is not approved and carries revision 1', () {
      final composition = compose();
      expect(composition.isApproved, isFalse);
      expect(composition.stateLabel, 'Draft');
      expect(composition.revisionNumber, 1);
    });
  });

  group('movement tables', () {
    test('a house with no recorded movement/feed prints blank cells', () {
      final composition = compose();
      final row = composition.femaleMovements.rows.single;
      expect(row.first, 'House A');
      // Opening..Closing (8 columns) + feed kg + grams/bird all blank.
      for (final cell in row.skip(1)) {
        expect(cell, kBreederReportBlank);
      }
    });

    test(
      'feed grams-per-bird prints at daily_feed_intake_g displayPrecision',
      () {
        final movement = BreederBirdMovement(
          id: 'move-1',
          reportId: 'report-1',
          houseId: 'house-a',
          sex: BreederBirdMovementSex.female,
          opening: 100,
          closing: 100,
        );
        final feed = BreederFeedEntry(
          id: 'feed-1',
          reportId: 'report-1',
          houseId: 'house-a',
          sex: BreederBirdMovementSex.female,
          feedKg: 10,
        );
        final composition = compose(
          movements: [movement],
          feedEntries: [feed],
        );
        final row = composition.femaleMovements.rows.single;
        // 10 kg * 1000 / 100 birds = 100.0 g/bird -> displayPrecision 0.
        expect(row.last, '100');
        expect(row[9], '10.0'); // feed kg column, unrounded input value
      },
    );

    test(
      'an isolation area appears as its own row, labelled distinctly',
      () {
        final composition = compose(isolationAreas: [isolationX]);
        expect(composition.femaleMovements.rows.length, 2);
        expect(composition.femaleMovements.rows[0].first, 'House A');
        expect(
          composition.femaleMovements.rows[1].first,
          'Sick Bay (Isolation)',
        );
      },
    );

    test('female table uses Kitchen, male table uses Euthanasia', () {
      final composition = compose();
      expect(composition.femaleMovements.columns, contains('Kitchen'));
      expect(composition.femaleMovements.columns, isNot(contains('Euthanasia')));
      expect(composition.maleMovements.columns, contains('Euthanasia'));
      expect(composition.maleMovements.columns, isNot(contains('Kitchen')));
    });
  });

  group('egg production and inventory', () {
    final gradeA = BreederEggGradeDefinition(
      id: 'grade-a',
      code: 'first',
      name: 'First',
      priority: 1,
    );

    test('is absent (null) before the flock enters production', () {
      final composition = compose(hasEggSection: false);
      expect(composition.eggProduction, isNull);
      expect(composition.eggInventory, isNull);
    });

    test(
      'egg-grade percent prints at the borrowed percent-metric precision, '
      'with a % suffix, and blank never 0',
      () {
        final entry = BreederEggProductionEntry(
          id: 'egg-1',
          reportId: 'report-1',
          houseId: 'house-a',
          gradeId: 'grade-a',
          count: 45,
          eggWeightGrams: 62.345,
        );
        final movement = BreederBirdMovement(
          id: 'move-1',
          reportId: 'report-1',
          houseId: 'house-a',
          sex: BreederBirdMovementSex.female,
          opening: 100,
          closing: 100,
        );
        final composition = compose(
          hasEggSection: true,
          grades: [gradeA],
          eggEntries: [entry],
          movements: [movement],
        );
        final row = composition.eggProduction!.rows.single;
        // row: [Location, First, First %, Total eggs, Production %, Egg weight]
        expect(row[0], 'House A');
        expect(row[1], '45');
        expect(row[2], '100.0%'); // 45/45 eggs, one decimal precision
        expect(row[3], '45');
        expect(row[4], '45.0%'); // 45 eggs / 100 closing females
        expect(row[5], '62.3'); // egg_weight_g precision 1

        // A location with nothing recorded at all: total is 0, so the
        // percent denominators are non-positive and every derived value
        // is blank — never a printed 0%.
        final blankComposition = compose(hasEggSection: true, grades: [gradeA]);
        final blankRow = blankComposition.eggProduction!.rows.single;
        expect(blankRow[1], '0'); // a real, recorded zero count
        expect(blankRow[2], kBreederReportBlank); // 0/0 -> blank, not 0%
        expect(blankRow[4], kBreederReportBlank);
      },
    );

    test('egg inventory: a grade with no balance row prints all blanks', () {
      final composition = compose(hasEggSection: true, grades: [gradeA]);
      final row = composition.eggInventory!.rows.single;
      expect(row.first, 'First');
      for (final cell in row.skip(1)) {
        expect(cell, kBreederReportBlank);
      }
    });

    test('egg inventory: a real balance prints its actual figures', () {
      final balance = const BreederEggInventoryBalance(
        gradeId: 'grade-a',
        previousBalance: 10,
        todaysProduction: 45,
        availableBalance: 55,
        dispatched: 20,
        sold: 5,
        kitchen: 2,
        gifts: 1,
        netAdjustment: 0,
        closingBalance: 27,
      );
      final composition = compose(
        hasEggSection: true,
        grades: [gradeA],
        inventoryBalances: [balance],
      );
      final row = composition.eggInventory!.rows.single;
      expect(row, [
        'First',
        '10',
        '45',
        '55',
        '20',
        '5',
        '2',
        '1',
        '27',
      ]);
    });

    test('an isolation area appears as its own egg-production row', () {
      final composition = compose(
        hasEggSection: true,
        grades: [gradeA],
        isolationAreas: [isolationX],
      );
      expect(composition.eggProduction!.rows.length, 2);
      expect(
        composition.eggProduction!.rows[1].first,
        'Sick Bay (Isolation)',
      );
    });
  });

  group('RTL table structure (genuinely correct, not merely mirrored text)', () {
    test('columnsFor(rtl: true) reverses column order, not header text', () {
      final table = compose().femaleMovements;
      final ltr = table.columnsFor(rtl: false);
      final rtl = table.columnsFor(rtl: true);
      expect(rtl, ltr.reversed.toList());
      // Every individual header string is untouched — only order flips.
      expect(rtl.toSet(), ltr.toSet());
    });

    test(
      'rowsFor(rtl: true) keeps each value under its own header after the '
      'reversal, and never reverses the characters of a numeric string',
      () {
        final movement = BreederBirdMovement(
          id: 'move-1',
          reportId: 'report-1',
          houseId: 'house-a',
          sex: BreederBirdMovementSex.female,
          opening: 15,
          closing: 15,
        );
        final table = compose(movements: [movement]).femaleMovements;
        final ltrColumns = table.columnsFor(rtl: false);
        final rtlColumns = table.columnsFor(rtl: true);
        final ltrRow = table.rowsFor(rtl: false).single;
        final rtlRow = table.rowsFor(rtl: true).single;

        // Association survives the reversal: whatever column j names in
        // the RTL header, rtlRow[j] is exactly that column's value.
        for (var j = 0; j < ltrColumns.length; j++) {
          final ltrIndex = ltrColumns.indexOf(rtlColumns[j]);
          expect(rtlRow[j], ltrRow[ltrIndex]);
        }

        // "Opening" is 15 in both directions — reversing column order must
        // never reverse the digits of a number (that would silently turn
        // 15 into a string reading 51, corrupting the printed document).
        final openingIndexRtl = rtlColumns.indexOf('Opening');
        expect(rtlRow[openingIndexRtl], '15');
        expect(rtlRow[openingIndexRtl], isNot('51'));

        // The location-label column (index 0 in LTR) is the last column
        // in RTL order — the row label reads on the visually-rightmost
        // side, matching the Arabic paper form's own layout.
        expect(rtlColumns.last, 'Location');
        expect(rtlRow.last, 'House A');
      },
    );
  });
}
