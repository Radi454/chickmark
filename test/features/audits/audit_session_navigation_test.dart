import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/data/models/audit_session_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/data/repositories/audit_repository.dart';
import 'package:hatchaudit/data/repositories/activity_log_repository.dart';
import 'package:hatchaudit/data/repositories/audit_session_repository.dart';
import 'package:hatchaudit/data/repositories/govee_capture_repository.dart';
import 'package:hatchaudit/data/repositories/station_sample_repository.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/providers/audit_session_provider.dart';
import 'package:hatchaudit/features/audits/screens/egg_storage_screen.dart';
import 'package:hatchaudit/features/audits/screens/audit_session_screen.dart';
import 'package:hatchaudit/features/audits/screens/audit_station_selection_screen.dart';
import 'package:hatchaudit/features/audits/screens/hatch_analysis_screen.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/features/govee/providers/govee_capture_provider.dart';
import 'package:hatchaudit/providers/app_provider.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
import 'package:hatchaudit/services/govee/govee_service.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'session_test_helpers.dart';

class MockAuditSessionRepository extends Mock
    implements AuditSessionRepository {}

class MockAuditRepository extends Mock implements AuditRepository {}

class MockStationSampleRepository extends Mock
    implements StationSampleRepository {}

class MockActivityLogRepository extends Mock implements ActivityLogRepository {}

class MockSupabaseService extends Mock implements SupabaseService {}

class MockGoveeCaptureRepository extends Mock
    implements GoveeCaptureRepository {}

class MockGoveeService extends Mock implements GoveeService {}

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
    registerFallbackValue(TemperaturePlace.eggStorageRoom);
  });

  testWidgets('completion navigation keeps unnamed root route available', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (rootContext) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(rootContext).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          body: Center(
                            child: Builder(
                              builder: (sessionContext) {
                                return ElevatedButton(
                                  onPressed: () {
                                    Navigator.of(sessionContext).popUntil(
                                      auditSessionCompletionRoutePredicate,
                                    );
                                  },
                                  child: const Text('Finish session'),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('Start session'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Start session'));
    await tester.pumpAndSettle();
    expect(find.text('Finish session'), findsOneWidget);

    await tester.tap(find.text('Finish session'));
    await tester.pumpAndSettle();

    expect(find.text('Start session'), findsOneWidget);
    expect(find.text('Finish session'), findsNothing);
  });

  testWidgets(
    'station selection start button resets after session route pops',
    (tester) async {
      final repository = MockAuditSessionRepository();
      final supabase = MockSupabaseService();
      final provider = AuditSessionProvider(
        repository: repository,
        supabaseService: supabase,
      );

      when(() => repository.insertSession(any())).thenAnswer((_) async {});
      when(() => supabase.syncAuditSession(any())).thenAnswer((_) async {});

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: provider),
            ChangeNotifierProvider(
              create: (_) => AuthProvider(supabaseService: supabase),
            ),
            ChangeNotifierProvider(create: (_) => CustomersProvider()),
            ChangeNotifierProvider(create: (_) => AppProvider()),
            ChangeNotifierProvider(create: (_) => GoveeCaptureProvider()),
          ],
          child: MaterialApp(
            home: AuditStationSelectionScreen(
              customerId: SessionTestFixtures.testCustomerId,
              flockId: SessionTestFixtures.testFlockId,
              hatcheryId: SessionTestFixtures.testHatcheryId,
              selectedFlock: FlockModel(
                id: SessionTestFixtures.testFlockId,
                customerId: SessionTestFixtures.testCustomerId,
                flockId: SessionTestFixtures.testFlockId,
                breed: SessionTestFixtures.testBreed,
                entryDate: SessionTestFixtures.testVisitDate.subtract(
                  const Duration(days: 42 * 7),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Egg'));
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Start Visit'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(AuditSessionScreen), findsOneWidget);

      Navigator.of(tester.element(find.byType(AuditSessionScreen))).pop();
      await tester.pump(const Duration(milliseconds: 350));

      final startButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Start Visit'),
      );
      expect(startButton.onPressed, isNotNull);
    },
  );

  testWidgets('station selection uses a chick icon for Chicks', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuditStationSelectionScreen(
          customerId: SessionTestFixtures.testCustomerId,
          flockId: SessionTestFixtures.testFlockId,
          hatcheryId: SessionTestFixtures.testHatcheryId,
          selectedFlock: FlockModel(
            id: SessionTestFixtures.testFlockId,
            customerId: SessionTestFixtures.testCustomerId,
            flockId: SessionTestFixtures.testFlockId,
            breed: SessionTestFixtures.testBreed,
            entryDate: SessionTestFixtures.testVisitDate.subtract(
              const Duration(days: 42 * 7),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('station-chick-icon')), findsOneWidget);
    expect(find.byIcon(Icons.cruelty_free), findsNothing);

    await tester.tap(find.text('Chicks'));
    await tester.pump();

    expect(find.byKey(const ValueKey('station-chick-icon')), findsOneWidget);
    expect(find.byIcon(Icons.cruelty_free), findsNothing);
  });

  testWidgets('session shell uses reference progress and footer structure', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 1537);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = MockAuditSessionRepository();
    final activityLog = MockActivityLogRepository();
    final supabase = MockSupabaseService();
    final provider = AuditSessionProvider(
      repository: repository,
      activityLogRepository: activityLog,
      supabaseService: supabase,
    );

    when(() => repository.insertSession(any())).thenAnswer((_) async {});
    when(
      () => activityLog.log(
        any(),
        any(),
        entityType: any(named: 'entityType'),
        entityId: any(named: 'entityId'),
        details: any(named: 'details'),
      ),
    ).thenAnswer((_) async {});
    when(() => supabase.syncAuditSession(any())).thenAnswer((_) async {});

    await provider.startSession(
      context: AuditSessionContext(
        customerId: SessionTestFixtures.testCustomerId,
        hatcheryId: SessionTestFixtures.testHatcheryId,
        flockId: SessionTestFixtures.testFlockId,
        date: SessionTestFixtures.testVisitDate,
        breed: SessionTestFixtures.testBreed,
        selectedStationKeys: const [
          'egg',
          'hatch_analysis_egg_breakouts',
          'hatchers',
          'chicks',
          'setters',
        ],
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(create: (_) => CustomersProvider()),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: supabase),
          ),
          ChangeNotifierProvider(create: (_) => AppProvider()),
        ],
        child: const MaterialApp(home: AuditSessionScreen()),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('audit-session-progress-shell')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('audit-session-navigation-footer')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('audit-session-next-action')),
      findsOneWidget,
    );
    expect(find.text('Next Station'), findsOneWidget);

    final appBar = tester.widget<AppBar>(find.byType(AppBar).first);
    expect(appBar.toolbarHeight, kToolbarHeight);

    final progressSize = tester.getSize(
      find.byKey(const ValueKey('audit-session-progress-shell')),
    );
    expect(progressSize.height, lessThanOrEqualTo(82));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('audit-session-progress-shell')),
        matching: find.text('Hatch'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('audit-session-progress-shell')),
        matching: find.text('Hatch Analysis'),
      ),
      findsNothing,
    );
    final firstNodeCenter = tester.getCenter(
      find.byKey(const ValueKey('audit-session-progress-node-0')),
    );
    for (var i = 1; i < 5; i++) {
      expect(
        tester
            .getCenter(find.byKey(ValueKey('audit-session-progress-node-$i')))
            .dy,
        closeTo(firstNodeCenter.dy, 0.1),
      );
    }
    for (var i = 0; i < 4; i++) {
      final connectorRect = tester.getRect(
        find.byKey(ValueKey('audit-session-progress-connector-$i')),
      );
      final currentNodeRect = tester.getRect(
        find.byKey(ValueKey('audit-session-progress-node-$i')),
      );
      final nextNodeRect = tester.getRect(
        find.byKey(ValueKey('audit-session-progress-node-${i + 1}')),
      );
      expect(connectorRect.left, closeTo(currentNodeRect.right, 1));
      expect(connectorRect.right, closeTo(nextNodeRect.left, 1));
    }

    final footerSize = tester.getSize(
      find.byKey(const ValueKey('audit-session-navigation-footer')),
    );
    expect(footerSize.height, lessThanOrEqualTo(78));
  });

  testWidgets('non-final station save does not show completion check overlay', (
    tester,
  ) async {
    final repository = MockAuditSessionRepository();
    final activityLog = MockActivityLogRepository();
    final supabase = MockSupabaseService();
    final provider = AuditSessionProvider(
      repository: repository,
      activityLogRepository: activityLog,
      supabaseService: supabase,
    );

    when(() => repository.insertSession(any())).thenAnswer((_) async {});
    when(
      () => repository.markStationCompleted(any(), any()),
    ).thenAnswer((_) async => makeAuditSessionRow(stationsCompleted: ['egg']));
    when(() => repository.getSessionById(any())).thenAnswer(
      (_) async => AuditSessionModel.fromMap(
        makeAuditSessionRow(
          selectedStationKeys: ['egg', 'chicks'],
          stationsCompleted: ['egg'],
        ),
      ),
    );
    when(
      () => activityLog.log(
        any(),
        any(),
        entityType: any(named: 'entityType'),
        entityId: any(named: 'entityId'),
        details: any(named: 'details'),
      ),
    ).thenAnswer((_) async {});
    when(() => supabase.syncAuditSession(any())).thenAnswer((_) async {});

    await provider.startSession(
      context: AuditSessionContext(
        customerId: SessionTestFixtures.testCustomerId,
        hatcheryId: SessionTestFixtures.testHatcheryId,
        flockId: SessionTestFixtures.testFlockId,
        date: SessionTestFixtures.testVisitDate,
        breed: SessionTestFixtures.testBreed,
        selectedStationKeys: const ['egg', 'chicks'],
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(create: (_) => CustomersProvider()),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: supabase),
          ),
          ChangeNotifierProvider(create: (_) => AppProvider()),
          ChangeNotifierProvider(create: (_) => GoveeCaptureProvider()),
        ],
        child: const MaterialApp(home: AuditSessionScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    final stationProvider = Provider.of<AuditProvider>(
      tester.element(find.byType(EggStorageScreen)),
      listen: false,
    );
    stationProvider.setEditMode(false);

    await tester.tap(find.byKey(const ValueKey('audit-session-next-action')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(_completionCheckOverlayFinder(), findsNothing);
  });

  testWidgets('session shell only hydrates the visible station initially', (
    tester,
  ) async {
    final sessionRepository = MockAuditSessionRepository();
    final auditRepository = MockAuditRepository();
    final stationSampleRepository = MockStationSampleRepository();
    final activityLog = MockActivityLogRepository();
    final supabase = MockSupabaseService();
    final provider = AuditSessionProvider(
      repository: sessionRepository,
      activityLogRepository: activityLog,
      supabaseService: supabase,
    );

    when(() => sessionRepository.insertSession(any())).thenAnswer((_) async {});
    when(
      () => activityLog.log(
        any(),
        any(),
        entityType: any(named: 'entityType'),
        entityId: any(named: 'entityId'),
        details: any(named: 'details'),
      ),
    ).thenAnswer((_) async {});
    when(() => supabase.syncAuditSession(any())).thenAnswer((_) async {});
    when(
      () => auditRepository.getAuditsBySessionId(any()),
    ).thenAnswer((_) async => []);
    when(
      () => stationSampleRepository.getSamplesForStation(any(), any()),
    ).thenAnswer((_) async => []);

    await provider.startSession(
      context: AuditSessionContext(
        customerId: SessionTestFixtures.testCustomerId,
        hatcheryId: SessionTestFixtures.testHatcheryId,
        flockId: SessionTestFixtures.testFlockId,
        date: SessionTestFixtures.testVisitDate,
        breed: SessionTestFixtures.testBreed,
        selectedStationKeys: const ['egg', 'chicks', 'hatchers'],
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(create: (_) => CustomersProvider()),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: supabase),
          ),
          ChangeNotifierProvider(create: (_) => AppProvider()),
          ChangeNotifierProvider(create: (_) => GoveeCaptureProvider()),
        ],
        child: MaterialApp(
          home: AuditSessionScreen(
            auditRepository: auditRepository,
            stationSampleRepository: stationSampleRepository,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    verify(
      () => auditRepository.getAuditsBySessionId(provider.currentSession!.id),
    ).called(1);
    verify(
      () => stationSampleRepository.getSamplesForStation(
        provider.currentSession!.id,
        'egg',
      ),
    ).called(1);
    verifyNever(
      () => stationSampleRepository.getSamplesForStation(
        provider.currentSession!.id,
        'chicks',
      ),
    );
    verifyNever(
      () => stationSampleRepository.getSamplesForStation(
        provider.currentSession!.id,
        'hatchers',
      ),
    );
  });

  testWidgets('resumed Egg station hydrates saved audit data', (tester) async {
    final sessionRepository = MockAuditSessionRepository();
    final auditRepository = MockAuditRepository();
    final stationSampleRepository = MockStationSampleRepository();
    final activityLog = MockActivityLogRepository();
    final supabase = MockSupabaseService();
    final session = AuditSessionModel(
      id: 'session-egg-resume',
      customerId: SessionTestFixtures.testCustomerId,
      flockId: SessionTestFixtures.testFlockId,
      hatcheryId: SessionTestFixtures.testHatcheryId,
      date: SessionTestFixtures.testVisitDate,
      breed: SessionTestFixtures.testBreed,
      status: 'in_progress',
      selectedStationKeys: const ['egg'],
      stationsCompleted: const ['egg'],
      createdAt: SessionTestFixtures.testCreatedAt,
      updatedAt: SessionTestFixtures.testUpdatedAt,
    );
    final savedEggAudit = AuditModel.fromMap({
      ...makeEggStorageAudit(id: 'audit-egg-resume').toMap(),
      'sessionId': session.id,
      'esEggStorageDays': 9,
    });
    final provider = AuditSessionProvider(
      repository: sessionRepository,
      activityLogRepository: activityLog,
      supabaseService: supabase,
    );

    when(
      () => sessionRepository.getSessionById(session.id),
    ).thenAnswer((_) async => session);
    when(
      () => activityLog.log(
        any(),
        any(),
        entityType: any(named: 'entityType'),
        entityId: any(named: 'entityId'),
        details: any(named: 'details'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => auditRepository.getAuditsBySessionId(session.id),
    ).thenAnswer((_) async => [savedEggAudit]);
    when(
      () => stationSampleRepository.getSamplesForStation(session.id, 'egg'),
    ).thenAnswer((_) async => []);

    await provider.resumeSession(session.id);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(create: (_) => CustomersProvider()),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: supabase),
          ),
          ChangeNotifierProvider(create: (_) => AppProvider()),
          ChangeNotifierProvider(create: (_) => GoveeCaptureProvider()),
        ],
        child: MaterialApp(
          home: AuditSessionScreen(
            auditRepository: auditRepository,
            stationSampleRepository: stationSampleRepository,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.widgetWithText(TextField, '9'), findsOneWidget);
  });

  testWidgets('resumed Chicks station hydrates saved comparison samples', (
    tester,
  ) async {
    final sessionRepository = MockAuditSessionRepository();
    final auditRepository = MockAuditRepository();
    final stationSampleRepository = MockStationSampleRepository();
    final activityLog = MockActivityLogRepository();
    final supabase = MockSupabaseService();
    final session = AuditSessionModel(
      id: 'session-chicks-resume',
      customerId: SessionTestFixtures.testCustomerId,
      flockId: SessionTestFixtures.testFlockId,
      hatcheryId: SessionTestFixtures.testHatcheryId,
      date: SessionTestFixtures.testVisitDate,
      breed: SessionTestFixtures.testBreed,
      status: 'in_progress',
      selectedStationKeys: const ['chicks'],
      stationsCompleted: const ['chicks'],
      createdAt: SessionTestFixtures.testCreatedAt,
      updatedAt: SessionTestFixtures.testUpdatedAt,
    );
    final firstSample = AuditModel.fromMap({
      ...makeChickQualityAudit(id: 'audit-chicks-resume-1').toMap(),
      'sessionId': session.id,
      'sampleMode': 'compare',
      'compareGroupKey': 'chicks-group-1',
      'hatchNumber': 1,
      'chickAvgWeight': 40.0,
    });
    final secondSample = AuditModel.fromMap({
      ...makeChickQualityAudit(id: 'audit-chicks-resume-2').toMap(),
      'sessionId': session.id,
      'sampleMode': 'compare',
      'compareGroupKey': 'chicks-group-1',
      'hatchNumber': 2,
      'chickAvgWeight': 45.0,
    });
    final provider = AuditSessionProvider(
      repository: sessionRepository,
      activityLogRepository: activityLog,
      supabaseService: supabase,
    );

    when(
      () => sessionRepository.getSessionById(session.id),
    ).thenAnswer((_) async => session);
    when(
      () => activityLog.log(
        any(),
        any(),
        entityType: any(named: 'entityType'),
        entityId: any(named: 'entityId'),
        details: any(named: 'details'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => auditRepository.getAuditsBySessionId(session.id),
    ).thenAnswer((_) async => [secondSample, firstSample]);
    when(
      () => stationSampleRepository.getSamplesForStation(session.id, 'chicks'),
    ).thenAnswer((_) async => []);

    await provider.resumeSession(session.id);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(create: (_) => CustomersProvider()),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: supabase),
          ),
          ChangeNotifierProvider(create: (_) => AppProvider()),
          ChangeNotifierProvider(create: (_) => GoveeCaptureProvider()),
        ],
        child: MaterialApp(
          home: AuditSessionScreen(
            auditRepository: auditRepository,
            stationSampleRepository: stationSampleRepository,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Compare machines'), findsOneWidget);
    expect(find.text('M1'), findsOneWidget);
    expect(find.text('M2'), findsOneWidget);
  });

  testWidgets('resumed Hatch Analysis station hydrates saved breakout rows', (
    tester,
  ) async {
    final sessionRepository = MockAuditSessionRepository();
    final auditRepository = MockAuditRepository();
    final stationSampleRepository = MockStationSampleRepository();
    final activityLog = MockActivityLogRepository();
    final supabase = MockSupabaseService();
    final session = AuditSessionModel(
      id: 'session-hatch-analysis-resume',
      customerId: SessionTestFixtures.testCustomerId,
      flockId: SessionTestFixtures.testFlockId,
      hatcheryId: SessionTestFixtures.testHatcheryId,
      date: SessionTestFixtures.testVisitDate,
      breed: SessionTestFixtures.testBreed,
      status: 'in_progress',
      selectedStationKeys: const ['hatch_analysis_egg_breakouts'],
      stationsCompleted: const ['hatch_analysis_egg_breakouts'],
      createdAt: SessionTestFixtures.testCreatedAt,
      updatedAt: SessionTestFixtures.testUpdatedAt,
    );
    final firstBreakout = AuditModel.fromMap({
      ...makeHatchAnalysisAudit(
        id: 'audit-hatch-analysis-resume-1',
        hatchNumber: 1,
      ).toMap(),
      'sessionId': session.id,
      'sampleMode': 'compare',
      'compareGroupKey': 'hatch-analysis-group-1',
    });
    final secondBreakout = AuditModel.fromMap({
      ...makeHatchAnalysisAudit(
        id: 'audit-hatch-analysis-resume-2',
        hatchNumber: 2,
      ).toMap(),
      'sessionId': session.id,
      'sampleMode': 'compare',
      'compareGroupKey': 'hatch-analysis-group-1',
    });
    final provider = AuditSessionProvider(
      repository: sessionRepository,
      activityLogRepository: activityLog,
      supabaseService: supabase,
    );

    when(
      () => sessionRepository.getSessionById(session.id),
    ).thenAnswer((_) async => session);
    when(
      () => activityLog.log(
        any(),
        any(),
        entityType: any(named: 'entityType'),
        entityId: any(named: 'entityId'),
        details: any(named: 'details'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => auditRepository.getAuditsBySessionId(session.id),
    ).thenAnswer((_) async => [secondBreakout, firstBreakout]);
    when(
      () => stationSampleRepository.getSamplesForStation(
        session.id,
        'hatch_analysis_egg_breakouts',
      ),
    ).thenAnswer((_) async => []);

    await provider.resumeSession(session.id);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(create: (_) => CustomersProvider()),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: supabase),
          ),
          ChangeNotifierProvider(create: (_) => AppProvider()),
          ChangeNotifierProvider(create: (_) => GoveeCaptureProvider()),
        ],
        child: MaterialApp(
          home: AuditSessionScreen(
            auditRepository: auditRepository,
            stationSampleRepository: stationSampleRepository,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final screenElement = tester.element(find.byType(HatchAnalysisScreen));
    final stationProvider = Provider.of<AuditProvider>(
      screenElement,
      listen: false,
    );

    expect(stationProvider.drafts, hasLength(2));
    expect(stationProvider.drafts.map((draft) => draft.hatchNumber), [1, 2]);
  });

  testWidgets('chick quality session shows the station progress strip', (
    tester,
  ) async {
    final repository = MockAuditSessionRepository();
    final activityLog = MockActivityLogRepository();
    final supabase = MockSupabaseService();
    final provider = AuditSessionProvider(
      repository: repository,
      activityLogRepository: activityLog,
      supabaseService: supabase,
    );

    when(() => repository.insertSession(any())).thenAnswer((_) async {});
    when(
      () => activityLog.log(
        any(),
        any(),
        entityType: any(named: 'entityType'),
        entityId: any(named: 'entityId'),
        details: any(named: 'details'),
      ),
    ).thenAnswer((_) async {});
    when(() => supabase.syncAuditSession(any())).thenAnswer((_) async {});

    await provider.startSession(
      context: AuditSessionContext(
        customerId: SessionTestFixtures.testCustomerId,
        hatcheryId: SessionTestFixtures.testHatcheryId,
        flockId: SessionTestFixtures.testFlockId,
        date: SessionTestFixtures.testVisitDate,
        breed: SessionTestFixtures.testBreed,
        selectedStationKeys: const ['chicks'],
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(create: (_) => CustomersProvider()),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: supabase),
          ),
          ChangeNotifierProvider(create: (_) => AppProvider()),
        ],
        child: const MaterialApp(home: AuditSessionScreen()),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('audit-session-progress-shell')),
      findsOneWidget,
    );
    final progressCheckIcon = find.descendant(
      of: find.byKey(const ValueKey('audit-session-progress-shell')),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Icon && widget.icon == Icons.check && widget.size == 12,
        description: 'compact station progress check icon',
      ),
    );
    expect(progressCheckIcon, findsOneWidget);
    expect(
      find.byKey(const ValueKey('chick-quality-workbench')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('audit-session-navigation-footer')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chick-quality-footer')), findsNothing);
  });

  testWidgets('hatch analysis session hides the station progress strip', (
    tester,
  ) async {
    final repository = MockAuditSessionRepository();
    final activityLog = MockActivityLogRepository();
    final supabase = MockSupabaseService();
    final provider = AuditSessionProvider(
      repository: repository,
      activityLogRepository: activityLog,
      supabaseService: supabase,
    );

    when(() => repository.insertSession(any())).thenAnswer((_) async {});
    when(
      () => activityLog.log(
        any(),
        any(),
        entityType: any(named: 'entityType'),
        entityId: any(named: 'entityId'),
        details: any(named: 'details'),
      ),
    ).thenAnswer((_) async {});
    when(() => supabase.syncAuditSession(any())).thenAnswer((_) async {});

    await provider.startSession(
      context: AuditSessionContext(
        customerId: SessionTestFixtures.testCustomerId,
        hatcheryId: SessionTestFixtures.testHatcheryId,
        flockId: SessionTestFixtures.testFlockId,
        date: SessionTestFixtures.testVisitDate,
        breed: SessionTestFixtures.testBreed,
        selectedStationKeys: const ['hatch_analysis_egg_breakouts'],
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(create: (_) => CustomersProvider()),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: supabase),
          ),
          ChangeNotifierProvider(create: (_) => AppProvider()),
        ],
        child: const MaterialApp(home: AuditSessionScreen()),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('audit-session-progress-shell')),
      findsNothing,
    );
    expect(find.text('Breakout Type'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('audit-session-navigation-footer')),
      findsOneWidget,
    );
  });

  testWidgets('supported audit room station shows Govee readings button', (
    tester,
  ) async {
    final repository = MockAuditSessionRepository();
    final activityLog = MockActivityLogRepository();
    final supabase = MockSupabaseService();
    final provider = AuditSessionProvider(
      repository: repository,
      activityLogRepository: activityLog,
      supabaseService: supabase,
    );

    when(() => repository.insertSession(any())).thenAnswer((_) async {});
    when(
      () => activityLog.log(
        any(),
        any(),
        entityType: any(named: 'entityType'),
        entityId: any(named: 'entityId'),
        details: any(named: 'details'),
      ),
    ).thenAnswer((_) async {});
    when(() => supabase.syncAuditSession(any())).thenAnswer((_) async {});

    await provider.startSession(
      context: AuditSessionContext(
        customerId: SessionTestFixtures.testCustomerId,
        hatcheryId: SessionTestFixtures.testHatcheryId,
        flockId: SessionTestFixtures.testFlockId,
        date: SessionTestFixtures.testVisitDate,
        breed: SessionTestFixtures.testBreed,
        selectedStationKeys: const ['egg'],
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(create: (_) => CustomersProvider()),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: supabase),
          ),
          ChangeNotifierProvider(create: (_) => AppProvider()),
          ChangeNotifierProvider(create: (_) => GoveeCaptureProvider()),
        ],
        child: const MaterialApp(home: AuditSessionScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Govee readings'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('audit-open-govee-readings')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('audit-open-govee-readings')),
        matching: find.byIcon(Icons.device_thermostat_outlined),
      ),
      findsNothing,
    );
  });

  testWidgets('Govee readings button opens the floating capture panel', (
    tester,
  ) async {
    final repository = MockAuditSessionRepository();
    final activityLog = MockActivityLogRepository();
    final supabase = MockSupabaseService();
    final goveeRepository = MockGoveeCaptureRepository();
    final goveeService = MockGoveeService();
    final provider = AuditSessionProvider(
      repository: repository,
      activityLogRepository: activityLog,
      supabaseService: supabase,
    );

    when(() => repository.insertSession(any())).thenAnswer((_) async {});
    when(
      () => activityLog.log(
        any(),
        any(),
        entityType: any(named: 'entityType'),
        entityId: any(named: 'entityId'),
        details: any(named: 'details'),
      ),
    ).thenAnswer((_) async {});
    when(() => supabase.syncAuditSession(any())).thenAnswer((_) async {});
    _stubEmptyGoveeRepository(goveeRepository);
    _stubIdleGoveeService(goveeService);

    await provider.startSession(
      context: AuditSessionContext(
        customerId: SessionTestFixtures.testCustomerId,
        hatcheryId: SessionTestFixtures.testHatcheryId,
        flockId: SessionTestFixtures.testFlockId,
        date: SessionTestFixtures.testVisitDate,
        breed: SessionTestFixtures.testBreed,
        selectedStationKeys: const ['egg'],
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(create: (_) => CustomersProvider()),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: supabase),
          ),
          ChangeNotifierProvider(create: (_) => AppProvider()),
          ChangeNotifierProvider(
            create: (_) => GoveeCaptureProvider(
              repository: goveeRepository,
              goveeService: goveeService,
              enablePhaseTimer: false,
            ),
          ),
        ],
        child: const MaterialApp(home: AuditSessionScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('audit-open-govee-readings')));
    await tester.pumpAndSettle();

    expect(find.text('Govee capture'), findsOneWidget);
    expect(find.text('Egg storage room'), findsWidgets);
    expect(find.text('Govee'), findsNothing);
  });

  testWidgets('unsupported audit station does not show Govee readings button', (
    tester,
  ) async {
    final repository = MockAuditSessionRepository();
    final activityLog = MockActivityLogRepository();
    final supabase = MockSupabaseService();
    final provider = AuditSessionProvider(
      repository: repository,
      activityLogRepository: activityLog,
      supabaseService: supabase,
    );

    when(() => repository.insertSession(any())).thenAnswer((_) async {});
    when(
      () => activityLog.log(
        any(),
        any(),
        entityType: any(named: 'entityType'),
        entityId: any(named: 'entityId'),
        details: any(named: 'details'),
      ),
    ).thenAnswer((_) async {});
    when(() => supabase.syncAuditSession(any())).thenAnswer((_) async {});

    await provider.startSession(
      context: AuditSessionContext(
        customerId: SessionTestFixtures.testCustomerId,
        hatcheryId: SessionTestFixtures.testHatcheryId,
        flockId: SessionTestFixtures.testFlockId,
        date: SessionTestFixtures.testVisitDate,
        breed: SessionTestFixtures.testBreed,
        selectedStationKeys: const ['hatch_analysis_egg_breakouts'],
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(create: (_) => CustomersProvider()),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: supabase),
          ),
          ChangeNotifierProvider(create: (_) => AppProvider()),
          ChangeNotifierProvider(create: (_) => GoveeCaptureProvider()),
        ],
        child: const MaterialApp(home: AuditSessionScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Govee readings'), findsNothing);
    expect(
      find.byKey(const ValueKey('audit-open-govee-readings')),
      findsNothing,
    );
  });
}

Finder _completionCheckOverlayFinder() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Icon && widget.icon == Icons.check && widget.size == 48,
    description: 'large completion check overlay',
  );
}

void _stubEmptyGoveeRepository(MockGoveeCaptureRepository repository) {
  when(
    () => repository.getCaptureForScope(
      customerId: any(named: 'customerId'),
      hatcheryId: any(named: 'hatcheryId'),
      stationKey: any(named: 'stationKey'),
      place: any(named: 'place'),
      machineId: any(named: 'machineId'),
      captureDate: any(named: 'captureDate'),
    ),
  ).thenAnswer((_) async => null);
  when(
    () => repository.getCapturesForDashboard(
      customerId: any(named: 'customerId'),
      hatcheryId: any(named: 'hatcheryId'),
      captureDate: any(named: 'captureDate'),
    ),
  ).thenAnswer((_) async => const []);
}

void _stubIdleGoveeService(MockGoveeService service) {
  when(() => service.initializeBle()).thenAnswer((_) async {});
  when(() => service.setAutoReconnectEnabled(any())).thenReturn(null);
  when(() => service.isAvailable).thenReturn(false);
  when(() => service.isConnected).thenReturn(false);
  when(() => service.isGattConnected).thenReturn(false);
  when(() => service.isGattConnecting).thenReturn(false);
  when(() => service.isScanning).thenReturn(false);
  when(() => service.deviceName).thenReturn(null);
  when(() => service.deviceId).thenReturn(null);
  when(() => service.signalStrength).thenReturn(null);
  when(() => service.latestReading).thenReturn(null);
  when(() => service.lastSeenAt).thenReturn(null);
  when(() => service.diagnostics).thenReturn(const []);
  when(() => service.readings).thenAnswer((_) => const Stream.empty());
}
