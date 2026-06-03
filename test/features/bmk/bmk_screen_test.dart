import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/bmk_breed_model.dart';
import 'package:hatchaudit/data/models/bmk_egg_breakout_model.dart';
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
}
