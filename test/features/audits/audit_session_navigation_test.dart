import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/audit_session_model.dart';
import 'package:hatchaudit/data/repositories/activity_log_repository.dart';
import 'package:hatchaudit/data/repositories/audit_session_repository.dart';
import 'package:hatchaudit/features/audits/providers/audit_session_provider.dart';
import 'package:hatchaudit/features/audits/screens/audit_session_screen.dart';
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
        selectedStationKeys: const ['egg_storage', 'setter_optimizing'],
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
        selectedStationKeys: const ['chick_quality'],
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
        selectedStationKeys: const ['hatch_analysis'],
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
        selectedStationKeys: const ['egg_storage'],
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
        selectedStationKeys: const ['hatch_analysis'],
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
