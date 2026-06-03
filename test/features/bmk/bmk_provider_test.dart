import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/bmk_breed_model.dart';
import 'package:hatchaudit/data/models/bmk_egg_breakout_model.dart';
import 'package:hatchaudit/data/repositories/bmk_repository.dart';
import 'package:hatchaudit/features/bmk/providers/bmk_provider.dart';

void main() {
  test('saveSelectedBreedBenchmark updates the selected breed row', () async {
    final repository = _FakeBmkRepository();
    final provider = BmkProvider(repository: repository);

    await provider.ensureInitialized();
    await provider.saveSelectedBreedBenchmark(
      hatchabilityPct: 91.2,
      fertilityPct: 95.3,
      hofPct: 96.4,
      productionPct: 82.5,
      eggWeightG: 63.6,
      chickWeightG: 43.7,
    );

    final saved = repository.breedRows['Ross308-25']!;
    expect(saved.hatchabilityPct, 91.2);
    expect(saved.fertilityPct, 95.3);
    expect(saved.hofPct, 96.4);
    expect(provider.breedRow!.eggWeightG, 63.6);
    expect(provider.breedRow!.chickWeightG, 43.7);
  });

  test(
    'saveSelectedEggBreakoutBenchmark updates the selected breakout row',
    () async {
      final repository = _FakeBmkRepository();
      final provider = BmkProvider(repository: repository);

      await provider.ensureInitialized();
      await provider.saveSelectedEggBreakoutBenchmark(
        infertilePct: 4.1,
        early24hPct: 1.2,
        early48hPct: 1.3,
        bloodRingPct: 1.4,
        blackEyePct: 1.5,
        earlyDeadPct: 2.1,
        midDeadPct: 2.2,
        lateDeadPct: 2.3,
        externalPipPct: 0.8,
        crackedPct: 0.4,
        contamPct: 0.5,
      );

      final saved = repository.eggBreakoutRows[25]!;
      expect(saved.infertilePct, 4.1);
      expect(saved.blackEyePct, 1.5);
      expect(saved.midDeadPct, 2.2);
      expect(provider.ebRow!.externalPipPct, 0.8);
      expect(provider.ebRow!.contamPct, 0.5);
    },
  );
}

class _FakeBmkRepository extends BmkRepository {
  final Map<String, BmkBreedModel> breedRows = {
    'Ross308-25': BmkBreedModel(
      id: 'Ross308-25',
      breed: 'Ross308',
      ageWeek: 25,
      hatchabilityPct: 90,
      fertilityPct: 94,
      hofPct: 95,
      productionPct: 80,
      eggWeightG: 62,
      chickWeightG: 42,
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

  @override
  Future<void> upsertBmkBreed(Map<String, dynamic> row) async {
    final model = BmkBreedModel.fromMap(row);
    breedRows['${model.breed}-${model.ageWeek}'] = model;
  }

  @override
  Future<void> upsertBmkEggBreakout(Map<String, dynamic> row) async {
    final model = BmkEggBreakoutModel.fromMap(row);
    eggBreakoutRows[model.ageWeek] = model;
  }
}
