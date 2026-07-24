import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/audit_session_model.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/data/repositories/audit_session_repository.dart';
import 'package:hatchaudit/features/audits/providers/audit_session_provider.dart';
import 'package:hatchaudit/features/audits/screens/audit_session_screen.dart';
import 'package:hatchaudit/features/audits/screens/audit_station_selection_screen.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';
import 'package:hatchaudit/features/govee/providers/govee_capture_provider.dart';
import 'package:hatchaudit/features/home/providers/home_provider.dart';
import 'package:hatchaudit/features/home/screens/home_screen.dart';
import 'package:hatchaudit/features/settings/providers/settings_provider.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/test_database.dart';

class _MockSupabaseService extends Mock implements SupabaseService {}

class _MockAuditSessionRepository extends Mock
    implements AuditSessionRepository {}

class _RecordingNavigatorObserver extends NavigatorObserver {
  Route<dynamic>? latestPushedRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (previousRoute != null) latestPushedRoute = route;
  }
}

class _ImmediateCustomersProvider extends CustomersProvider {
  @override
  Future<void> loadCustomers({
    UserModel? currentUser,
    bool syncRemote = false,
  }) async {}
}

class _StaticHomeProvider extends HomeProvider {
  _StaticHomeProvider(List<AuditSessionModel> sessions)
    : _sessions = List.of(sessions);

  final List<AuditSessionModel> _sessions;
  int loadCalls = 0;
  bool clearSessionsOnLoad = false;

  @override
  List<AuditSessionModel> get activeSessions => List.unmodifiable(_sessions);

  @override
  List<AuditSessionModel> get recentSessions => const [];

  @override
  Future<void> load({required UserModel? currentUser}) async {
    loadCalls += 1;
    if (clearSessionsOnLoad) {
      _sessions.clear();
      notifyListeners();
    }
  }
}

AuditSessionModel _incompleteSession({
  required String id,
  List<String> selected = const ['chicks', 'hatch_analysis_egg_breakouts'],
  List<String> completed = const [],
}) {
  final date = DateTime(2026, 7, 21, 12, 30);
  return AuditSessionModel(
    id: id,
    customerId: 'customer-$id',
    flockId: 'flock-$id',
    hatcheryId: 'hatchery-$id',
    date: date,
    breed: 'Avian',
    status: 'in_progress',
    selectedStationKeys: selected,
    stationsCompleted: completed,
    createdAt: date,
    updatedAt: date,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory databaseDirectory;

  setUpAll(() async {
    databaseDirectory = await useIsolatedAppDatabase();
  });

  tearDownAll(() async {
    await resetAppDatabase();
    if (await databaseDirectory.exists()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  Future<void> pumpHome(
    WidgetTester tester, {
    HomeProvider? homeProvider,
    AuditSessionProvider? auditSessionProvider,
    CustomersProvider? customersProvider,
    List<NavigatorObserver> navigatorObservers = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => customersProvider ?? CustomersProvider(),
          ),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(
              supabaseService: _MockSupabaseService(),
              bypassAuth: true,
            ),
          ),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => DashboardProvider()),
          ChangeNotifierProvider(create: (_) => GoveeCaptureProvider()),
          ChangeNotifierProvider(
            create: (_) => auditSessionProvider ?? AuditSessionProvider(),
          ),
        ],
        child: MaterialApp(
          navigatorObservers: navigatorObservers,
          home: HomeScreen(loadInitialData: false, homeProvider: homeProvider),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Home lists every incomplete visit with completion reminder', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sessions = [
      _incompleteSession(id: 'one', completed: const ['chicks']),
      _incompleteSession(id: 'two'),
      _incompleteSession(id: 'three'),
    ];

    await pumpHome(tester, homeProvider: _StaticHomeProvider(sessions));

    expect(
      find.byKey(const ValueKey('home-incomplete-visits-section')),
      findsOneWidget,
    );
    for (final session in sessions) {
      expect(
        find.byKey(ValueKey('home-incomplete-visit-${session.id}')),
        findsOneWidget,
      );
    }
    expect(find.text('Please complete this visit soon.'), findsNWidgets(3));
    expect(find.text('Complete now'), findsNWidgets(3));
    expect(find.text('1/2 stations complete'), findsOneWidget);
    expect(
      find.text('Still needed: Hatch Analysis & Egg Breakouts'),
      findsOneWidget,
    );
  });

  testWidgets('Complete now opens the first unfinished station directly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = _incompleteSession(
      id: 'resume',
      selected: const ['egg', 'chicks'],
      completed: const ['egg'],
    );
    final repository = _MockAuditSessionRepository();
    when(
      () => repository.getSessionById('resume'),
    ).thenAnswer((_) async => session);
    final auditSessionProvider = AuditSessionProvider(repository: repository);

    await pumpHome(
      tester,
      homeProvider: _StaticHomeProvider([session]),
      auditSessionProvider: auditSessionProvider,
    );
    await tester.tap(find.byKey(const ValueKey('home-complete-now-resume')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    verify(() => repository.getSessionById('resume')).called(1);
    expect(auditSessionProvider.currentStationIndex, 1);
    expect(find.byType(AuditSessionScreen), findsOneWidget);
    expect(find.byType(AuditStationSelectionScreen), findsNothing);
  });

  testWidgets('Complete now ignores repeated taps while resume is opening', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = _incompleteSession(id: 'guarded');
    final repository = _MockAuditSessionRepository();
    final resumeResult = Completer<AuditSessionModel?>();
    when(
      () => repository.getSessionById('guarded'),
    ).thenAnswer((_) => resumeResult.future);
    final auditSessionProvider = AuditSessionProvider(repository: repository);

    await pumpHome(
      tester,
      homeProvider: _StaticHomeProvider([session]),
      auditSessionProvider: auditSessionProvider,
    );
    final action = find.byKey(const ValueKey('home-complete-now-guarded'));
    await tester.tap(action);
    await tester.tap(action);

    verify(() => repository.getSessionById('guarded')).called(1);

    resumeResult.complete(session);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AuditSessionScreen), findsOneWidget);
  });

  testWidgets('Returning from an incomplete visit reloads the Home list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = _incompleteSession(id: 'reload');
    final repository = _MockAuditSessionRepository();
    when(
      () => repository.getSessionById('reload'),
    ).thenAnswer((_) async => session);
    final auditSessionProvider = AuditSessionProvider(repository: repository);
    final homeProvider = _StaticHomeProvider([session]);
    final navigatorObserver = _RecordingNavigatorObserver();

    await pumpHome(
      tester,
      homeProvider: homeProvider,
      auditSessionProvider: auditSessionProvider,
      customersProvider: _ImmediateCustomersProvider(),
      navigatorObservers: [navigatorObserver],
    );
    await tester.tap(find.byKey(const ValueKey('home-complete-now-reload')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AuditSessionScreen), findsOneWidget);

    homeProvider.clearSessionsOnLoad = true;
    final resumedRoute = navigatorObserver.latestPushedRoute!;
    resumedRoute.didPop(null);
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 50 && homeProvider.loadCalls == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();

    expect(homeProvider.loadCalls, 1);
    expect(homeProvider.activeSessions, isEmpty);
  });

  testWidgets('Home hides Incomplete Visits when there are none', (
    tester,
  ) async {
    await pumpHome(tester, homeProvider: _StaticHomeProvider(const []));

    expect(
      find.byKey(const ValueKey('home-incomplete-visits-section')),
      findsNothing,
    );
  });
}
