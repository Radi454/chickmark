import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/breeder_bird_movement_model.dart';
import 'package:hatchaudit/data/models/breeder_daily_report_model.dart';
import 'package:hatchaudit/data/models/breeder_isolation_area_model.dart';
import 'package:hatchaudit/data/models/poultry_hierarchy_models.dart';
import 'package:hatchaudit/data/repositories/breeder_bird_movement_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_daily_report_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_feed_entry_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_isolation_area_repository.dart';
import 'package:hatchaudit/data/repositories/poultry_hierarchy_repository.dart';
import 'package:hatchaudit/services/breeder/breeder_bird_ledger_service.dart';

import '../../support/test_database.dart';

/// `BreederBirdLedgerService` (breeder-flock-performance ticket 07, design
/// doc section 5, 6, 7): the single tested home for closing-balance
/// arithmetic, transfer balancing, opening-balance derivation, live
/// balances, and the Draft -> Submitted -> Approved state machine.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pure arithmetic (no database)', () {
    test('closing birds = opening - permanent removals +/- transfers', () {
      final closing = BreederBirdLedgerService.closingBirds(
        opening: 100,
        mortality: 2,
        culls: 1,
        sale: 3,
        kitchenRemoval: 1,
        transferIn: 5,
        transferOut: 4,
      );
      // 100 - 2 - 1 - 3 - 1 + 5 - 4 = 94
      expect(closing, 94);
    });

    test('rejects a negative field', () {
      expect(
        () => BreederBirdLedgerService.closingBirds(opening: 10, mortality: -1),
        throwsA(isA<BreederLedgerValidationError>()),
      );
    });

    test('rejects a resulting negative closing balance', () {
      expect(
        () => BreederBirdLedgerService.closingBirds(opening: 5, mortality: 10),
        throwsA(isA<BreederLedgerValidationError>()),
      );
    });

    test('accepts balanced transfers across two house rows', () {
      final movements = [
        BreederBirdMovement(
          id: 'm1',
          reportId: 'r1',
          houseId: 'houseA',
          sex: BreederBirdMovementSex.female,
          opening: 100,
          transferOut: 10,
          closing: 90,
        ),
        BreederBirdMovement(
          id: 'm2',
          reportId: 'r1',
          houseId: 'houseB',
          sex: BreederBirdMovementSex.female,
          opening: 50,
          transferIn: 10,
          closing: 60,
        ),
      ];
      expect(
        () => BreederBirdLedgerService.validateTransferBalance(movements),
        returnsNormally,
      );
    });

    test('rejects mismatched transfers across two house rows', () {
      final movements = [
        BreederBirdMovement(
          id: 'm1',
          reportId: 'r1',
          houseId: 'houseA',
          sex: BreederBirdMovementSex.female,
          opening: 100,
          transferOut: 10,
          closing: 90,
        ),
        BreederBirdMovement(
          id: 'm2',
          reportId: 'r1',
          houseId: 'houseB',
          sex: BreederBirdMovementSex.female,
          opening: 50,
          transferIn: 7,
          closing: 57,
        ),
      ];
      expect(
        () => BreederBirdLedgerService.validateTransferBalance(movements),
        throwsA(isA<BreederLedgerValidationError>()),
      );
    });

    test('balances female and male transfers independently', () {
      final movements = [
        BreederBirdMovement(
          id: 'm1',
          reportId: 'r1',
          houseId: 'houseA',
          sex: BreederBirdMovementSex.female,
          opening: 100,
          transferOut: 10,
          closing: 90,
        ),
        BreederBirdMovement(
          id: 'm2',
          reportId: 'r1',
          houseId: 'houseB',
          sex: BreederBirdMovementSex.female,
          opening: 50,
          transferIn: 10,
          closing: 60,
        ),
        BreederBirdMovement(
          id: 'm3',
          reportId: 'r1',
          houseId: 'houseA',
          sex: BreederBirdMovementSex.male,
          opening: 10,
          transferOut: 2,
          closing: 8,
        ),
        BreederBirdMovement(
          id: 'm4',
          reportId: 'r1',
          houseId: 'houseB',
          sex: BreederBirdMovementSex.male,
          opening: 5,
          transferIn: 2,
          closing: 7,
        ),
      ];
      expect(
        () => BreederBirdLedgerService.validateTransferBalance(movements),
        returnsNormally,
      );
    });
  });

  group('BreederBirdMovement location invariant', () {
    test('rejects a movement naming both a house and an isolation area', () {
      expect(
        () => BreederBirdMovement(
          id: 'm1',
          reportId: 'r1',
          houseId: 'houseA',
          isolationAreaId: 'areaA',
          sex: BreederBirdMovementSex.female,
          opening: 10,
          closing: 10,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a movement naming neither a house nor an isolation area', () {
      expect(
        () => BreederBirdMovement(
          id: 'm1',
          reportId: 'r1',
          sex: BreederBirdMovementSex.female,
          opening: 10,
          closing: 10,
        ),
        throwsArgumentError,
      );
    });
  });

  group(
    'feedGramsPerBird (pure arithmetic, no database, '
    'breeder-flock-performance ticket 09)',
    () {
      test('female feed: kg * 1000 / closing live females', () {
        // 25 kg * 1000 / 200 females = 125 g/bird.
        expect(
          BreederBirdLedgerService.feedGramsPerBird(
            feedKg: 25,
            closingLiveBirds: 200,
          ),
          125.0,
        );
      });

      test('male feed: kg * 1000 / closing live males', () {
        // 3 kg * 1000 / 20 males = 150 g/bird.
        expect(
          BreederBirdLedgerService.feedGramsPerBird(
            feedKg: 3,
            closingLiveBirds: 20,
          ),
          150.0,
        );
      });

      test('a zero denominator yields blank, never 0', () {
        expect(
          BreederBirdLedgerService.feedGramsPerBird(
            feedKg: 10,
            closingLiveBirds: 0,
          ),
          isNull,
        );
      });

      test('a negative denominator yields blank, never an error', () {
        expect(
          BreederBirdLedgerService.feedGramsPerBird(
            feedKg: 10,
            closingLiveBirds: -5,
          ),
          isNull,
        );
      });

      test('a missing (null) denominator yields blank', () {
        expect(
          BreederBirdLedgerService.feedGramsPerBird(
            feedKg: 10,
            closingLiveBirds: null,
          ),
          isNull,
        );
      });

      test('negative feed is rejected', () {
        expect(
          () => BreederBirdLedgerService.feedGramsPerBird(
            feedKg: -1,
            closingLiveBirds: 100,
          ),
          throwsA(isA<BreederLedgerValidationError>()),
        );
      });
    },
  );

  group('BreederApprovalRole', () {
    test('permits production_manager and admin', () {
      expect(BreederApprovalRole.canApprove('production_manager'), isTrue);
      expect(BreederApprovalRole.canApprove('admin'), isTrue);
      expect(BreederApprovalRole.canApprove('ADMIN'), isTrue);
    });

    test('rejects auditor, customer, and null', () {
      expect(BreederApprovalRole.canApprove('auditor'), isFalse);
      expect(BreederApprovalRole.canApprove('customer'), isFalse);
      expect(BreederApprovalRole.canApprove(null), isFalse);
    });
  });

  group('database-backed ledger behaviour', () {
    setUpAll(() async {
      await useIsolatedAppDatabase();
    });

    tearDownAll(() async {
      await DatabaseHelper().close();
    });

    late BreederDailyReportRepository reportRepository;
    late BreederBirdMovementRepository movementRepository;
    late PoultryHierarchyRepository houseRepository;
    late BreederIsolationAreaRepository isolationAreaRepository;
    late BreederFeedEntryRepository feedEntryRepository;
    late BreederBirdLedgerService service;

    setUp(() {
      reportRepository = BreederDailyReportRepository();
      movementRepository = BreederBirdMovementRepository();
      houseRepository = PoultryHierarchyRepository();
      isolationAreaRepository = BreederIsolationAreaRepository();
      feedEntryRepository = BreederFeedEntryRepository();
      service = BreederBirdLedgerService(
        reportRepository: reportRepository,
        movementRepository: movementRepository,
        houseRepository: houseRepository,
        isolationAreaRepository: isolationAreaRepository,
        feedEntryRepository: feedEntryRepository,
      );
    });

    Future<void> seedFlock(String flockId) async {
      final db = await DatabaseHelper().db;
      await db.insert('flocks', {'id': flockId, 'flockId': flockId});
    }

    Future<HouseModel> seedHouse(
      String flockId,
      String houseId, {
      int openingFemales = 0,
      int openingMales = 0,
    }) async {
      final house = HouseModel(
        id: houseId,
        flockId: flockId,
        name: houseId,
        openingFemales: openingFemales,
        openingMales: openingMales,
      );
      await houseRepository.saveHouse(house);
      return house;
    }

    Future<BreederIsolationArea> seedIsolationArea(
      String flockId,
      String areaId, {
      String? name,
    }) async {
      final area = BreederIsolationArea(
        id: areaId,
        flockId: flockId,
        name: name ?? areaId,
      );
      await isolationAreaRepository.saveArea(area);
      return area;
    }

    test(
      'opening balance on the first day comes from house opening counts',
      () async {
        await seedFlock('flock-open-1');
        await seedHouse('flock-open-1', 'house-open-1', openingFemales: 500);

        final opening = await service.openingBalanceFor(
          flockId: 'flock-open-1',
          houseId: 'house-open-1',
          sex: BreederBirdMovementSex.female,
          reportDate: DateTime(2026, 1, 1),
        );
        expect(opening, 500);
      },
    );

    test(
      'opening balance on a later day comes from the previous closing',
      () async {
        await seedFlock('flock-open-2');
        await seedHouse('flock-open-2', 'house-open-2', openingFemales: 500);

        final day1 = await reportRepository.createDraft(
          flockId: 'flock-open-2',
          reportDate: DateTime(2026, 1, 1),
        );
        await service.recordMovement(
          reportId: day1.id,
          houseId: 'house-open-2',
          sex: BreederBirdMovementSex.female,
          opening: 500,
          mortality: 3,
        );

        final openingDay2 = await service.openingBalanceFor(
          flockId: 'flock-open-2',
          houseId: 'house-open-2',
          sex: BreederBirdMovementSex.female,
          reportDate: DateTime(2026, 1, 2),
        );
        expect(openingDay2, 497);
      },
    );

    test('house and flock live balances aggregate movements', () async {
      await seedFlock('flock-balance-1');
      await seedHouse(
        'flock-balance-1',
        'house-balance-a',
        openingFemales: 200,
      );
      await seedHouse(
        'flock-balance-1',
        'house-balance-b',
        openingFemales: 100,
      );

      final report = await reportRepository.createDraft(
        flockId: 'flock-balance-1',
        reportDate: DateTime(2026, 2, 1),
      );
      await service.recordMovement(
        reportId: report.id,
        houseId: 'house-balance-a',
        sex: BreederBirdMovementSex.female,
        opening: 200,
        mortality: 5,
        transferOut: 10,
      );
      await service.recordMovement(
        reportId: report.id,
        houseId: 'house-balance-b',
        sex: BreederBirdMovementSex.female,
        opening: 100,
        transferIn: 10,
      );

      final houseA = await service.houseBalance(
        flockId: 'flock-balance-1',
        houseId: 'house-balance-a',
        sex: BreederBirdMovementSex.female,
      );
      final houseB = await service.houseBalance(
        flockId: 'flock-balance-1',
        houseId: 'house-balance-b',
        sex: BreederBirdMovementSex.female,
      );
      expect(houseA, 185); // 200 - 5 - 10
      expect(houseB, 110); // 100 + 10

      final flockTotal = await service.flockBalance(
        flockId: 'flock-balance-1',
        sex: BreederBirdMovementSex.female,
      );
      expect(flockTotal, 295); // 185 + 110
    });

    test(
      'a movement whose house belongs to a different flock is rejected',
      () async {
        await seedFlock('flock-scope-a');
        await seedFlock('flock-scope-b');
        await seedHouse('flock-scope-b', 'house-scope-foreign');

        final report = await reportRepository.createDraft(
          flockId: 'flock-scope-a',
          reportDate: DateTime(2026, 3, 1),
        );

        expect(
          () => service.recordMovement(
            reportId: report.id,
            houseId: 'house-scope-foreign',
            sex: BreederBirdMovementSex.female,
            opening: 10,
          ),
          throwsA(anything),
        );
      },
    );

    test('only one report per flock per calendar date', () async {
      await seedFlock('flock-unique-1');
      await reportRepository.createDraft(
        flockId: 'flock-unique-1',
        reportDate: DateTime(2026, 4, 1),
      );
      expect(
        () => reportRepository.createDraft(
          flockId: 'flock-unique-1',
          reportDate: DateTime(2026, 4, 1),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('a missing day never appears and is never auto-created', () async {
      await seedFlock('flock-missing-1');
      await reportRepository.createDraft(
        flockId: 'flock-missing-1',
        reportDate: DateTime(2026, 5, 1),
      );
      await reportRepository.createDraft(
        flockId: 'flock-missing-1',
        reportDate: DateTime(2026, 5, 3),
      );

      final reports = await reportRepository.listForFlock('flock-missing-1');
      expect(reports.length, 2);
      final missingDay = await reportRepository.getByFlockAndDate(
        'flock-missing-1',
        DateTime(2026, 5, 2),
      );
      expect(missingDay, isNull);
    });

    test('Draft -> Submitted -> Approved happy path', () async {
      await seedFlock('flock-state-1');
      await seedHouse('flock-state-1', 'house-state-1', openingFemales: 10);
      final report = await reportRepository.createDraft(
        flockId: 'flock-state-1',
        reportDate: DateTime(2026, 6, 1),
      );
      await service.recordMovement(
        reportId: report.id,
        houseId: 'house-state-1',
        sex: BreederBirdMovementSex.female,
        opening: 10,
      );

      final submitted = await service.submit(report, actorUserId: 'user-1');
      expect(submitted.state, BreederDailyReportState.submitted);
      expect(submitted.revision, 2);

      final approved = await service.approve(
        submitted,
        actorUserId: 'user-2',
        actorRole: 'production_manager',
      );
      expect(approved.state, BreederDailyReportState.approved);
      expect(approved.revision, 3);
      expect(approved.approvedBy, 'user-2');
    });

    test('submit rejects a report with unbalanced transfers', () async {
      await seedFlock('flock-state-2');
      await seedHouse('flock-state-2', 'house-state-2a', openingFemales: 50);
      await seedHouse('flock-state-2', 'house-state-2b', openingFemales: 50);
      final report = await reportRepository.createDraft(
        flockId: 'flock-state-2',
        reportDate: DateTime(2026, 6, 2),
      );
      await service.recordMovement(
        reportId: report.id,
        houseId: 'house-state-2a',
        sex: BreederBirdMovementSex.female,
        opening: 50,
        transferOut: 5,
      );
      await service.recordMovement(
        reportId: report.id,
        houseId: 'house-state-2b',
        sex: BreederBirdMovementSex.female,
        opening: 50,
        transferIn: 3,
      );

      expect(
        () => service.submit(report, actorUserId: 'user-1'),
        throwsA(isA<BreederLedgerValidationError>()),
      );
    });

    test('approval is refused for an insufficient role', () async {
      await seedFlock('flock-state-3');
      await seedHouse('flock-state-3', 'house-state-3', openingFemales: 10);
      final report = await reportRepository.createDraft(
        flockId: 'flock-state-3',
        reportDate: DateTime(2026, 6, 3),
      );
      await service.recordMovement(
        reportId: report.id,
        houseId: 'house-state-3',
        sex: BreederBirdMovementSex.female,
        opening: 10,
      );
      final submitted = await service.submit(report, actorUserId: 'user-1');

      expect(
        () => service.approve(
          submitted,
          actorUserId: 'user-2',
          actorRole: 'auditor',
        ),
        throwsA(isA<BreederReportStateError>()),
      );
    });

    test('approving a Draft report (skipping Submitted) is refused', () async {
      await seedFlock('flock-state-4');
      final report = await reportRepository.createDraft(
        flockId: 'flock-state-4',
        reportDate: DateTime(2026, 6, 4),
      );
      expect(
        () => service.approve(
          report,
          actorUserId: 'user-2',
          actorRole: 'admin',
        ),
        throwsA(isA<BreederReportStateError>()),
      );
    });

    group('feed entries (breeder-flock-performance ticket 09)', () {
      test(
        'female and male feed grams-per-bird divide by each sex\'s own '
        'closing balance in that house',
        () async {
          await seedFlock('flock-feed-1');
          await seedHouse(
            'flock-feed-1',
            'house-feed-1',
            openingFemales: 200,
            openingMales: 20,
          );
          final report = await reportRepository.createDraft(
            flockId: 'flock-feed-1',
            reportDate: DateTime(2026, 9, 1),
          );
          final femaleMovement = await service.recordMovement(
            reportId: report.id,
            houseId: 'house-feed-1',
            sex: BreederBirdMovementSex.female,
            opening: 200,
            mortality: 0,
          );
          final maleMovement = await service.recordMovement(
            reportId: report.id,
            houseId: 'house-feed-1',
            sex: BreederBirdMovementSex.male,
            opening: 20,
          );

          final femaleFeed = await service.recordFeedEntry(
            reportId: report.id,
            houseId: 'house-feed-1',
            sex: BreederBirdMovementSex.female,
            feedKg: 25,
          );
          final maleFeed = await service.recordFeedEntry(
            reportId: report.id,
            houseId: 'house-feed-1',
            sex: BreederBirdMovementSex.male,
            feedKg: 3,
          );

          expect(
            BreederBirdLedgerService.feedGramsPerBird(
              feedKg: femaleFeed.feedKg,
              closingLiveBirds: femaleMovement.closing,
            ),
            125.0, // 25 * 1000 / 200
          );
          expect(
            BreederBirdLedgerService.feedGramsPerBird(
              feedKg: maleFeed.feedKg,
              closingLiveBirds: maleMovement.closing,
            ),
            150.0, // 3 * 1000 / 20
          );
        },
      );

      test(
        'isolation feed is reported on its own row against the isolation '
        'area\'s own count, never folded into the house figure',
        () async {
          await seedFlock('flock-feed-2');
          await seedHouse(
            'flock-feed-2',
            'house-feed-2',
            openingFemales: 100,
          );
          await seedIsolationArea('flock-feed-2', 'area-feed-2');
          final report = await reportRepository.createDraft(
            flockId: 'flock-feed-2',
            reportDate: DateTime(2026, 9, 2),
          );
          final houseMovement = await service.recordMovement(
            reportId: report.id,
            houseId: 'house-feed-2',
            sex: BreederBirdMovementSex.female,
            opening: 100,
            transferOut: 10,
          );
          final isolationMovement = await service.recordMovement(
            reportId: report.id,
            isolationAreaId: 'area-feed-2',
            sex: BreederBirdMovementSex.female,
            opening: 0,
            transferIn: 10,
          );

          // House feed only covers the 90 birds that stayed in the house;
          // isolation feed is recorded and computed separately, against
          // only the 10 isolated birds.
          final houseFeed = await service.recordFeedEntry(
            reportId: report.id,
            houseId: 'house-feed-2',
            sex: BreederBirdMovementSex.female,
            feedKg: 9,
          );
          final isolationFeed = await service.recordFeedEntry(
            reportId: report.id,
            isolationAreaId: 'area-feed-2',
            sex: BreederBirdMovementSex.female,
            feedKg: 1,
          );

          expect(
            BreederBirdLedgerService.feedGramsPerBird(
              feedKg: houseFeed.feedKg,
              closingLiveBirds: houseMovement.closing,
            ),
            100.0, // 9 * 1000 / 90
          );
          expect(
            BreederBirdLedgerService.feedGramsPerBird(
              feedKg: isolationFeed.feedKg,
              closingLiveBirds: isolationMovement.closing,
            ),
            100.0, // 1 * 1000 / 10 — coincidentally equal, never combined
          );
          // The isolation entry never appears against the house's location.
          final storedHouseFeed = await feedEntryRepository
              .getByReportHouseSex(
                report.id,
                'house-feed-2',
                BreederBirdMovementSex.female,
              );
          expect(storedHouseFeed!.feedKg, 9);
        },
      );

      test('a missing closing balance yields a blank, not a zero', () async {
        await seedFlock('flock-feed-3');
        await seedHouse('flock-feed-3', 'house-feed-3');
        final report = await reportRepository.createDraft(
          flockId: 'flock-feed-3',
          reportDate: DateTime(2026, 9, 3),
        );
        // No movement recorded for this house/sex at all.
        final feed = await service.recordFeedEntry(
          reportId: report.id,
          houseId: 'house-feed-3',
          sex: BreederBirdMovementSex.female,
          feedKg: 5,
        );
        expect(
          BreederBirdLedgerService.feedGramsPerBird(
            feedKg: feed.feedKg,
            closingLiveBirds: null,
          ),
          isNull,
        );
      });

      test('negative feed is rejected by the service', () async {
        await seedFlock('flock-feed-4');
        await seedHouse('flock-feed-4', 'house-feed-4');
        final report = await reportRepository.createDraft(
          flockId: 'flock-feed-4',
          reportDate: DateTime(2026, 9, 4),
        );
        expect(
          () => service.recordFeedEntry(
            reportId: report.id,
            houseId: 'house-feed-4',
            sex: BreederBirdMovementSex.female,
            feedKg: -1,
          ),
          throwsA(isA<BreederLedgerValidationError>()),
        );
      });

      test(
        'a feed entry whose isolation area belongs to a different flock is '
        'rejected',
        () async {
          await seedFlock('flock-feed-scope-a');
          await seedFlock('flock-feed-scope-b');
          await seedIsolationArea('flock-feed-scope-b', 'area-feed-foreign');
          final report = await reportRepository.createDraft(
            flockId: 'flock-feed-scope-a',
            reportDate: DateTime(2026, 9, 5),
          );
          expect(
            () => service.recordFeedEntry(
              reportId: report.id,
              isolationAreaId: 'area-feed-foreign',
              sex: BreederBirdMovementSex.female,
              feedKg: 1,
            ),
            throwsA(anything),
          );
        },
      );
    });

    group('report header edits (breeder-flock-performance ticket 09)', () {
      test(
        'updateHeader persists temperature, light hours, and notes',
        () async {
          await seedFlock('flock-header-1');
          final report = await reportRepository.createDraft(
            flockId: 'flock-header-1',
            reportDate: DateTime(2026, 9, 6),
          );

          final updated = await service.updateHeader(
            report,
            insideTemperature: 21.5,
            outsideTemperature: 15,
            lightHours: 16,
            notes: 'All quiet',
          );

          expect(updated.insideTemperature, 21.5);
          expect(updated.outsideTemperature, 15);
          expect(updated.lightHours, 16);
          expect(updated.notes, 'All quiet');

          final reloaded = await reportRepository.getById(report.id);
          expect(reloaded!.lightHours, 16);
          expect(reloaded.notes, 'All quiet');
        },
      );

      test('lightHours outside 0-24 is rejected', () async {
        await seedFlock('flock-header-2');
        final report = await reportRepository.createDraft(
          flockId: 'flock-header-2',
          reportDate: DateTime(2026, 9, 7),
        );
        expect(
          () => service.updateHeader(report, lightHours: 25),
          throwsA(isA<BreederLedgerValidationError>()),
        );
        expect(
          () => service.updateHeader(report, lightHours: -1),
          throwsA(isA<BreederLedgerValidationError>()),
        );
      });

      test('a Submitted report\'s header can no longer be edited', () async {
        await seedFlock('flock-header-3');
        await seedHouse('flock-header-3', 'house-header-3', openingFemales: 5);
        final report = await reportRepository.createDraft(
          flockId: 'flock-header-3',
          reportDate: DateTime(2026, 9, 8),
        );
        await service.recordMovement(
          reportId: report.id,
          houseId: 'house-header-3',
          sex: BreederBirdMovementSex.female,
          opening: 5,
        );
        final submitted = await service.submit(report, actorUserId: 'user-1');

        expect(
          () => service.updateHeader(submitted, lightHours: 16),
          throwsA(isA<BreederReportStateError>()),
        );
      });
    });

    group('isolation areas (breeder-flock-performance ticket 08)', () {
      test(
        'a house->isolation transfer leaves the flock total unchanged and '
        'moves the counts correctly',
        () async {
          await seedFlock('flock-iso-1');
          await seedHouse('flock-iso-1', 'house-iso-1', openingFemales: 200);
          await seedIsolationArea('flock-iso-1', 'area-iso-1');
          final report = await reportRepository.createDraft(
            flockId: 'flock-iso-1',
            reportDate: DateTime(2026, 7, 1),
          );

          await service.recordMovement(
            reportId: report.id,
            houseId: 'house-iso-1',
            sex: BreederBirdMovementSex.female,
            opening: 200,
            transferOut: 15,
          );
          await service.recordMovement(
            reportId: report.id,
            isolationAreaId: 'area-iso-1',
            sex: BreederBirdMovementSex.female,
            opening: 0,
            transferIn: 15,
          );

          final recordedMovements = await movementRepository.getForReport(
            report.id,
          );
          expect(
            () => BreederBirdLedgerService.validateTransferBalance(
              recordedMovements,
            ),
            returnsNormally,
          );

          final houseTotal = await service.flockBalance(
            flockId: 'flock-iso-1',
            sex: BreederBirdMovementSex.female,
          );
          final isolationTotal = await service.isolationFlockBalance(
            flockId: 'flock-iso-1',
            sex: BreederBirdMovementSex.female,
          );
          final grandTotal = await service.flockTotalBalance(
            flockId: 'flock-iso-1',
            sex: BreederBirdMovementSex.female,
          );

          expect(houseTotal, 185); // 200 - 15
          expect(isolationTotal, 15);
          expect(grandTotal, 200); // unchanged: 185 + 15
        },
      );

      test(
        'an isolation->house transfer likewise balances and leaves the '
        'flock total unchanged',
        () async {
          await seedFlock('flock-iso-2');
          await seedHouse('flock-iso-2', 'house-iso-2', openingFemales: 100);
          await seedIsolationArea('flock-iso-2', 'area-iso-2');

          final day1 = await reportRepository.createDraft(
            flockId: 'flock-iso-2',
            reportDate: DateTime(2026, 7, 1),
          );
          await service.recordMovement(
            reportId: day1.id,
            houseId: 'house-iso-2',
            sex: BreederBirdMovementSex.female,
            opening: 100,
            transferOut: 20,
          );
          await service.recordMovement(
            reportId: day1.id,
            isolationAreaId: 'area-iso-2',
            sex: BreederBirdMovementSex.female,
            opening: 0,
            transferIn: 20,
          );

          // Day 2: move the isolated birds back into the house.
          final day2 = await reportRepository.createDraft(
            flockId: 'flock-iso-2',
            reportDate: DateTime(2026, 7, 2),
          );
          final houseOpeningDay2 = await service.openingBalanceFor(
            flockId: 'flock-iso-2',
            houseId: 'house-iso-2',
            sex: BreederBirdMovementSex.female,
            reportDate: DateTime(2026, 7, 2),
          );
          final isolationOpeningDay2 = await service.isolationOpeningBalanceFor(
            flockId: 'flock-iso-2',
            isolationAreaId: 'area-iso-2',
            sex: BreederBirdMovementSex.female,
            reportDate: DateTime(2026, 7, 2),
          );
          expect(houseOpeningDay2, 80);
          expect(isolationOpeningDay2, 20);

          await service.recordMovement(
            reportId: day2.id,
            houseId: 'house-iso-2',
            sex: BreederBirdMovementSex.female,
            opening: houseOpeningDay2,
            transferIn: 20,
          );
          await service.recordMovement(
            reportId: day2.id,
            isolationAreaId: 'area-iso-2',
            sex: BreederBirdMovementSex.female,
            opening: isolationOpeningDay2,
            transferOut: 20,
          );

          final houseTotal = await service.flockBalance(
            flockId: 'flock-iso-2',
            sex: BreederBirdMovementSex.female,
          );
          final isolationTotal = await service.isolationFlockBalance(
            flockId: 'flock-iso-2',
            sex: BreederBirdMovementSex.female,
          );
          expect(houseTotal, 100); // fully returned
          expect(isolationTotal, 0);
          expect(
            await service.flockTotalBalance(
              flockId: 'flock-iso-2',
              sex: BreederBirdMovementSex.female,
            ),
            100,
          );
        },
      );

      test(
        'mortality inside isolation reduces the flock total (a permanent '
        'removal, unlike a transfer)',
        () async {
          await seedFlock('flock-iso-3');
          await seedHouse('flock-iso-3', 'house-iso-3', openingFemales: 50);
          await seedIsolationArea('flock-iso-3', 'area-iso-3');

          final day1 = await reportRepository.createDraft(
            flockId: 'flock-iso-3',
            reportDate: DateTime(2026, 7, 1),
          );
          await service.recordMovement(
            reportId: day1.id,
            houseId: 'house-iso-3',
            sex: BreederBirdMovementSex.female,
            opening: 50,
            transferOut: 10,
          );
          await service.recordMovement(
            reportId: day1.id,
            isolationAreaId: 'area-iso-3',
            sex: BreederBirdMovementSex.female,
            opening: 0,
            transferIn: 10,
          );

          // Day 2: two of the isolated birds die.
          final day2 = await reportRepository.createDraft(
            flockId: 'flock-iso-3',
            reportDate: DateTime(2026, 7, 2),
          );
          await service.recordMovement(
            reportId: day2.id,
            isolationAreaId: 'area-iso-3',
            sex: BreederBirdMovementSex.female,
            opening: 10,
            mortality: 2,
          );

          final isolationTotal = await service.isolationFlockBalance(
            flockId: 'flock-iso-3',
            sex: BreederBirdMovementSex.female,
          );
          final grandTotal = await service.flockTotalBalance(
            flockId: 'flock-iso-3',
            sex: BreederBirdMovementSex.female,
          );
          expect(isolationTotal, 8); // 10 - 2
          expect(grandTotal, 48); // 40 (house) + 8 (isolation), down from 50
        },
      );

      test(
        'the three reported figures are correct for females and males '
        'independently',
        () async {
          await seedFlock('flock-iso-4');
          await seedHouse(
            'flock-iso-4',
            'house-iso-4',
            openingFemales: 300,
            openingMales: 30,
          );
          await seedIsolationArea('flock-iso-4', 'area-iso-4');

          final report = await reportRepository.createDraft(
            flockId: 'flock-iso-4',
            reportDate: DateTime(2026, 7, 1),
          );
          await service.recordMovement(
            reportId: report.id,
            houseId: 'house-iso-4',
            sex: BreederBirdMovementSex.female,
            opening: 300,
            transferOut: 12,
          );
          await service.recordMovement(
            reportId: report.id,
            isolationAreaId: 'area-iso-4',
            sex: BreederBirdMovementSex.female,
            opening: 0,
            transferIn: 12,
            mortality: 1,
          );
          await service.recordMovement(
            reportId: report.id,
            houseId: 'house-iso-4',
            sex: BreederBirdMovementSex.male,
            opening: 30,
            transferOut: 3,
          );
          await service.recordMovement(
            reportId: report.id,
            isolationAreaId: 'area-iso-4',
            sex: BreederBirdMovementSex.male,
            opening: 0,
            transferIn: 3,
          );

          expect(
            await service.flockBalance(
              flockId: 'flock-iso-4',
              sex: BreederBirdMovementSex.female,
            ),
            288, // 300 - 12
          );
          expect(
            await service.isolationFlockBalance(
              flockId: 'flock-iso-4',
              sex: BreederBirdMovementSex.female,
            ),
            11, // 12 - 1
          );
          expect(
            await service.flockTotalBalance(
              flockId: 'flock-iso-4',
              sex: BreederBirdMovementSex.female,
            ),
            299, // 300 - 1
          );

          expect(
            await service.flockBalance(
              flockId: 'flock-iso-4',
              sex: BreederBirdMovementSex.male,
            ),
            27, // 30 - 3
          );
          expect(
            await service.isolationFlockBalance(
              flockId: 'flock-iso-4',
              sex: BreederBirdMovementSex.male,
            ),
            3,
          );
          expect(
            await service.flockTotalBalance(
              flockId: 'flock-iso-4',
              sex: BreederBirdMovementSex.male,
            ),
            30, // unchanged
          );
        },
      );

      test(
        'an isolation area from another flock is rejected',
        () async {
          await seedFlock('flock-iso-scope-a');
          await seedFlock('flock-iso-scope-b');
          await seedIsolationArea('flock-iso-scope-b', 'area-iso-foreign');

          final report = await reportRepository.createDraft(
            flockId: 'flock-iso-scope-a',
            reportDate: DateTime(2026, 7, 1),
          );

          expect(
            () => service.recordMovement(
              reportId: report.id,
              isolationAreaId: 'area-iso-foreign',
              sex: BreederBirdMovementSex.female,
              opening: 0,
            ),
            throwsA(anything),
          );
        },
      );

      test(
        'recordMovement rejects a movement naming both a house and an '
        'isolation area',
        () async {
          await seedFlock('flock-iso-both');
          await seedHouse('flock-iso-both', 'house-iso-both');
          await seedIsolationArea('flock-iso-both', 'area-iso-both');
          final report = await reportRepository.createDraft(
            flockId: 'flock-iso-both',
            reportDate: DateTime(2026, 7, 1),
          );

          expect(
            () => service.recordMovement(
              reportId: report.id,
              houseId: 'house-iso-both',
              isolationAreaId: 'area-iso-both',
              sex: BreederBirdMovementSex.female,
              opening: 0,
            ),
            throwsA(isA<BreederLedgerValidationError>()),
          );
        },
      );

      test(
        'recordMovement rejects a movement naming neither a house nor an '
        'isolation area',
        () async {
          await seedFlock('flock-iso-neither');
          final report = await reportRepository.createDraft(
            flockId: 'flock-iso-neither',
            reportDate: DateTime(2026, 7, 1),
          );

          expect(
            () => service.recordMovement(
              reportId: report.id,
              sex: BreederBirdMovementSex.female,
              opening: 0,
            ),
            throwsA(isA<BreederLedgerValidationError>()),
          );
        },
      );

      test(
        'isolation area names must be unique within a flock',
        () async {
          await seedFlock('flock-iso-name');
          await seedIsolationArea(
            'flock-iso-name',
            'area-name-1',
            name: 'Sick Pen',
          );

          expect(
            () => isolationAreaRepository.saveArea(
              BreederIsolationArea(
                id: 'area-name-2',
                flockId: 'flock-iso-name',
                name: 'Sick Pen',
              ),
            ),
            throwsA(anything),
          );
        },
      );
    });
  });
}
