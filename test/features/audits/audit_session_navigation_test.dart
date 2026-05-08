import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/data/models/audit_session_model.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/data/repositories/audit_repository.dart';
import 'package:hatchaudit/data/repositories/activity_log_repository.dart';
import 'package:hatchaudit/data/repositories/audit_session_repository.dart';
import 'package:hatchaudit/data/repositories/station_sample_repository.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/providers/audit_session_provider.dart';
import 'package:hatchaudit/features/audits/screens/audit_session_screen.dart';
import 'package:hatchaudit/features/audits/screens/chick_quality_screen.dart';
import 'package:hatchaudit/features/audits/screens/hatch_analysis_screen.dart';
import 'package:hatchaudit/features/audits/screens/hatcher_optimizing_screen.dart';
import 'package:hatchaudit/features/audits/screens/setter_optimizing_screen.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/features/govee/providers/govee_capture_provider.dart';
import 'package:hatchaudit/providers/app_provider.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
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
    registerFallbackValue(makeChickQualityAudit(id: 'fallback-audit'));
    registerFallbackValue(
      StationSampleModel(
        id: 'fallback-sample',
        auditSessionId: 'fallback-session',
        stationType: 'chicks',
        sampleIndex: 1,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
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
    expect(find.text('Hatch Analysis'), findsOneWidget);

    final hatchAnalysisLabel = tester.widget<Text>(find.text('Hatch Analysis'));
    expect(hatchAnalysisLabel.maxLines, 2);
    expect(hatchAnalysisLabel.overflow, isNot(TextOverflow.ellipsis));

    final appBar = tester.widget<AppBar>(find.byType(AppBar).first);
    expect(appBar.toolbarHeight, kToolbarHeight);

    final progressSize = tester.getSize(
      find.byKey(const ValueKey('audit-session-progress-shell')),
    );
    expect(progressSize.height, lessThanOrEqualTo(82));

    final footerSize = tester.getSize(
      find.byKey(const ValueKey('audit-session-navigation-footer')),
    );
    expect(footerSize.height, lessThanOrEqualTo(78));
  });

  testWidgets('dirty station navigation saves without leave dialog', (
    tester,
  ) async {
    final repository = MockAuditSessionRepository();
    final auditRepository = MockAuditRepository();
    final stationSampleRepository = MockStationSampleRepository();
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
    when(() => supabase.syncAudit(any())).thenAnswer((_) async {});
    when(
      () => repository.markStationCompleted(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => repository.getSessionById(any()),
    ).thenAnswer((_) async => provider.currentSession);
    when(
      () => auditRepository.getAuditsBySessionId(any()),
    ).thenAnswer((_) async => []);
    when(
      () => stationSampleRepository.getSamplesForStation(any(), any()),
    ).thenAnswer((_) async => []);
    when(
      () => auditRepository.getAuditById(any()),
    ).thenAnswer((_) async => null);
    when(() => auditRepository.insertAudit(any())).thenAnswer((_) async {});
    when(
      () => stationSampleRepository.upsertSample(any()),
    ).thenAnswer((_) async {});
    when(
      () => stationSampleRepository.deleteSample(any()),
    ).thenAnswer((_) async {});
    when(() => auditRepository.deleteAudit(any())).thenAnswer((_) async {});

    await provider.startSession(
      context: AuditSessionContext(
        customerId: SessionTestFixtures.testCustomerId,
        hatcheryId: SessionTestFixtures.testHatcheryId,
        flockId: SessionTestFixtures.testFlockId,
        date: SessionTestFixtures.testVisitDate,
        breed: SessionTestFixtures.testBreed,
        selectedStationKeys: const ['chicks', 'setters'],
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
            activityLogRepository: activityLog,
            supabaseService: supabase,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final screenElement = tester.element(find.byType(ChickQualityScreen));
    final stationProvider = Provider.of<AuditProvider>(
      screenElement,
      listen: false,
    );
    stationProvider.updateField('pasgarFinalScore', 100.0);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('audit-session-next-action')));
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);

    await tester.pumpAndSettle();

    expect(provider.currentStationIndex, 1);
    verify(() => auditRepository.insertAudit(any())).called(1);
    verify(() => stationSampleRepository.upsertSample(any())).called(1);
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

    expect(find.text('Multi House Samples'), findsOneWidget);
    expect(find.text('Sample 1'), findsOneWidget);
    expect(find.text('Sample 2'), findsOneWidget);
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

  testWidgets('resumed Setters station hydrates saved machine samples', (
    tester,
  ) async {
    final sessionRepository = MockAuditSessionRepository();
    final auditRepository = MockAuditRepository();
    final stationSampleRepository = MockStationSampleRepository();
    final activityLog = MockActivityLogRepository();
    final supabase = MockSupabaseService();
    final session = AuditSessionModel(
      id: 'session-setters-resume',
      customerId: SessionTestFixtures.testCustomerId,
      flockId: SessionTestFixtures.testFlockId,
      hatcheryId: SessionTestFixtures.testHatcheryId,
      date: SessionTestFixtures.testVisitDate,
      breed: SessionTestFixtures.testBreed,
      status: 'in_progress',
      selectedStationKeys: const ['setters'],
      stationsCompleted: const ['setters'],
      createdAt: SessionTestFixtures.testCreatedAt,
      updatedAt: SessionTestFixtures.testUpdatedAt,
    );
    final firstMachine = AuditModel.fromMap({
      ...makeSetterAudit(id: 'audit-setters-resume-1').toMap(),
      'sessionId': session.id,
      'sampleMode': 'compare',
      'compareGroupKey': 'setters-group-1',
      'hatchNumber': 1,
      'setterId': 'setter-a',
      'soSetterId': 'setter-a',
      'soEstAvg': 99.5,
    });
    final secondMachine = AuditModel.fromMap({
      ...makeSetterAudit(id: 'audit-setters-resume-2').toMap(),
      'sessionId': session.id,
      'sampleMode': 'compare',
      'compareGroupKey': 'setters-group-1',
      'hatchNumber': 2,
      'setterId': 'setter-b',
      'soSetterId': 'setter-b',
      'soEstAvg': 100.1,
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
    ).thenAnswer((_) async => [secondMachine, firstMachine]);
    when(
      () => stationSampleRepository.getSamplesForStation(session.id, 'setters'),
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

    final screenElement = tester.element(find.byType(SetterOptimizingScreen));
    final stationProvider = Provider.of<AuditProvider>(
      screenElement,
      listen: false,
    );

    expect(stationProvider.isReadOnly, isFalse);
    expect(stationProvider.drafts, hasLength(2));
    expect(stationProvider.drafts.map((draft) => draft.hatchNumber), [1, 2]);
  });

  testWidgets('resumed Hatchers station hydrates saved machine samples', (
    tester,
  ) async {
    final sessionRepository = MockAuditSessionRepository();
    final auditRepository = MockAuditRepository();
    final stationSampleRepository = MockStationSampleRepository();
    final activityLog = MockActivityLogRepository();
    final supabase = MockSupabaseService();
    final session = AuditSessionModel(
      id: 'session-hatchers-resume',
      customerId: SessionTestFixtures.testCustomerId,
      flockId: SessionTestFixtures.testFlockId,
      hatcheryId: SessionTestFixtures.testHatcheryId,
      date: SessionTestFixtures.testVisitDate,
      breed: SessionTestFixtures.testBreed,
      status: 'in_progress',
      selectedStationKeys: const ['hatchers'],
      stationsCompleted: const ['hatchers'],
      createdAt: SessionTestFixtures.testCreatedAt,
      updatedAt: SessionTestFixtures.testUpdatedAt,
    );
    final firstMachine = AuditModel.fromMap({
      ...makeHatcherAudit(id: 'audit-hatchers-resume-1').toMap(),
      'sessionId': session.id,
      'sampleMode': 'compare',
      'compareGroupKey': 'hatchers-group-1',
      'hatchNumber': 1,
      'hatcherId': 'hatcher-a',
      'hoHatcherId': 'hatcher-a',
      'hoCvtAvg': 103.8,
    });
    final secondMachine = AuditModel.fromMap({
      ...makeHatcherAudit(id: 'audit-hatchers-resume-2').toMap(),
      'sessionId': session.id,
      'sampleMode': 'compare',
      'compareGroupKey': 'hatchers-group-1',
      'hatchNumber': 2,
      'hatcherId': 'hatcher-b',
      'hoHatcherId': 'hatcher-b',
      'hoCvtAvg': 104.3,
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
    ).thenAnswer((_) async => [secondMachine, firstMachine]);
    when(
      () =>
          stationSampleRepository.getSamplesForStation(session.id, 'hatchers'),
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

    final screenElement = tester.element(find.byType(HatcherOptimizingScreen));
    final stationProvider = Provider.of<AuditProvider>(
      screenElement,
      listen: false,
    );

    expect(stationProvider.isReadOnly, isFalse);
    expect(stationProvider.drafts, hasLength(2));
    expect(stationProvider.drafts.map((draft) => draft.hatchNumber), [1, 2]);
  });

  testWidgets('Setters session opens with sample mode controls visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(536, 768);
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
        selectedStationKeys: const ['setters'],
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
    await tester.pumpAndSettle();

    final singleSample = find.text('Single Sample');
    expect(singleSample, findsOneWidget);
    expect(tester.getRect(singleSample).top, greaterThanOrEqualTo(0));
  });

  testWidgets('Hatchers session opens with sample mode controls visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(536, 768);
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
        selectedStationKeys: const ['hatchers'],
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
    await tester.pumpAndSettle();

    final singleSample = find.text('Single Sample');
    expect(singleSample, findsOneWidget);
    expect(tester.getRect(singleSample).top, greaterThanOrEqualTo(0));
  });

  testWidgets('chick quality session hides the station progress strip', (
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
      findsNothing,
    );
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

  testWidgets(
    'supported audit room station has no station-owned Govee button',
    (tester) async {
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

      expect(find.text('Govee readings'), findsNothing);
      expect(
        find.byKey(const ValueKey('audit-open-govee-readings')),
        findsNothing,
      );
    },
  );

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
