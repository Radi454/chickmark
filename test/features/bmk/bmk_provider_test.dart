import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/bmk_breed_model.dart';
import 'package:hatchaudit/data/models/bmk_egg_breakout_model.dart';
import 'package:hatchaudit/data/models/bmk_operational_standard_model.dart';
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

  test(
    'saveSelectedOperationalStandard updates selected operational row',
    () async {
      final repository = _FakeBmkRepository();
      final provider = BmkProvider(repository: repository);

      await provider.ensureInitialized();
      provider.setCanEditGlobalStandards(true);
      await provider.saveSelectedOperationalStandard(
        minValue: 18.5,
        maxValue: 20.5,
      );

      final saved = repository.operationalRows['global-egg_storage_est_short']!;
      expect(saved.minValue, 18.5);
      expect(saved.maxValue, 20.5);
      expect(provider.selectedOperationalStandard!.minValue, 18.5);
    },
  );

  test(
    'setOperationalHatchery reloads standards for hatchery overrides',
    () async {
      final repository = _FakeBmkRepository();
      final provider = BmkProvider(repository: repository);

      await provider.ensureInitialized();
      provider.setOperationalHatchery('hatchery-1');
      await Future<void>.delayed(Duration.zero);

      expect(provider.selectedHatcheryId, 'hatchery-1');
      expect(provider.selectedOperationalStandard!.hatcheryId, 'hatchery-1');
      expect(provider.selectedOperationalStandard!.minValue, 18);
    },
  );

  test('saveOperationalSourcePhoto stores local and cloud paths', () async {
    final repository = _FakeBmkRepository();
    final provider = BmkProvider(repository: repository);

    await provider.ensureInitialized();
    provider.setCanEditGlobalStandards(true);
    await provider.saveOperationalSourcePhoto(
      metricKey: 'egg_storage_est_short',
      photoPath: '/tmp/source-photo.jpg',
      remotePath: 'supabase://photos/bmk/source-photo.jpg',
    );

    final saved = repository.operationalRows['global-egg_storage_est_short']!;
    expect(saved.sourcePhotoPath, '/tmp/source-photo.jpg');
    expect(
      saved.sourcePhotoRemotePath,
      'supabase://photos/bmk/source-photo.jpg',
    );
    expect(
      provider.selectedOperationalStandard!.sourcePhotoPath,
      '/tmp/source-photo.jpg',
    );
    expect(
      provider.selectedOperationalStandard!.sourcePhotoRemotePath,
      'supabase://photos/bmk/source-photo.jpg',
    );
  });

  test('deleteOperationalSourcePhoto clears local and cloud paths', () async {
    final repository = _FakeBmkRepository();
    final provider = BmkProvider(repository: repository);

    repository.operationalRows['global-egg_storage_est_short'] = repository
        .operationalRows['global-egg_storage_est_short']!
        .copyWith(
          sourcePhotoPath: '/tmp/source-photo.jpg',
          sourcePhotoRemotePath: 'supabase://photos/bmk/source-photo.jpg',
        );

    await provider.ensureInitialized();
    provider.setCanEditGlobalStandards(true);
    await provider.deleteOperationalSourcePhoto(
      metricKey: 'egg_storage_est_short',
    );

    final saved = repository.operationalRows['global-egg_storage_est_short']!;
    expect(saved.sourcePhotoPath, isNull);
    expect(saved.sourcePhotoRemotePath, isNull);
    expect(provider.selectedOperationalStandard!.sourcePhotoPath, isNull);
    expect(provider.selectedOperationalStandard!.sourcePhotoRemotePath, isNull);
  });

  test(
    'a non-admin session cannot write a global operational standard',
    () async {
      final repository = _FakeBmkRepository();
      final provider = BmkProvider(repository: repository);

      await provider.ensureInitialized();
      // Default: no global-write rights. Cloud policy
      // bmk_operational_global_write is admin-only, and a rejected row would
      // wedge the whole dirty push batch, so the edit must be refused here.
      expect(provider.canEditGlobalStandards, isFalse);
      final before = repository.operationalRows['global-egg_storage_est_short'];

      await expectLater(
        provider.saveSelectedOperationalStandard(minValue: 1),
        throwsA(isA<BmkGlobalStandardPermissionException>()),
      );
      await expectLater(
        provider.saveOperationalSourcePhoto(
          metricKey: 'egg_storage_est_short',
          photoPath: '/tmp/x.jpg',
        ),
        throwsA(isA<BmkGlobalStandardPermissionException>()),
      );
      await expectLater(
        provider.deleteOperationalSourcePhoto(
          metricKey: 'egg_storage_est_short',
        ),
        throwsA(isA<BmkGlobalStandardPermissionException>()),
      );

      expect(
        repository.operationalRows['global-egg_storage_est_short'],
        same(before),
      );
    },
  );

  test(
    'a non-admin session can still write a hatchery-scoped override',
    () async {
      final repository = _FakeBmkRepository();
      final provider = BmkProvider(repository: repository);

      await provider.ensureInitialized();
      provider.setOperationalHatchery('hatchery-1');
      await Future<void>.delayed(Duration.zero);
      await provider.saveSelectedOperationalStandard(minValue: 17.25);

      final saved = provider.selectedOperationalStandard!;
      expect(saved.hatcheryId, 'hatchery-1');
      expect(saved.minValue, 17.25);
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

  final Map<String, BmkOperationalStandardModel> operationalRows = {
    'global-egg_storage_est_short': BmkOperationalStandardModel(
      id: 'global-egg_storage_est_short',
      stationKey: 'egg',
      sectorKey: 'egg_storage',
      metricKey: 'egg_storage_est_short',
      metricLabel: 'Egg storage EST short',
      unit: '°C',
      minValue: 19,
      maxValue: 21,
      sortOrder: 10,
    ),
    'hatchery-1-egg_storage_est_short': BmkOperationalStandardModel(
      id: 'hatchery-1-egg_storage_est_short',
      hatcheryId: 'hatchery-1',
      stationKey: 'egg',
      sectorKey: 'egg_storage',
      metricKey: 'egg_storage_est_short',
      metricLabel: 'Egg storage EST short',
      unit: '°C',
      minValue: 18,
      maxValue: 20,
      sortOrder: 10,
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

  @override
  Future<List<BmkOperationalStandardModel>> getOperationalStandards({
    String? hatcheryId,
  }) async {
    return operationalRows.values
        .where((row) => row.hatcheryId == null || row.hatcheryId == hatcheryId)
        .fold<Map<String, BmkOperationalStandardModel>>({}, (map, row) {
          map[row.metricKey] = row;
          return map;
        })
        .values
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

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
  Future<void> upsertOperationalStandard(
    BmkOperationalStandardModel row,
  ) async {
    operationalRows[row.id] = row;
  }
}
