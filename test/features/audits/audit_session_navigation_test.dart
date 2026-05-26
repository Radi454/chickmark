import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/audit_session_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/panel_sample_model.dart';
import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/data/repositories/audit_repository.dart';
import 'package:hatchaudit/data/repositories/activity_log_repository.dart';
import 'package:hatchaudit/data/repositories/audit_session_repository.dart';
import 'package:hatchaudit/data/repositories/govee_capture_repository.dart';
import 'package:hatchaudit/data/repositories/panel_sample_repository.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/models/egg_breakout_sample.dart';
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

class MockPanelSampleRepository extends Mock implements PanelSampleRepository {}

class MockActivityLogRepository extends Mock implements ActivityLogRepository {}

class MockSupabaseService extends Mock implements SupabaseService {}

class MockGoveeCaptureRepository extends Mock
    implements GoveeCaptureRepository {}

class MockGoveeService extends Mock implements GoveeService {}

Map<String, dynamic> _panelRow({
  required String sessionId,
  required String id,
  String? house,
  String? setter,
  String? hatcher,
  String? tray,
  Map<String, Object?> values = const {},
}) {
  return {
    'id': id,
    'sessionId': sessionId,
    'customerId': SessionTestFixtures.testCustomerId,
    'flockId': SessionTestFixtures.testFlockId,
    'hatcheryId': SessionTestFixtures.testHatcheryId,
    'date': SessionTestFixtures.testVisitDate.toIso8601String().split('T')[0],
    'breed': SessionTestFixtures.testBreed,
    'house': house,
    'setter': setter,
    'hatcher': hatcher,
    'tray': tray,
    'createdAt': SessionTestFixtures.testCreatedAt.toIso8601String(),
    'updatedAt': SessionTestFixtures.testUpdatedAt.toIso8601String(),
    ...values,
  };
}

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
    registerFallbackValue(DateTime(2026));
    registerFallbackValue(TemperaturePlace.eggStorageRoom);
    registerFallbackValue(
      PanelRecord(
        id: 'fallback-panel',
        tableName: 'egg_storage',
        sessionId: 'fallback-session',
        customerId: 'fallback-customer',
        date: DateTime(2026),
      ),
    );
    registerFallbackValue(<PanelSampleRecord>[]);
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
      when(
        () => repository.findInProgressSession(
          customerId: SessionTestFixtures.testCustomerId,
          flockId: SessionTestFixtures.testFlockId,
          hatcheryId: SessionTestFixtures.testHatcheryId,
          date: any(named: 'date'),
        ),
      ).thenAnswer((_) async => null);
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
            theme: ThemeData(splashFactory: NoSplash.splashFactory),
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
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
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

  testWidgets(
    'station selection shows saved badge and remove button for saved row',
    (tester) async {
      final repository = MockAuditSessionRepository();
      final supabase = MockSupabaseService();
      final provider = AuditSessionProvider(
        repository: repository,
        supabaseService: supabase,
      );
      final session = AuditSessionModel.fromMap(
        makeAuditSessionRow(
          id: 'existing-session',
          selectedStationKeys: ['egg'],
          stationsCompleted: ['egg'],
        ),
      );

      when(
        () => repository.findInProgressSession(
          customerId: SessionTestFixtures.testCustomerId,
          flockId: SessionTestFixtures.testFlockId,
          hatcheryId: SessionTestFixtures.testHatcheryId,
          date: any(named: 'date'),
        ),
      ).thenAnswer((_) async => session);
      when(() => supabase.syncAuditSession(any())).thenAnswer((_) async {});

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: provider),
            ChangeNotifierProvider(
              create: (_) => AuthProvider(supabaseService: supabase),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(splashFactory: NoSplash.splashFactory),
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
      await tester.pumpAndSettle();

      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Continue Visit'), findsOneWidget);
      expect(find.byTooltip('Remove station'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove station'));
      await tester.pumpAndSettle();

      expect(find.text('Saved'), findsNothing);
    },
  );

  testWidgets('resumed station selection can add unsaved stations', (
    tester,
  ) async {
    final repository = MockAuditSessionRepository();
    final supabase = MockSupabaseService();
    final provider = AuditSessionProvider(
      repository: repository,
      supabaseService: supabase,
    );
    final existing = AuditSessionModel.fromMap(
      makeAuditSessionRow(
        id: 'existing-session',
        selectedStationKeys: ['egg'],
        stationsCompleted: ['egg'],
      ),
    );
    final updated = existing.copyWith(
      selectedStationKeys: const ['egg', 'chicks'],
      stationsCompleted: const ['egg'],
    );

    when(
      () => repository.findInProgressSession(
        customerId: SessionTestFixtures.testCustomerId,
        flockId: SessionTestFixtures.testFlockId,
        hatcheryId: SessionTestFixtures.testHatcheryId,
        date: any(named: 'date'),
      ),
    ).thenAnswer((_) async => existing);
    when(
      () => repository.updateSelectedStationKeys('existing-session', const [
        'egg',
        'chicks',
      ]),
    ).thenAnswer((_) async {});
    when(
      () => repository.getSessionById('existing-session'),
    ).thenAnswer((_) async => updated);
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
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
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
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chicks'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Continue Visit'));
    await tester.pump();

    verify(
      () => repository.updateSelectedStationKeys('existing-session', const [
        'egg',
        'chicks',
      ]),
    ).called(1);
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
    expect(
      find.byKey(const ValueKey('audit-session-progress-current-marker-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('audit-session-progress-current-marker-1')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('audit-session-progress-shell')),
        matching: find.byIcon(Icons.radio_button_checked),
      ),
      findsNothing,
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

  testWidgets('incomplete station can continue without marking completed', (
    tester,
  ) async {
    final sessionRepository = MockAuditSessionRepository();
    final auditRepository = MockAuditRepository();
    final panelSampleRepository = MockPanelSampleRepository();
    final supabase = MockSupabaseService();
    final session = AuditSessionModel.fromMap(
      makeAuditSessionRow(
        id: 'incomplete-forward-session',
        selectedStationKeys: ['egg', 'chicks'],
        stationsCompleted: const [],
      ),
    );
    final provider = AuditSessionProvider(
      repository: sessionRepository,
      supabaseService: supabase,
    );

    when(
      () => sessionRepository.getSessionById(session.id),
    ).thenAnswer((_) async => session);
    when(
      () => sessionRepository.markStationCompleted(session.id, 'egg'),
    ).thenAnswer((_) async {});
    when(() => supabase.syncAuditSession(any())).thenAnswer((_) async {});
    _stubEmptyPanelPersistence(panelSampleRepository, session.id);

    await provider.resumeSession(session.id, initialStationIndex: 0);

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
            panelSampleRepository: panelSampleRepository,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('audit-session-next-action')));
    await tester.pumpAndSettle();

    expect(find.text('Continue without completing?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump();
    await tester.pump();

    expect(provider.currentStationIndex, 1);
    verifyNever(
      () => sessionRepository.markStationCompleted(session.id, 'egg'),
    );
  });

  testWidgets('final incomplete station stays in progress after confirmation', (
    tester,
  ) async {
    final sessionRepository = MockAuditSessionRepository();
    final auditRepository = MockAuditRepository();
    final panelSampleRepository = MockPanelSampleRepository();
    final supabase = MockSupabaseService();
    final session = AuditSessionModel.fromMap(
      makeAuditSessionRow(
        id: 'incomplete-final-session',
        selectedStationKeys: ['egg'],
        stationsCompleted: const [],
        status: 'in_progress',
      ),
    );
    final provider = AuditSessionProvider(
      repository: sessionRepository,
      supabaseService: supabase,
    );

    when(
      () => sessionRepository.getSessionById(session.id),
    ).thenAnswer((_) async => session);
    when(
      () => sessionRepository.markStationCompleted(session.id, 'egg'),
    ).thenAnswer((_) async {});
    when(
      () => sessionRepository.updateSessionProgress(session.id, any()),
    ).thenAnswer((_) async {});
    when(() => supabase.syncAuditSession(any())).thenAnswer((_) async {});
    _stubEmptyPanelPersistence(panelSampleRepository, session.id);

    await provider.resumeSession(session.id, initialStationIndex: 0);

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
            panelSampleRepository: panelSampleRepository,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('audit-session-next-action')));
    await tester.pumpAndSettle();

    expect(find.text('Continue without completing?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump();
    await tester.pump();

    expect(provider.currentSession?.status, 'in_progress');
    verifyNever(
      () => sessionRepository.markStationCompleted(session.id, 'egg'),
    );
    verifyNever(
      () => sessionRepository.updateSessionProgress(session.id, any()),
    );
  });

  testWidgets('completed review uses next until the final station', (
    tester,
  ) async {
    final sessionRepository = MockAuditSessionRepository();
    final auditRepository = MockAuditRepository();
    final panelSampleRepository = MockPanelSampleRepository();
    final activityLog = MockActivityLogRepository();
    final supabase = MockSupabaseService();
    final session = AuditSessionModel.fromMap(
      makeAuditSessionRow(
        id: 'completed-review-session',
        status: 'completed',
        selectedStationKeys: ['egg', 'chicks'],
        stationsCompleted: ['egg', 'chicks'],
        completedAt: SessionTestFixtures.testUpdatedAt,
      ),
    );
    final provider = AuditSessionProvider(
      repository: sessionRepository,
      activityLogRepository: activityLog,
      supabaseService: supabase,
    );

    when(
      () => sessionRepository.getSessionById(session.id),
    ).thenAnswer((_) async => session);
    when(
      () => sessionRepository.markStationCompleted(any(), any()),
    ).thenAnswer((_) async {});
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
      () => panelSampleRepository.getRowsBySessionId(any(), session.id),
    ).thenAnswer((_) async => []);
    when(
      () => panelSampleRepository.getRowsBySessionId('egg_storage', session.id),
    ).thenAnswer(
      (_) async => [
        _panelRow(
          sessionId: session.id,
          id: 'completed-review-egg-storage',
          values: const {'storagePeriodDays': 4},
        ),
      ],
    );
    when(
      () => panelSampleRepository.getRowsBySessionId('egg_quality', session.id),
    ).thenAnswer((_) async => []);
    when(
      () => panelSampleRepository.savePanelWithSamples(
        panel: any(named: 'panel'),
        samples: any(named: 'samples'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => panelSampleRepository.deleteHierarchyRowsBySessionId(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => panelSampleRepository.deleteHierarchyRowsBySessionIdExcept(
        any(),
        any(),
        any(),
        keepHierarchyRows: any(named: 'keepHierarchyRows'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => panelSampleRepository.deleteRowsBySessionId(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => panelSampleRepository.deleteRowsBySessionIdForSampleIds(
        any(),
        any(),
        any(),
      ),
    ).thenAnswer((_) async {});
    when(() => supabase.syncAuditSession(any())).thenAnswer((_) async {});

    await provider.resumeSession(session.id, initialStationIndex: 0);

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
            panelSampleRepository: panelSampleRepository,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.widgetWithText(ElevatedButton, 'Next Station'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Save'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('audit-session-next-action')));
    await tester.pump();
    await tester.pump();

    expect(provider.currentStationIndex, 1);
    expect(find.widgetWithText(ElevatedButton, 'Save'), findsOneWidget);
  });

  testWidgets('session shell only hydrates the visible station initially', (
    tester,
  ) async {
    final sessionRepository = MockAuditSessionRepository();
    final auditRepository = MockAuditRepository();
    final panelSampleRepository = MockPanelSampleRepository();
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
      () => panelSampleRepository.getRowsBySessionId(any(), any()),
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
            panelSampleRepository: panelSampleRepository,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    verify(
      () => panelSampleRepository.getRowsBySessionId(
        'egg_storage',
        provider.currentSession!.id,
      ),
    ).called(1);
    verify(
      () => panelSampleRepository.getRowsBySessionId(
        'egg_quality',
        provider.currentSession!.id,
      ),
    ).called(1);
    verifyNever(
      () => panelSampleRepository.getRowsBySessionId(
        'chick_quality',
        provider.currentSession!.id,
      ),
    );
    verifyNever(
      () => panelSampleRepository.getRowsBySessionId(
        'hatcher_optimizing',
        provider.currentSession!.id,
      ),
    );
  });

  testWidgets(
    'session switch with same station key uses a fresh station provider',
    (tester) async {
      final sessionRepository = MockAuditSessionRepository();
      final auditRepository = MockAuditRepository();
      final panelSampleRepository = MockPanelSampleRepository();
      final supabase = MockSupabaseService();
      final firstSession = AuditSessionModel.fromMap(
        makeAuditSessionRow(
          id: 'first-session',
          selectedStationKeys: const ['egg'],
        ),
      );
      final secondSession = AuditSessionModel.fromMap(
        makeAuditSessionRow(
          id: 'second-session',
          selectedStationKeys: const ['egg'],
        ),
      );
      final provider = AuditSessionProvider(
        repository: sessionRepository,
        supabaseService: supabase,
      );

      when(
        () => sessionRepository.getSessionById(firstSession.id),
      ).thenAnswer((_) async => firstSession);
      when(
        () => sessionRepository.getSessionById(secondSession.id),
      ).thenAnswer((_) async => secondSession);
      when(() => supabase.syncAuditSession(any())).thenAnswer((_) async {});
      when(
        () => panelSampleRepository.getRowsBySessionId(any(), any()),
      ).thenAnswer((_) async => []);

      await provider.resumeSession(firstSession.id, initialStationIndex: 0);

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
              panelSampleRepository: panelSampleRepository,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final firstStationProvider = Provider.of<AuditProvider>(
        tester.element(find.byType(EggStorageScreen)),
        listen: false,
      );

      await provider.resumeSession(secondSession.id, initialStationIndex: 0);
      await tester.pump();
      await tester.pump();

      final secondStationProvider = Provider.of<AuditProvider>(
        tester.element(find.byType(EggStorageScreen)),
        listen: false,
      );

      expect(secondStationProvider, isNot(same(firstStationProvider)));
    },
  );

  testWidgets('resumed Egg station hydrates saved audit data', (tester) async {
    final sessionRepository = MockAuditSessionRepository();
    final auditRepository = MockAuditRepository();
    final panelSampleRepository = MockPanelSampleRepository();
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
      () => panelSampleRepository.getRowsBySessionId('egg_storage', session.id),
    ).thenAnswer(
      (_) async => [
        _panelRow(
          sessionId: session.id,
          id: 'egg-storage-row',
          values: const {'storagePeriodDays': 9},
        ),
      ],
    );
    when(
      () => panelSampleRepository.getRowsBySessionId('egg_quality', session.id),
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
            panelSampleRepository: panelSampleRepository,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.widgetWithText(TextField, '9'), findsNWidgets(2));
  });

  testWidgets(
    'resumed Egg station hydrates quality hierarchy when storage is pooled',
    (tester) async {
      final sessionRepository = MockAuditSessionRepository();
      final auditRepository = MockAuditRepository();
      final panelSampleRepository = MockPanelSampleRepository();
      final activityLog = MockActivityLogRepository();
      final supabase = MockSupabaseService();
      final session = AuditSessionModel(
        id: 'session-egg-hierarchy-resume',
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
        () =>
            panelSampleRepository.getRowsBySessionId('egg_storage', session.id),
      ).thenAnswer(
        (_) async => [
          _panelRow(
            sessionId: session.id,
            id: 'egg-storage-pooled',
            values: const {'storagePeriodDays': 4},
          ),
        ],
      );
      when(
        () =>
            panelSampleRepository.getRowsBySessionId('egg_quality', session.id),
      ).thenAnswer(
        (_) async => [
          _panelRow(
            sessionId: session.id,
            id: 'egg-quality-house-1',
            house: 'H1',
            values: const {'eggSampleSize': 1, 'eggWeightsJson': '[50.0]'},
          ),
          _panelRow(
            sessionId: session.id,
            id: 'egg-quality-house-1-machine-1',
            house: 'H1',
            setter: 'S1',
            hatcher: 'H1',
            values: const {'eggSampleSize': 1, 'eggWeightsJson': '[51.0]'},
          ),
          _panelRow(
            sessionId: session.id,
            id: 'egg-quality-house-1-machine-2',
            house: 'H1',
            setter: 'S2',
            hatcher: 'H2',
            values: const {'eggSampleSize': 1, 'eggWeightsJson': '[52.0]'},
          ),
        ],
      );

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
              panelSampleRepository: panelSampleRepository,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('House scope'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'H1'), findsOneWidget);
      expect(find.text('Machine scope'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'S1H1'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'S2H2'), findsOneWidget);
    },
  );

  testWidgets('resumed Chicks station hydrates saved comparison samples', (
    tester,
  ) async {
    final sessionRepository = MockAuditSessionRepository();
    final auditRepository = MockAuditRepository();
    final panelSampleRepository = MockPanelSampleRepository();
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
      () =>
          panelSampleRepository.getRowsBySessionId('chick_quality', session.id),
    ).thenAnswer(
      (_) async => [
        _panelRow(
          sessionId: session.id,
          id: 'chick-quality-row-1',
          setter: 'S1',
          hatcher: 'H1',
          values: const {'pasgarFinalScore': 95.0},
        ),
        _panelRow(
          sessionId: session.id,
          id: 'chick-quality-row-2',
          setter: 'S2',
          hatcher: 'H2',
          values: const {'pasgarFinalScore': 96.0},
        ),
      ],
    );
    when(
      () =>
          panelSampleRepository.getRowsBySessionId('chick_weights', session.id),
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
            panelSampleRepository: panelSampleRepository,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Machine scope'), findsOneWidget);
    expect(find.text('S1H1'), findsOneWidget);
    expect(find.text('S2H2'), findsOneWidget);
  });

  testWidgets('resumed Hatch Analysis station hydrates saved breakout rows', (
    tester,
  ) async {
    final sessionRepository = MockAuditSessionRepository();
    final auditRepository = MockAuditRepository();
    final panelSampleRepository = MockPanelSampleRepository();
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
      () => panelSampleRepository.getRowsBySessionId(
        'fresh_egg_breakout',
        session.id,
      ),
    ).thenAnswer((_) async => []);
    when(
      () => panelSampleRepository.getRowsBySessionId(
        'candled_egg_breakout',
        session.id,
      ),
    ).thenAnswer((_) async => []);
    when(
      () => panelSampleRepository.getRowsBySessionId(
        'residue_breakout',
        session.id,
      ),
    ).thenAnswer(
      (_) async => [
        _panelRow(
          sessionId: session.id,
          id: 'residue-row-1',
          tray: 'Tray 1',
          values: const {
            'traySize': 150,
            'infertileCount': 5,
            'earlyDeadCount': 2,
          },
        ),
        _panelRow(
          sessionId: session.id,
          id: 'residue-row-2',
          tray: 'Tray 2',
          values: const {
            'traySize': 150,
            'infertileCount': 6,
            'lateDeadCount': 3,
          },
        ),
      ],
    );

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
            panelSampleRepository: panelSampleRepository,
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

    expect(stationProvider.drafts, hasLength(1));
    final breakoutRows = EggBreakoutSampleEntry.decodeList(
      stationProvider.activeDraft.ebTrayBreakoutJson,
    );
    expect(breakoutRows.map((entry) => entry.tray), ['Tray 1', 'Tray 2']);
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
    expect(
      find.byKey(const ValueKey('audit-session-progress-current-marker-0')),
      findsOneWidget,
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

  testWidgets('hatch analysis session shows the station progress strip', (
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
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('audit-session-progress-current-marker-0')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('audit-session-progress-shell')),
        matching: find.text('Hatch'),
      ),
      findsOneWidget,
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

void _stubEmptyPanelPersistence(
  MockPanelSampleRepository repository,
  String sessionId,
) {
  when(
    () => repository.getRowsBySessionId(any(), sessionId),
  ).thenAnswer((_) async => []);
  when(
    () => repository.savePanelWithSamples(
      panel: any(named: 'panel'),
      samples: any(named: 'samples'),
    ),
  ).thenAnswer((_) async {});
  when(
    () => repository.deleteHierarchyRowsBySessionId(any(), any()),
  ).thenAnswer((_) async {});
  when(
    () => repository.deleteHierarchyRowsBySessionIdExcept(
      any(),
      any(),
      any(),
      keepHierarchyRows: any(named: 'keepHierarchyRows'),
    ),
  ).thenAnswer((_) async {});
  when(
    () => repository.deleteRowsBySessionId(any(), any()),
  ).thenAnswer((_) async {});
  when(
    () => repository.deleteRowsBySessionIdForSampleIds(any(), any(), any()),
  ).thenAnswer((_) async {});
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
