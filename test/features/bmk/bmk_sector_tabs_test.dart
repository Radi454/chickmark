import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/breeder_benchmark_models.dart';
import 'package:hatchaudit/data/models/bmk_breed_model.dart';
import 'package:hatchaudit/data/models/bmk_egg_breakout_model.dart';
import 'package:hatchaudit/data/models/bmk_operational_standard_model.dart';
import 'package:hatchaudit/data/repositories/bmk_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_benchmark_repository.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/features/bmk/providers/bmk_provider.dart';
import 'package:hatchaudit/features/bmk/screens/bmk_screen.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockSupabaseService extends Mock implements SupabaseService {}

/// Empty hatchery data — this test is about sector routing, not the
/// hatchery sector's own content (covered by bmk_screen_test.dart).
class _EmptyBmkRepository extends BmkRepository {
  final BmkBreedModel? breedRow;

  _EmptyBmkRepository({this.breedRow});

  @override
  Future<List<BmkOperationalHatcheryOption>> getOperationalHatcheries() async =>
      const [];

  @override
  Future<List<int>> getBreedAges(String breed) async =>
      breedRow == null ? const [] : [breedRow!.ageWeek];

  @override
  Future<BmkBreedModel?> getBreedBenchmark(String breed, int ageWeek) async =>
      breedRow;

  @override
  Future<List<int>> getEggBreakoutAges() async => const [];

  @override
  Future<BmkEggBreakoutModel?> getEggBreakoutBenchmark(int ageWeek) async =>
      null;

  @override
  Future<List<BmkOperationalStandardModel>> getOperationalStandards({
    String? hatcheryId,
  }) async => const [];
}

const _kRossProfile = BreederBenchmarkProfile(
  id: 'p1',
  profileKey: 'aviagen_ross308_parent_stock_2021_en',
  company: 'Aviagen',
  breed: 'Ross 308',
  product: 'Parent Stock',
  guideVersion: 'Performance Objectives 2021 EN',
  publicationDate: null,
  sourceUrl: 'https://example.invalid/ross308.pdf',
  effectiveAgeStartDays: 0,
  effectiveAgeEndDays: 455,
  lifecycleCoverage: 'rearing_and_production',
  state: 'active',
);

const _kHubbardProfile = BreederBenchmarkProfile(
  id: 'p2',
  profileKey: 'hubbard_conventional_edge_parent_stock_2025_en',
  company: 'Hubbard',
  breed: 'Hubbard Conventional (EDGE)',
  product: 'Parent Stock',
  guideVersion: 'EDGE Parent Stock 2025 EN',
  publicationDate: null,
  sourceUrl: '',
  effectiveAgeStartDays: 0,
  effectiveAgeEndDays: 455,
  lifecycleCoverage: 'rearing_and_production',
  state: 'active',
);

const _kMetrics = [
  BreederMetricDefinition(
    id: 'm-bw',
    code: 'body_weight_g',
    label: 'Body Weight',
    unit: 'g',
    sexScope: 'both',
    periodType: 'weekly',
    aggregationMethod: 'average',
    displayPrecision: 0,
  ),
  BreederMetricDefinition(
    id: 'm-hw',
    code: 'hen_week_production_pct',
    label: 'Hen-Week Production',
    unit: '%',
    sexScope: 'female',
    periodType: 'weekly',
    aggregationMethod: 'average',
    displayPrecision: 1,
  ),
  BreederMetricDefinition(
    id: 'm-lr',
    code: 'liveability_rearing_pct',
    label: 'Liveability (Rearing Period)',
    unit: '%',
    sexScope: 'both',
    periodType: 'weekly',
    aggregationMethod: 'average',
    displayPrecision: 1,
  ),
];

BreederBenchmarkValue _value({
  required String profileId,
  required String metricId,
  required String sex,
  required int ageWeek,
  required double? target,
}) {
  return BreederBenchmarkValue(
    id: '$profileId-$metricId-$sex-$ageWeek',
    profileId: profileId,
    metricId: metricId,
    sex: sex,
    ageDays: ageWeek * 7,
    ageWeek: ageWeek,
    productionWeek: null,
    periodType: 'weekly',
    targetValue: target,
    lowerBound: null,
    upperBound: null,
  );
}

class _FakeBreederBenchmarkRepository extends BreederBenchmarkRepository {
  final List<BreederBenchmarkProfile> profiles;
  bool loaded = false;

  _FakeBreederBenchmarkRepository({this.profiles = const [_kRossProfile]});

  @override
  Future<List<BreederBenchmarkProfile>> getProfiles({
    bool activeOnly = true,
  }) async {
    loaded = true;
    return profiles;
  }

  @override
  Future<List<BreederMetricDefinition>> getMetricDefinitions() async =>
      _kMetrics;

  @override
  Future<List<BreederBenchmarkValue>> getValuesForProfile(
    String profileId,
  ) async {
    if (profileId == _kHubbardProfile.id) {
      // Hubbard publishes no male table and no liveability.
      return [
        _value(
          profileId: profileId,
          metricId: 'm-bw',
          sex: 'female',
          ageWeek: 25,
          target: 2930,
        ),
        _value(
          profileId: profileId,
          metricId: 'm-hw',
          sex: 'female',
          ageWeek: 25,
          target: 12.5,
        ),
      ];
    }
    return [
      _value(
        profileId: profileId,
        metricId: 'm-bw',
        sex: 'female',
        ageWeek: 25,
        target: 2970,
      ),
      _value(
        profileId: profileId,
        metricId: 'm-bw',
        sex: 'male',
        ageWeek: 25,
        target: 3800,
      ),
      _value(
        profileId: profileId,
        metricId: 'm-hw',
        sex: 'female',
        ageWeek: 25,
        target: 5.4,
      ),
    ];
  }
}

void main() {
  testWidgets('BMK screen splits Hatchery and Breeder Farm sectors', (
    tester,
  ) async {
    final repository = _FakeBreederBenchmarkRepository();
    await _pumpBmkScreen(tester, repository);

    expect(find.byKey(const ValueKey('bmk-sector-tabs')), findsOne);
    expect(find.text('Hatchery'), findsOneWidget);
    expect(find.text('Breeder Farm'), findsOneWidget);

    // Hatchery is the default sector and the breeder repository is not
    // touched until its tab is opened.
    expect(find.text('Breed Benchmarks'), findsOneWidget);
    expect(repository.loaded, isFalse);

    await tester.tap(find.text('Breeder Farm'));
    await tester.pumpAndSettle();

    expect(repository.loaded, isTrue);
    // Read-only sector: no add/edit affordance.
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byIcon(Icons.edit), findsNothing);
  });

  testWidgets('Breeder Farm sector reads like the Hatchery sector', (
    tester,
  ) async {
    await _pumpBmkScreen(tester, _FakeBreederBenchmarkRepository());
    await tester.tap(find.text('Breeder Farm'));
    await tester.pumpAndSettle();

    // Same shape as the hatchery: selector bar, age control, tile grids.
    expect(find.byKey(const ValueKey('breeder-bmk-profile-bar')), findsOne);
    expect(find.byKey(const ValueKey('breeder-bmk-headline-grid')), findsOne);
    expect(find.byKey(const ValueKey('breeder-bmk-production-grid')), findsOne);
    expect(find.byKey(const ValueKey('breeder-bmk-livability-grid')), findsOne);
    expect(find.text('Ross 308'), findsOneWidget);

    // The age control lands on the first week the guide publishes production
    // for, not on day-old.
    expect(find.text('25w'), findsOneWidget);
    expect(find.text('2970 g'), findsOneWidget);
    expect(find.text('5.4 %'), findsOneWidget);

    // Male line is published for Ross, so the sex toggle appears and switches
    // the sexed metrics.
    expect(find.byKey(const ValueKey('breeder-bmk-sex-bar')), findsOne);
    await tester.tap(find.text('Male'));
    await tester.pumpAndSettle();
    expect(find.text('3800 g'), findsOneWidget);

    // Hen-week production is published for the female line only, so under
    // Male it must dash rather than repeat the hen's figure.
    expect(find.text('5.4 %'), findsNothing);
    expect(find.text('Hen-Week Production'), findsOneWidget);
    expect(find.text('—'), findsWidgets);

    // Switching back restores it.
    await tester.tap(find.text('Female'));
    await tester.pumpAndSettle();
    expect(find.text('5.4 %'), findsOneWidget);

    // The full per-age tables stay reachable.
    expect(find.byKey(const ValueKey('breeder-bmk-view-tables')), findsOne);
  });

  testWidgets('Breeder Farm sector lays out on a phone without overflowing', (
    tester,
  ) async {
    // Breeder metric labels come from the guides and run long, so the narrow
    // layout is the one that breaks first.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpBmkScreen(tester, _FakeBreederBenchmarkRepository());
    await tester.tap(find.text('Breeder Farm'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('breeder-bmk-headline-grid')), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Breeder metrics the guide does not publish render as a dash', (
    tester,
  ) async {
    await _pumpBmkScreen(
      tester,
      _FakeBreederBenchmarkRepository(profiles: const [_kHubbardProfile]),
    );
    await tester.tap(find.text('Breeder Farm'));
    await tester.pumpAndSettle();

    // Hubbard publishes no male table: the sex toggle must not offer one.
    expect(find.byKey(const ValueKey('breeder-bmk-sex-bar')), findsNothing);

    // Liveability is unpublished — a dash, never a zero.
    expect(find.text('Liveability (Rearing Period)'), findsOneWidget);
    expect(find.text('0 %'), findsNothing);
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('Hatchery breed benchmarks render unpublished values as a dash', (
    tester,
  ) async {
    // `bmk_breeds` stores 0.0 where a guide publishes nothing at this age;
    // showing that as "0%" reads as a real target of zero.
    await _pumpBmkScreen(
      tester,
      _FakeBreederBenchmarkRepository(),
      breedRow: BmkBreedModel(
        id: 'ross308-25',
        breed: 'Ross308',
        ageWeek: 25,
        hatchabilityPct: 0,
        fertilityPct: 0,
        hofPct: 0,
        productionPct: 5.4,
        eggWeightG: 49.4,
        chickWeightG: 45,
      ),
    );

    expect(find.byKey(const ValueKey('bmk-breed-metric-grid')), findsOne);
    expect(find.text('0%'), findsNothing);
    expect(find.text('—'), findsNWidgets(3));
    // Published values are untouched.
    expect(find.text('5.4%'), findsOneWidget);
    expect(find.text('49.4 g'), findsOneWidget);
    expect(find.text('45 g'), findsOneWidget);
  });
}

Future<void> _pumpBmkScreen(
  WidgetTester tester,
  BreederBenchmarkRepository repository, {
  BmkBreedModel? breedRow,
}) async {
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
          create: (_) =>
              BmkProvider(repository: _EmptyBmkRepository(breedRow: breedRow)),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: BmkScreen(breederBenchmarkRepository: repository),
      ),
    ),
  );

  await tester.pumpAndSettle();
}
