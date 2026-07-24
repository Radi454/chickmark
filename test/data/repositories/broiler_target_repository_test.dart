import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/broiler_target_models.dart';
import 'package:hatchaudit/data/models/poultry_hierarchy_models.dart';
import 'package:hatchaudit/data/repositories/broiler_target_repository.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDirectory;
  late BroilerTargetRepository repository;

  setUpAll(() async {
    databaseDirectory = await useIsolatedAppDatabase();
  });

  setUp(() async {
    await resetAppDatabase();
    repository = BroilerTargetRepository();
  });

  tearDownAll(() async {
    await resetAppDatabase();
    if (databaseDirectory.existsSync()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  test('official catalogue seeding is idempotent and queryable', () async {
    await repository.ensureOfficialCatalogueSeeded();
    await repository.ensureOfficialCatalogueSeeded();

    final profiles = await repository.listProfiles(activeOnly: true);
    expect(profiles, hasLength(15));
    expect(
      profiles.where((profile) => profile.breed == 'Ross 308'),
      hasLength(3),
    );

    final row = await repository.getRow('ross-308-2022-as-hatched', 42);
    expect(row, isNotNull);
    expect(row!.bodyWeightG, 2998);
    expect(row.cumulativeFeedIntakeGPerLivingBird, 4586);
  });

  test(
    'custom versions replace only draft rows and preserve older targets',
    () async {
      await repository.ensureOfficialCatalogueSeeded();
      final draft = await repository.createCustomProfileVersion(
        sourceProfileId: 'cobb500-2022-as-hatched',
        publicationVersion: 'Customer 2026.1',
        createdBy: 'user-1',
      );

      await repository.replaceRowsInDraftVersion(draft.id, [
        BroilerTargetRow(
          id: 'custom-day-0',
          profileId: draft.id,
          ageDay: 0,
          bodyWeightG: 43,
        ),
        BroilerTargetRow(
          id: 'custom-day-7',
          profileId: draft.id,
          ageDay: 7,
          bodyWeightG: 210,
        ),
      ]);
      final db = await DatabaseHelper().db;
      final targetDeletes = await db.query(
        'sync_tombstones',
        where: 'tableName = ?',
        whereArgs: ['broiler_target_rows'],
      );
      expect(targetDeletes, hasLength(57));
      await repository.activateVersion(draft.id);

      final active = await repository.listProfiles(
        brand: 'Cobb',
        breed: 'Cobb500',
        sexProfile: FlockSexProfile.asHatched,
        activeOnly: true,
      );
      expect(active, hasLength(1));
      expect(active.single.id, draft.id);

      final officialRow = await repository.getRow('cobb500-2022-as-hatched', 7);
      final customRow = await repository.getRow(draft.id, 7);
      expect(officialRow!.bodyWeightG, 202);
      expect(customRow!.bodyWeightG, 210);
    },
  );

  test('activated versions cannot have their row set replaced', () async {
    await repository.ensureOfficialCatalogueSeeded();
    final draft = await repository.createCustomProfileVersion(
      sourceProfileId: 'ross-308-2022-male',
      publicationVersion: 'Customer 2026.2',
      createdBy: 'user-1',
    );
    await repository.activateVersion(draft.id);

    await expectLater(
      repository.replaceRowsInDraftVersion(draft.id, const []),
      throwsA(isA<TargetProfileImmutableException>()),
    );

    final db = await DatabaseHelper().db;
    final officialCount = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM broiler_target_rows WHERE profileId = ?',
      ['ross-308-2022-male'],
    );
    expect(officialCount.single['count'], 57);
  });
}
