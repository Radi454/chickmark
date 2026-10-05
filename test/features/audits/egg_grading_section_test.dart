import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/panel_sampling_state.dart';
import 'package:hatchaudit/data/models/sampling_scope.dart';
import 'package:hatchaudit/data/repositories/panel_sampling_state_repository.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/screens/audit_context_screen.dart';
import 'package:hatchaudit/features/audits/screens/egg_storage_screen.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockSupabaseService extends Mock implements SupabaseService {}

class _TwoHouseSamplingRepository extends PanelSamplingStateRepository {
  final state = PanelSamplingState(
    sessionId: 'session-1',
    panelKey: 'egg_quality',
    serialHighWatermark: 2,
    activeSampleId: 'sample-1',
    nodes: [
      SamplingNode(
        id: 'house-node-1',
        sessionId: 'session-1',
        panelKey: 'egg_quality',
        level: SamplingScopeLevel.house,
        identityKey: 'H1',
        identity: const {'house': 'house-1', 'code': 'H1', 'name': 'House 1'},
      ),
      SamplingNode(
        id: 'sample-node-1',
        sessionId: 'session-1',
        panelKey: 'egg_quality',
        parentId: 'house-node-1',
        level: SamplingScopeLevel.sample,
        identityKey: 'SA1',
        identity: const {},
        sampleId: 'sample-1',
        sampleNumber: 1,
      ),
      SamplingNode(
        id: 'house-node-2',
        sessionId: 'session-1',
        panelKey: 'egg_quality',
        level: SamplingScopeLevel.house,
        identityKey: 'H2',
        identity: const {'house': 'house-2', 'code': 'H2', 'name': 'House 2'},
      ),
      SamplingNode(
        id: 'sample-node-2',
        sessionId: 'session-1',
        panelKey: 'egg_quality',
        parentId: 'house-node-2',
        level: SamplingScopeLevel.sample,
        identityKey: 'SA2',
        identity: const {},
        sampleId: 'sample-2',
        sampleNumber: 2,
      ),
    ],
  );

  @override
  Future<PanelSamplingState> loadOrCreateDefault({
    required String sessionId,
    required String panelKey,
  }) async => state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const connectivityChannel = MethodChannel(
    'dev.fluttercommunity.plus/connectivity',
  );

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, (call) async {
          if (call.method == 'check') return ['wifi'];
          return null;
        });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, null);
  });

  Future<AuditProvider> pumpEggGrading(
    WidgetTester tester, {
    PanelSamplingStateRepository? samplingRepository,
  }) async {
    final provider = AuditProvider(
      autosaveEnabled: false,
      panelSamplingStateRepository: samplingRepository,
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(
            create: (_) =>
                AuthProvider(supabaseService: _MockSupabaseService()),
          ),
          ChangeNotifierProvider(create: (_) => CustomersProvider()),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: EggStorageScreen(
            context: AuditContextData(
              auditType: 'Egg',
              customerId: 'customer-1',
              flockId: 'flock-1',
              breed: 'Ross 308',
              sessionId: 'session-1',
              flockAgeWeeks: 42,
              date: '2026-08-23',
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return provider;
  }

  Future<void> expandEggGrading(WidgetTester tester) async {
    final heading = find.text('Egg grading / visual quality');
    await tester.ensureVisible(heading);
    await tester.tap(heading);
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<AuditProvider> pumpEggGradingWithTwoHouses(WidgetTester tester) async {
    final provider = await pumpEggGrading(
      tester,
      samplingRepository: _TwoHouseSamplingRepository(),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    provider.updateField('esGradingSampleSize', 100);
    provider.updateGradingCounts({'dirty': 4});
    expect(provider.activeDraft.esGradingSampleSize, 100);
    expect(provider.activeGradingCounts, {'dirty': 4});
    await tester.pump(const Duration(milliseconds: 300));
    await expandEggGrading(tester);
    return provider;
  }

  testWidgets('entering counts updates the summary strip', (tester) async {
    await pumpEggGrading(tester);
    await expandEggGrading(tester);

    await tester.enterText(
      find.byKey(const Key('egg-grading-sample-size')),
      '100',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byKey(const Key('egg-grading-rejected')), '12');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.byKey(const Key('egg-grading-count-dirty')),
      '4',
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Acceptable 88 (88.0%)'), findsOneWidget);
    expect(find.text('Rejected 12 (12.0%)'), findsOneWidget);
    expect(find.text('Top defect: Dirty 4.0%'), findsOneWidget);
    expect(find.textContaining('Dirty'), findsWidgets);
  });

  testWidgets('blank defect percentages render as dashes in 40x40 slots', (
    tester,
  ) async {
    await pumpEggGrading(tester);
    await expandEggGrading(tester);

    expect(find.text('-'), findsNWidgets(18));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SizedBox && widget.width == 40 && widget.height == 40,
      ),
      findsNWidgets(18),
    );
  });

  testWidgets('editing a known defect preserves an unknown defect code', (
    tester,
  ) async {
    final provider = await pumpEggGrading(tester);
    provider.updateField('esGradingSampleSize', 100);
    provider.updateGradingCounts({'dirty': 2, 'future_shell_code': 7});
    await tester.pump(const Duration(milliseconds: 100));
    await expandEggGrading(tester);

    await tester.enterText(
      find.byKey(const Key('egg-grading-count-dirty')),
      '3',
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(provider.activeGradingCounts, {'dirty': 3, 'future_shell_code': 7});
  });

  testWidgets('a defect count above the sample size shows an error', (
    tester,
  ) async {
    await pumpEggGrading(tester);
    await expandEggGrading(tester);
    await tester.enterText(
      find.byKey(const Key('egg-grading-sample-size')),
      '50',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.byKey(const Key('egg-grading-count-dirty')),
      '80',
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('cannot exceed eggs inspected'), findsOneWidget);
  });

  testWidgets('clearing inspected eggs validates retained counts', (
    tester,
  ) async {
    await pumpEggGrading(tester);
    await expandEggGrading(tester);
    await tester.enterText(
      find.byKey(const Key('egg-grading-sample-size')),
      '100',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byKey(const Key('egg-grading-rejected')), '12');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.byKey(const Key('egg-grading-count-dirty')),
      '4',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.byKey(const Key('egg-grading-sample-size')),
      '',
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('Eggs rejected cannot exceed eggs inspected.'),
      findsOneWidget,
    );
    expect(
      find.text('Dirty count cannot exceed eggs inspected.'),
      findsOneWidget,
    );
  });

  testWidgets('a defect sum above the sample size is accepted', (tester) async {
    await pumpEggGrading(tester);
    await expandEggGrading(tester);
    await tester.enterText(
      find.byKey(const Key('egg-grading-sample-size')),
      '100',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.byKey(const Key('egg-grading-count-dirty')),
      '60',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.byKey(const Key('egg-grading-count-cracked')),
      '55',
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('cannot exceed'), findsNothing);
  });

  testWidgets(
    'switching registered House samples keeps grading drafts separate',
    (tester) async {
      final provider = await pumpEggGradingWithTwoHouses(tester);
      expect(provider.activeGradingCounts, {'dirty': 4});
      final secondHouseChip = find.text('House 2');
      await tester.ensureVisible(secondHouseChip);
      await tester.tap(secondHouseChip);
      await tester.pump(const Duration(milliseconds: 300));
      expect(provider.activeGradingCounts, isEmpty);
      provider.updateField('esGradingSampleSize', 80);
      provider.updateGradingCounts({'dirty': 7});
      await tester.pump(const Duration(milliseconds: 100));

      final firstHouseChip = find.text('House 1');
      await tester.ensureVisible(firstHouseChip);
      await tester.tap(firstHouseChip);
      await tester.pump(const Duration(milliseconds: 300));
      expect(provider.activeGradingCounts, {'dirty': 4});

      await tester.ensureVisible(secondHouseChip);
      await tester.tap(secondHouseChip);
      await tester.pump(const Duration(milliseconds: 300));
      expect(provider.activeGradingCounts, {'dirty': 7});
    },
  );
}
