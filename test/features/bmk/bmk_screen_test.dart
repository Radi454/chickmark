import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/bmk_breed_model.dart';
import 'package:hatchaudit/data/models/bmk_egg_breakout_model.dart';
import 'package:hatchaudit/data/models/bmk_operational_standard_model.dart';
import 'package:hatchaudit/data/repositories/bmk_repository.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/features/bmk/providers/bmk_provider.dart';
import 'package:hatchaudit/features/bmk/screens/bmk_screen.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockSupabaseService extends Mock implements SupabaseService {}

void main() {
  testWidgets('BMK reference screen renders compact dashboard sections', (
    tester,
  ) async {
    await _pumpBmkScreen(tester);

    expect(find.byKey(const ValueKey('bmk-reference-mode-toolbar')), findsOne);
    expect(find.byKey(const ValueKey('bmk-breed-selector-bar')), findsOne);
    expect(find.byKey(const ValueKey('bmk-breed-metric-grid')), findsOne);
    expect(find.byKey(const ValueKey('bmk-breakout-type-selector')), findsOne);
    expect(find.byKey(const ValueKey('bmk-breakout-metric-grid')), findsOne);
    expect(find.byIcon(Icons.egg_outlined), findsOneWidget);
    expect(find.text('Reference age'), findsWidgets);
    expect(find.text('Benchmark age'), findsWidgets);
  });

  testWidgets('BMK mobile keeps each reference sector compact', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpBmkScreen(tester);

    expect(find.text('Hatchability'), findsOneWidget);
    expect(find.text('Fertility'), findsOneWidget);
    expect(find.text('HOF'), findsOneWidget);
    expect(find.text('Production'), findsOneWidget);
    expect(find.text('Egg weight'), findsOneWidget);
    expect(find.text('Chick weight'), findsOneWidget);

    final breakoutTop = tester.getTopLeft(find.text('Egg Breakout BMK')).dy;
    expect(breakoutTop, lessThan(760));

    await tester.ensureVisible(find.text('Residue'));
    await tester.ensureVisible(find.text('Residue'));
    await tester.ensureVisible(find.text('Residue'));
    await tester.tap(find.text('Residue'));
    await tester.pumpAndSettle();

    expect(find.text('External pip'), findsOneWidget);
    expect(find.text('Cracked'), findsOneWidget);
    expect(find.text('Contaminated'), findsOneWidget);

    final contaminatedBottom = tester
        .getBottomLeft(find.text('Contaminated'))
        .dy;
    expect(contaminatedBottom, lessThan(844));
  });

  testWidgets('BMK reference metrics do not render decorative symbols', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpBmkScreen(tester);

    expect(find.byIcon(Icons.percent_outlined), findsNothing);
    expect(find.byIcon(Icons.eco_outlined), findsNothing);
    expect(find.byIcon(Icons.verified_outlined), findsNothing);
    expect(find.byIcon(Icons.trending_up_outlined), findsNothing);
    expect(find.byIcon(Icons.monitor_weight_outlined), findsNothing);
    expect(find.byIcon(Icons.egg_alt_outlined), findsNothing);
    expect(find.byIcon(Icons.search_outlined), findsNothing);
    expect(find.byIcon(Icons.science_outlined), findsNothing);

    await tester.tap(find.text('Residue'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.block_outlined), findsNothing);
    expect(find.byIcon(Icons.timelapse), findsNothing);
    expect(find.byIcon(Icons.open_in_new), findsNothing);
    expect(find.byIcon(Icons.crisis_alert_outlined), findsNothing);
    expect(find.byIcon(Icons.warning_outlined), findsNothing);
  });

  testWidgets('BMK admin renders operational benchmark editor sector', (
    tester,
  ) async {
    await _pumpBmkScreen(tester);

    await tester.tap(find.text('Admin'));
    await tester.pumpAndSettle();

    expect(find.text('Operational BMK Admin'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('bmk-operational-hatchery-selector')),
      findsOne,
    );
    expect(find.text('Global defaults'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('bmk-operational-standard-selector')),
      findsOne,
    );
    expect(find.text('Egg storage EST short'), findsWidgets);
    expect(find.text('Save operational BMK'), findsOneWidget);
  });

  testWidgets('Operational BMKs are grouped without category source icons', (
    tester,
  ) async {
    await _pumpBmkScreen(tester);

    expect(find.text('Egg'), findsOneWidget);
    expect(find.text('Chicks'), findsOneWidget);
    expect(find.text('Hatch Results'), findsOneWidget);
    expect(find.text('Setters'), findsOneWidget);
    expect(find.text('Hatchers'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('bmk-operational-citations')),
      findsNothing,
    );
  });

  testWidgets('Each operational BMK tile opens its own source link', (
    tester,
  ) async {
    await _pumpBmkScreen(tester);

    final citationButton = find.byKey(
      const ValueKey('bmk-citation-egg_storage_est_short'),
    );
    await tester.ensureVisible(citationButton);
    await tester.tap(citationButton);
    await tester.pumpAndSettle();

    expect(find.text('Egg storage EST short'), findsWidgets);
    expect(find.text('Cobb storage guidance'), findsOneWidget);
    expect(
      find.text(
        'https://www.cobbgenetics.com/assets/Cobb-Files/Hatchery-Guide.pdf',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bmk-open-source-egg_storage_est_short')),
      findsOneWidget,
    );
    expect(find.text('Add photo'), findsOneWidget);
  });

  testWidgets('Internal operational BMK source does not expose a link', (
    tester,
  ) async {
    await _pumpBmkScreen(tester);

    final citationButton = find.byKey(const ValueKey('bmk-citation-cv_alert'));
    await tester.ensureVisible(citationButton);
    await tester.tap(citationButton);
    await tester.pumpAndSettle();

    expect(find.text('CV alert'), findsWidgets);
    expect(find.text('ChickMark operational default'), findsOneWidget);
    expect(find.text('Link'), findsNothing);
    expect(
      find.byKey(const ValueKey('bmk-open-source-cv_alert')),
      findsNothing,
    );
  });

  testWidgets(
    'Operational BMK source photo can be viewed replaced or deleted',
    (tester) async {
      await _pumpBmkScreen(tester);

      final citationButton = find.byKey(
        const ValueKey('bmk-citation-pasgar_score'),
      );
      await tester.ensureVisible(citationButton);
      await tester.tap(citationButton);
      await tester.pumpAndSettle();

      expect(find.text('Photo saved in cloud'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('bmk-view-source-photo-pasgar_score')),
        findsOneWidget,
      );
      expect(find.text('Replace photo'), findsOneWidget);
      expect(find.text('Delete photo'), findsOneWidget);
    },
  );
}

Future<void> _pumpBmkScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider(
            supabaseService: _MockSupabaseService(),
            bypassAuth: true,
          ),
        ),
        ChangeNotifierProvider<BmkProvider>(
          create: (_) => BmkProvider(repository: _FakeBmkRepository()),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: const BmkScreen(),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

class _FakeBmkRepository extends BmkRepository {
  final Map<String, BmkBreedModel> breedRows = {
    'Ross308-25': BmkBreedModel(
      id: 'Ross308-25',
      breed: 'Ross308',
      ageWeek: 25,
      hatchabilityPct: 89,
      fertilityPct: 95,
      hofPct: 85,
      productionPct: 82,
      eggWeightG: 62,
      chickWeightG: 45,
    ),
  };

  final Map<int, BmkEggBreakoutModel> eggBreakoutRows = {
    25: BmkEggBreakoutModel(
      id: 'eb-25',
      ageWeek: 25,
      infertilePct: 3,
      early24hPct: 1,
      early48hPct: 1,
      bloodRingPct: 1,
      blackEyePct: 1,
      earlyDeadPct: 2,
      midDeadPct: 2,
      lateDeadPct: 2,
      externalPipPct: 1,
      crackedPct: 0.5,
      contamPct: 0.5,
    ),
  };

  final List<BmkOperationalStandardModel> operationalRows = [
    BmkOperationalStandardModel(
      id: 'global-egg_storage_est_short',
      stationKey: 'egg',
      sectorKey: 'egg_storage',
      metricKey: 'egg_storage_est_short',
      metricLabel: 'Egg storage EST short',
      unit: '°C',
      minValue: 19,
      maxValue: 21,
      source: 'Cobb storage guidance',
      sourceUrl:
          'https://www.cobbgenetics.com/assets/Cobb-Files/Hatchery-Guide.pdf',
      sortOrder: 10,
    ),
    BmkOperationalStandardModel(
      id: 'global-chicks_cvt',
      stationKey: 'chicks',
      sectorKey: 'cvt',
      metricKey: 'chicks_cvt',
      metricLabel: 'Chicks CVT',
      unit: '°F',
      minValue: 103,
      maxValue: 105,
      source: 'Aviagen chick vent temperature guidance',
      sourceUrl:
          'https://www.aviagen.com/assets/Tech_Center/BB_Resources_Tools/Hatchery_How_Tos/07HowTo7ChickComfort.pdf',
      sortOrder: 20,
    ),
    BmkOperationalStandardModel(
      id: 'global-cv_alert',
      stationKey: 'egg',
      sectorKey: 'egg_storage',
      metricKey: 'cv_alert',
      metricLabel: 'CV alert',
      unit: '%',
      maxValue: 8,
      source: 'ChickMark operational default',
      sortOrder: 25,
    ),
    BmkOperationalStandardModel(
      id: 'global-pasgar_score',
      stationKey: 'chicks',
      sectorKey: 'pasgar',
      metricKey: 'pasgar_score',
      metricLabel: 'Pasgar score',
      unit: 'score',
      minValue: 9,
      source: 'Pas Reform Pasgar guidance',
      sourceUrl:
          'https://www.pasreform.com/en/knowledge/173/pasgar-score-an-easy-chick-quality-assessment-method',
      sourcePhotoPath: '/tmp/pasgar-source.jpg',
      sourcePhotoRemotePath: 'supabase://photos/bmk/pasgar-source.jpg',
      sortOrder: 26,
    ),
    BmkOperationalStandardModel(
      id: 'global-culled_chicks',
      stationKey: 'hatch_results',
      sectorKey: 'hatch_results',
      metricKey: 'culled_chicks',
      metricLabel: 'Culled chicks',
      unit: '%',
      maxValue: 1,
      source: 'ChickMark operational default',
      sortOrder: 30,
    ),
    BmkOperationalStandardModel(
      id: 'global-setter_est_optimal',
      stationKey: 'setters',
      sectorKey: 'est',
      metricKey: 'setter_est_optimal',
      metricLabel: 'Setter EST optimal',
      unit: '°F',
      minValue: 100,
      maxValue: 101,
      source: 'Petersime/HatchTech EST guidance',
      sourceUrl:
          'https://en.aviagen.com/assets/Tech_Center/BB_Resources_Tools/AA_How_Tos/AAHowto3EggShellTempEN13.pdf',
      sortOrder: 40,
    ),
    BmkOperationalStandardModel(
      id: 'global-hatcher_cvt',
      stationKey: 'hatchers',
      sectorKey: 'cvt',
      metricKey: 'hatcher_cvt',
      metricLabel: 'Hatcher CVT',
      unit: '°F',
      minValue: 103,
      maxValue: 105,
      source: 'Aviagen chick vent temperature guidance',
      sourceUrl:
          'https://www.aviagen.com/assets/Tech_Center/BB_Resources_Tools/Hatchery_How_Tos/07HowTo7ChickComfort.pdf',
      sortOrder: 50,
    ),
  ];

  @override
  Future<List<BmkOperationalHatcheryOption>> getOperationalHatcheries() async {
    return const [
      BmkOperationalHatcheryOption(
        id: 'hatchery-1',
        label: 'Farm One · Hatchery One',
      ),
    ];
  }

  @override
  Future<List<int>> getBreedAges(String breed) async {
    return breedRows.values
        .where((row) => row.breed == breed)
        .map((row) => row.ageWeek)
        .toList()
      ..sort();
  }

  @override
  Future<BmkBreedModel?> getBreedBenchmark(String breed, int ageWeek) async {
    return breedRows['$breed-$ageWeek'];
  }

  @override
  Future<List<int>> getEggBreakoutAges() async {
    return eggBreakoutRows.keys.toList()..sort();
  }

  @override
  Future<BmkEggBreakoutModel?> getEggBreakoutBenchmark(int ageWeek) async {
    return eggBreakoutRows[ageWeek];
  }

  @override
  Future<List<BmkOperationalStandardModel>> getOperationalStandards({
    String? hatcheryId,
  }) async {
    return operationalRows;
  }

  @override
  Future<void> upsertOperationalStandard(
    BmkOperationalStandardModel row,
  ) async {
    final index = operationalRows.indexWhere((item) => item.id == row.id);
    if (index == -1) {
      operationalRows.add(row);
    } else {
      operationalRows[index] = row;
    }
  }
}
