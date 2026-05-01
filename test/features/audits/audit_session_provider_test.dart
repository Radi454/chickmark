import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:hatchaudit/data/models/audit_session_model.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/data/repositories/activity_log_repository.dart';
import 'package:hatchaudit/data/repositories/audit_session_repository.dart';
import 'package:hatchaudit/features/audits/providers/audit_session_provider.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'session_test_helpers.dart';

class MockAuditSessionRepository extends Mock
    implements AuditSessionRepository {}

class MockActivityLogRepository extends Mock implements ActivityLogRepository {}

class MockSupabaseService extends Mock implements SupabaseService {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      AuditSessionModel(
        id: 'fallback-session',
        customerId: 'fallback',
        flockId: 'fallback',
        hatcheryId: 'fallback',
        date: DateTime(2026),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
  });

  late MockAuditSessionRepository mockRepo;
  late MockActivityLogRepository mockActivityLog;
  late MockSupabaseService mockSupabase;
  late AuditSessionProvider provider;

  final testSession = AuditSessionModel.fromMap(makeAuditSessionRow());

  final testContext = AuditSessionContext(
    customerId: SessionTestFixtures.testCustomerId,
    hatcheryId: SessionTestFixtures.testHatcheryId,
    flockId: SessionTestFixtures.testFlockId,
    date: SessionTestFixtures.testVisitDate,
    breed: SessionTestFixtures.testBreed,
    flockAgeWeeks: 42,
  );

  final testUser = UserModel(
    id: 'test-auditor',
    fullName: 'Test Auditor',
    email: 'auditor@test.com',
    role: 'auditor',
    status: 'approved',
    createdAt: DateTime(2026, 1, 1),
  );

  setUp(() {
    mockRepo = MockAuditSessionRepository();
    mockActivityLog = MockActivityLogRepository();
    mockSupabase = MockSupabaseService();

    when(
      () => mockActivityLog.log(
        any(),
        any(),
        entityType: any(named: 'entityType'),
        entityId: any(named: 'entityId'),
        details: any(named: 'details'),
      ),
    ).thenAnswer((_) async {});
    when(() => mockSupabase.syncAuditSession(any())).thenAnswer((_) async {});

    provider = AuditSessionProvider(
      repository: mockRepo,
      activityLogRepository: mockActivityLog,
      supabaseService: mockSupabase,
    );
  });

  group('AuditSessionProvider - startSession', () {
    test('uses Egg as the visible label while preserving audit type', () {
      expect(AuditSessionProvider.stationDisplayLabels['egg_storage'], 'Egg');
      expect(
        AuditSessionProvider.stationKeyToAuditType['egg_storage'],
        'Egg Storage',
      );
    });

    test('creates new session with in_progress status', () async {
      when(() => mockRepo.insertSession(any())).thenAnswer((_) async {});

      await provider.startSession(context: testContext, currentUser: testUser);

      expect(provider.currentSession, isNotNull);
      expect(provider.currentSession!.status, 'in_progress');
      expect(provider.currentStationIndex, 0);
      expect(provider.isSessionActive, isTrue);
      expect(provider.isResumed, isFalse);
    });

    test('starts at station index 0 (Egg Storage)', () async {
      when(() => mockRepo.insertSession(any())).thenAnswer((_) async {});

      await provider.startSession(context: testContext, currentUser: testUser);

      expect(provider.currentStationIndex, 0);
    });

    test('persists custom station order on new session', () async {
      when(() => mockRepo.insertSession(any())).thenAnswer((_) async {});

      await provider.startSession(
        context: AuditSessionContext(
          customerId: SessionTestFixtures.testCustomerId,
          hatcheryId: SessionTestFixtures.testHatcheryId,
          flockId: SessionTestFixtures.testFlockId,
          date: SessionTestFixtures.testVisitDate,
          breed: SessionTestFixtures.testBreed,
          selectedStationKeys: const ['hatcher_optimizing', 'egg_storage'],
        ),
        currentUser: testUser,
      );

      expect(provider.stationKeys, ['hatcher_optimizing', 'egg_storage']);
      expect(provider.currentSession!.selectedStationKeys, [
        'hatcher_optimizing',
        'egg_storage',
      ]);
      final captured =
          verify(() => mockRepo.insertSession(captureAny())).captured.single
              as AuditSessionModel;
      expect(captured.selectedStationKeys, [
        'hatcher_optimizing',
        'egg_storage',
      ]);
    });

    test('syncs session to Supabase after creation', () async {
      when(() => mockRepo.insertSession(any())).thenAnswer((_) async {});

      await provider.startSession(context: testContext, currentUser: testUser);

      verify(() => mockSupabase.syncAuditSession(any())).called(1);
    });
  });

  group('AuditSessionProvider - resumeSession', () {
    test('loads existing session and sets resumed flag', () async {
      final resumedRow = makeAuditSessionRow(
        stationsCompleted: ['egg_storage', 'chick_quality'],
      );
      final resumedSession = AuditSessionModel.fromMap(resumedRow);

      when(
        () => mockRepo.getSessionById(resumedSession.id),
      ).thenAnswer((_) async => resumedSession);

      await provider.resumeSession(resumedSession.id);

      expect(provider.currentSession, isNotNull);
      expect(provider.isResumed, isTrue);
      expect(provider.currentStationIndex, 2);
    });

    test('resumes from first uncompleted station', () async {
      final emptyRow = makeAuditSessionRow();
      final emptySession = AuditSessionModel.fromMap(emptyRow);

      when(
        () => mockRepo.getSessionById(emptySession.id),
      ).thenAnswer((_) async => emptySession);

      await provider.resumeSession(emptySession.id);

      expect(provider.currentStationIndex, 0);
    });

    test('resumes using persisted custom station order', () async {
      final resumedRow = makeAuditSessionRow(
        selectedStationKeys: ['setter_optimizing', 'hatcher_optimizing'],
        stationsCompleted: ['setter_optimizing'],
      );
      final resumedSession = AuditSessionModel.fromMap(resumedRow);

      when(
        () => mockRepo.getSessionById(resumedSession.id),
      ).thenAnswer((_) async => resumedSession);

      await provider.resumeSession(resumedSession.id);

      expect(provider.stationKeys, ['setter_optimizing', 'hatcher_optimizing']);
      expect(provider.currentStationIndex, 1);
    });

    test(
      'resumes at the first missing station when completion order has gaps',
      () async {
        final resumedRow = makeAuditSessionRow(
          stationsCompleted: ['egg_storage', 'hatch_analysis'],
        );
        final resumedSession = AuditSessionModel.fromMap(resumedRow);

        when(
          () => mockRepo.getSessionById(resumedSession.id),
        ).thenAnswer((_) async => resumedSession);

        await provider.resumeSession(resumedSession.id);

        expect(provider.currentStationIndex, 1);
      },
    );

    test('sets error when session not found', () async {
      when(
        () => mockRepo.getSessionById('nonexistent'),
      ).thenAnswer((_) async => null);

      await provider.resumeSession('nonexistent');

      expect(provider.error, 'Session not found');
      expect(provider.currentSession, isNull);
    });
  });

  group('AuditSessionProvider - navigation', () {
    setUp(() async {
      when(() => mockRepo.insertSession(any())).thenAnswer((_) async {});
      await provider.startSession(context: testContext, currentUser: testUser);
    });

    test('goToNextStation increments target index', () {
      expect(provider.currentStationIndex, 0);

      provider.goToNextStation();

      expect(provider.isMovingToStation, isTrue);

      provider.stationTransitionComplete();

      expect(provider.currentStationIndex, 1);
    });

    test('goToPreviousStation from index 1 returns to 0', () {
      provider.goToNextStation();
      provider.stationTransitionComplete();
      expect(provider.currentStationIndex, 1);

      provider.goToPreviousStation();
      provider.stationTransitionComplete();

      expect(provider.currentStationIndex, 0);
    });

    test('goToNextStation at last station does not go past end', () {
      for (var i = 0; i < 5; i++) {
        provider.goToNextStation();
        provider.stationTransitionComplete();
      }

      expect(provider.currentStationIndex, supportedStationKeys.length - 1);
    });

    test('goToPreviousStation at index 0 does not go negative', () {
      provider.goToPreviousStation();
      provider.stationTransitionComplete();

      expect(provider.currentStationIndex, 0);
    });

    test('goToStation sets specific station index', () {
      provider.goToStation(3);
      provider.stationTransitionComplete();

      expect(provider.currentStationIndex, 3);
    });

    test('goToStation with invalid index does nothing', () {
      provider.goToStation(-1);
      provider.stationTransitionComplete();
      expect(provider.currentStationIndex, 0);

      provider.goToStation(supportedStationKeys.length);
      provider.stationTransitionComplete();
      expect(provider.currentStationIndex, 0);
    });

    test('navigation honors custom station count', () async {
      provider.clearCurrentSession();
      when(() => mockRepo.insertSession(any())).thenAnswer((_) async {});
      await provider.startSession(
        context: AuditSessionContext(
          customerId: SessionTestFixtures.testCustomerId,
          hatcheryId: SessionTestFixtures.testHatcheryId,
          flockId: SessionTestFixtures.testFlockId,
          date: SessionTestFixtures.testVisitDate,
          breed: SessionTestFixtures.testBreed,
          selectedStationKeys: const ['egg_storage', 'hatch_analysis'],
        ),
        currentUser: testUser,
      );

      provider.goToStation(2);
      provider.stationTransitionComplete();

      expect(provider.currentStationIndex, 0);
      provider.goToNextStation();
      provider.stationTransitionComplete();
      provider.goToNextStation();
      provider.stationTransitionComplete();
      expect(provider.currentStationIndex, 1);
    });
  });

  group('AuditSessionProvider - progress tracking', () {
    setUp(() async {
      when(() => mockRepo.insertSession(any())).thenAnswer((_) async {});
      await provider.startSession(context: testContext, currentUser: testUser);
    });

    test('markCurrentStationCompleted updates progress', () async {
      final updatedRow = makeAuditSessionRow(
        stationsCompleted: ['egg_storage'],
      );
      final updatedSession = AuditSessionModel.fromMap(updatedRow);

      when(
        () => mockRepo.markStationCompleted(any(), 'egg_storage'),
      ).thenAnswer((_) async {});
      when(
        () => mockRepo.getSessionById(any()),
      ).thenAnswer((_) async => updatedSession);

      await provider.markCurrentStationCompleted();

      expect(provider.currentSession!.stationsCompleted, ['egg_storage']);
    });

    test('markCurrentStationCompleted syncs to Supabase', () async {
      final updatedRow = makeAuditSessionRow(
        stationsCompleted: ['egg_storage'],
      );
      final updatedSession = AuditSessionModel.fromMap(updatedRow);

      when(
        () => mockRepo.markStationCompleted(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => mockRepo.getSessionById(any()),
      ).thenAnswer((_) async => updatedSession);

      await provider.markCurrentStationCompleted();

      verify(() => mockSupabase.syncAuditSession(any())).called(greaterThan(0));
    });
  });

  group('AuditSessionProvider - completeSession', () {
    setUp(() async {
      when(() => mockRepo.insertSession(any())).thenAnswer((_) async {});
      await provider.startSession(context: testContext, currentUser: testUser);
    });

    test('completes session by marking all stations done', () async {
      final completedRow = makeAuditSessionRow(
        status: 'completed',
        stationsCompleted: supportedStationKeys,
        completedAt: DateTime.now(),
      );
      final completedSession = AuditSessionModel.fromMap(completedRow);

      when(
        () => mockRepo.updateSessionProgress(any(), supportedStationKeys),
      ).thenAnswer((_) async {});
      when(
        () => mockRepo.getSessionById(any()),
      ).thenAnswer((_) async => completedSession);

      await provider.completeSession();

      verify(
        () => mockRepo.updateSessionProgress(any(), supportedStationKeys),
      ).called(1);
      expect(provider.isSessionComplete, isTrue);
    });

    test('completeSession marks only selected custom stations done', () async {
      provider.clearCurrentSession();
      when(() => mockRepo.insertSession(any())).thenAnswer((_) async {});
      await provider.startSession(
        context: AuditSessionContext(
          customerId: SessionTestFixtures.testCustomerId,
          hatcheryId: SessionTestFixtures.testHatcheryId,
          flockId: SessionTestFixtures.testFlockId,
          date: SessionTestFixtures.testVisitDate,
          breed: SessionTestFixtures.testBreed,
          selectedStationKeys: const ['chick_quality', 'hatch_analysis'],
        ),
        currentUser: testUser,
      );

      final completedRow = makeAuditSessionRow(
        status: 'completed',
        selectedStationKeys: ['chick_quality', 'hatch_analysis'],
        stationsCompleted: ['chick_quality', 'hatch_analysis'],
        completedAt: DateTime.now(),
      );
      final completedSession = AuditSessionModel.fromMap(completedRow);

      when(
        () => mockRepo.updateSessionProgress(any(), [
          'chick_quality',
          'hatch_analysis',
        ]),
      ).thenAnswer((_) async {});
      when(
        () => mockRepo.getSessionById(any()),
      ).thenAnswer((_) async => completedSession);

      await provider.completeSession();

      verify(
        () => mockRepo.updateSessionProgress(any(), [
          'chick_quality',
          'hatch_analysis',
        ]),
      ).called(1);
      expect(provider.isSessionComplete, isTrue);
    });
  });

  group('AuditSessionProvider - load sessions', () {
    test('loadInProgressSessions returns in-progress sessions', () async {
      when(
        () => mockRepo.getInProgressSessions(),
      ).thenAnswer((_) async => [testSession]);

      final result = await provider.loadInProgressSessions();

      expect(result.length, 1);
      expect(result.first.status, 'in_progress');
    });

    test('loadCompletedSessions with customer filter', () async {
      when(
        () => mockRepo.getCompletedSessions(
          customerId: 'customer-1',
          limit: 50,
          offset: 0,
        ),
      ).thenAnswer((_) async => []);

      final result = await provider.loadCompletedSessions(
        customerId: 'customer-1',
      );

      expect(result, isEmpty);
    });
  });

  group('AuditSessionProvider - clear and delete', () {
    test('clearCurrentSession resets all state', () async {
      when(() => mockRepo.insertSession(any())).thenAnswer((_) async {});
      await provider.startSession(context: testContext, currentUser: testUser);

      provider.clearCurrentSession();

      expect(provider.currentSession, isNull);
      expect(provider.currentStationIndex, 0);
      expect(provider.isResumed, isFalse);
      expect(provider.isMovingToStation, isFalse);
      expect(provider.error, isNull);
    });

    test('deleteSession clears provider if current session deleted', () async {
      when(() => mockRepo.insertSession(any())).thenAnswer((_) async {});
      await provider.startSession(context: testContext, currentUser: testUser);
      final sessionId = provider.currentSession!.id;

      when(() => mockRepo.deleteSession(sessionId)).thenAnswer((_) async {});

      await provider.deleteSession(sessionId);

      expect(provider.currentSession, isNull);
      expect(provider.currentStationIndex, 0);
    });
  });
}
