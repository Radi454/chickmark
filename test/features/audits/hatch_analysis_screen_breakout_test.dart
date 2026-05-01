import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/repositories/benchmark_lookup.dart';
import 'package:hatchaudit/features/audits/models/egg_breakout_sample.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/screens/audit_context_screen.dart';
import 'package:hatchaudit/features/audits/screens/hatch_analysis_screen.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockSupabaseService extends Mock implements SupabaseService {}

class MockBenchmarkLookup extends Mock implements BenchmarkLookup {}

MockBenchmarkLookup mockBenchmarkLookup() {
  final lookup = MockBenchmarkLookup();
  when(
    () => lookup.nearestBreakoutBenchmark(
      calculatedBmkAgeDays: any(named: 'calculatedBmkAgeDays'),
    ),
  ).thenAnswer(
    (_) async => {
      'ageWeek': 41,
      'infertilePct': 3.0,
      'early24hPct': 2.0,
      'early48hPct': 1.5,
      'bloodRingPct': 2.5,
      'blackEyePct': 0.5,
      'midDeadPct': 1.3,
      'lateDeadPct': 1.8,
      'internalPipPct': 0.8,
      'externalPipPct': 0.7,
      'crackedPct': 0.4,
      'contamPct': 0.2,
      'cullPct': 0.6,
      'exposedBrainPct': 0.1,
      'crossedBeakPct': 0.1,
    },
  );
  return lookup;
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

  AuditContextData contextData() => AuditContextData(
    auditType: 'Hatch Analysis',
    customerId: 'customer-1',
    flockId: 'flock-1',
    breed: 'Ross 308',
    flockAgeWeeks: 42,
    date: '2026-04-27',
  );

  Future<AuditProvider> pumpScreen(
    WidgetTester tester, {
    required EggBreakoutType breakoutType,
    int storageDays = 5,
    int? candlingDay,
    BenchmarkLookup? benchmarkLookup,
  }) async {
    final provider = AuditProvider();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: MockSupabaseService()),
          ),
        ],
        child: MaterialApp(
          home: HatchAnalysisScreen(
            context: contextData(),
            benchmarkLookup: benchmarkLookup ?? mockBenchmarkLookup(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    provider.updateHatchField(0, 'ebBreakoutType', breakoutType.storageValue);
    provider.updateHatchField(0, 'haStorageDays', storageDays);
    provider.updateHatchField(0, 'ebStorageDays', storageDays);
    provider.updateHatchField(0, 'haTotalEggsSet', 100);
    if (candlingDay != null) {
      provider.updateHatchField(0, 'ebBreakoutAgeDays', candlingDay);
    }
    await tester.pumpAndSettle();
    return provider;
  }

  Future<void> addVisibleSample(WidgetTester tester) async {
    await tester.ensureVisible(
      find.byKey(const ValueKey('breakout-add-sample')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('breakout-add-sample')));
    await tester.pumpAndSettle();
  }

  Future<void> tapVisibleKey(WidgetTester tester, Key key) async {
    final finder = find.byKey(key);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enterVisibleNumber(
    WidgetTester tester,
    Key key,
    String value,
  ) async {
    final finder = find.byKey(key);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    final textField = find.descendant(
      of: finder,
      matching: find.byType(TextField),
    );
    await tester.enterText(textField, value);
    await tester.pumpAndSettle();
  }

  String numericFieldText(WidgetTester tester, Key key) {
    final textField = find.descendant(
      of: find.byKey(key),
      matching: find.byType(TextField),
    );
    return tester.widget<TextField>(textField).controller?.text ?? '';
  }

  Future<void> tapVisibleText(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('fresh egg breakout hides hatchability and shows fresh items', (
    tester,
  ) async {
    await pumpScreen(tester, breakoutType: EggBreakoutType.freshEggBreakout);
    await addVisibleSample(tester);

    expect(find.text('Hatchability Results'), findsNothing);
    expect(find.text('Healthy Hatched'), findsNothing);
    expect(find.text('Culled'), findsNothing);
    expect(find.text('Dead at Hatch'), findsNothing);
    expect(find.text('Candling Day'), findsNothing);
    expect(find.text('BMK Age 289 days'), findsNothing);

    expect(find.text('Infertile'), findsOneWidget);
    expect(find.text('Early 24h'), findsOneWidget);
    expect(find.text('Early 48h'), findsOneWidget);
    expect(find.text('Early 72h / Blood ring'), findsOneWidget);
    expect(find.text('Black eye'), findsNothing);
    expect(find.text('Mid dead'), findsNothing);
  });

  testWidgets('candled egg breakout shows candling day and candled items', (
    tester,
  ) async {
    await pumpScreen(tester, breakoutType: EggBreakoutType.candledEggBreakout);
    await addVisibleSample(tester);

    expect(find.text('Hatchability Results'), findsNothing);
    expect(find.text('Candling Day'), findsNothing);
    expect(find.text('BMK Age 279 days'), findsNothing);

    expect(find.text('Infertile'), findsOneWidget);
    expect(find.text('Early 24h'), findsOneWidget);
    expect(find.text('Early 48h'), findsOneWidget);
    expect(find.text('Early 72h / Blood ring'), findsOneWidget);
    expect(find.text('Black eye'), findsOneWidget);
    expect(find.text('Mid dead'), findsOneWidget);
  });

  testWidgets('residue hatch day shows hatchability and breakout samples', (
    tester,
  ) async {
    await pumpScreen(tester, breakoutType: EggBreakoutType.residueHatchDay);

    expect(find.text('Hatchability Results'), findsNothing);
    expect(find.text('Healthy Hatched'), findsNothing);
    expect(find.text('Breakout Samples'), findsOneWidget);
    expect(find.byKey(const ValueKey('breakout-add-sample')), findsOneWidget);
    expect(find.text('BMK Age 268 days'), findsNothing);
  });

  testWidgets('uses breakout type as the main card and removes old regions', (
    tester,
  ) async {
    await pumpScreen(tester, breakoutType: EggBreakoutType.residueHatchDay);

    expect(find.text('Breakout Type'), findsOneWidget);
    expect(find.text('Fresh Egg'), findsOneWidget);
    expect(find.text('Candled Egg'), findsOneWidget);
    expect(find.text('Residue / Hatch Day'), findsOneWidget);
    expect(find.text('Breakout Samples'), findsOneWidget);

    expect(find.text('Batch / hatch group'), findsNothing);
    expect(find.text('Batch / Hatch Group 1'), findsNothing);
    expect(find.text('Batch Info'), findsNothing);
    expect(find.text('Hatchability Results'), findsNothing);
    expect(find.text('100% Budget Categories'), findsNothing);
  });

  testWidgets('main card shows flock breed storage and calculated bmk age', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.freshEggBreakout,
      benchmarkLookup: mockBenchmarkLookup(),
    );

    expect(find.text('FLOCK'), findsOneWidget);
    expect(find.text('flock-1'), findsOneWidget);
    expect(find.text('BREED'), findsOneWidget);
    expect(find.text('Ross 308'), findsOneWidget);
    expect(find.text('STORAGE DAYS'), findsOneWidget);
    expect(find.text('BMK AGE'), findsOneWidget);
    expect(find.text('42 weeks'), findsOneWidget);
    expect(find.text('CANDLED AGE'), findsNothing);
  });

  testWidgets('storage days field updates persisted values and bmk weeks', (
    tester,
  ) async {
    final provider = await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.freshEggBreakout,
      storageDays: 5,
      benchmarkLookup: mockBenchmarkLookup(),
    );

    await enterVisibleNumber(
      tester,
      const ValueKey('breakout-storage-days'),
      '8',
    );

    expect(provider.drafts.single.haStorageDays, 8);
    expect(provider.drafts.single.ebStorageDays, 8);
    expect(find.text('41 weeks'), findsOneWidget);
  });

  testWidgets('candled breakout exposes candled age and updates bmk age', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.candledEggBreakout,
      storageDays: 5,
      candlingDay: 9,
      benchmarkLookup: mockBenchmarkLookup(),
    );

    expect(find.text('CANDLED AGE'), findsOneWidget);
    expect(find.text('40 weeks'), findsOneWidget);
  });

  testWidgets('breakout counts are scoped by breakout type', (tester) async {
    final provider = await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.freshEggBreakout,
      benchmarkLookup: mockBenchmarkLookup(),
    );
    await addVisibleSample(tester);
    await enterVisibleNumber(
      tester,
      const ValueKey('breakout-count-infertile'),
      '12',
    );
    expect(
      EggBreakoutSampleEntry.decodeList(
        provider.drafts.single.ebTrayBreakoutJson,
      ).single.counts['infertile'],
      12,
    );

    await tapVisibleText(tester, 'Residue / Hatch Day');

    expect(
      find.byKey(const ValueKey('breakout-count-infertile')),
      findsNothing,
    );

    await addVisibleSample(tester);
    expect(
      numericFieldText(tester, const ValueKey('breakout-count-infertile')),
      isEmpty,
    );

    await tapVisibleText(tester, 'Fresh Egg');

    expect(
      numericFieldText(tester, const ValueKey('breakout-count-infertile')),
      '12',
    );
  });

  testWidgets('tray chips and add remove controls manage samples', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.residueHatchDay,
      benchmarkLookup: mockBenchmarkLookup(),
    );

    await addVisibleSample(tester);
    expect(find.byKey(const ValueKey('breakout-sample-tab-0')), findsOneWidget);
    expect(find.text('Tray 1'), findsWidgets);

    await addVisibleSample(tester);

    expect(find.byKey(const ValueKey('breakout-sample-tab-1')), findsOneWidget);
    expect(find.text('Tray 2'), findsWidgets);

    await tapVisibleKey(tester, const ValueKey('breakout-remove-sample'));

    expect(find.byKey(const ValueKey('breakout-sample-tab-1')), findsNothing);
  });

  testWidgets('sample card removes pool toggle and total tile', (tester) async {
    await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.residueHatchDay,
      benchmarkLookup: mockBenchmarkLookup(),
    );
    await addVisibleSample(tester);

    expect(find.text('Tray sample'), findsNothing);
    expect(find.text('Pool sample'), findsNothing);
    expect(find.text('Total sample'), findsNothing);
  });

  testWidgets('breakout rows show count calculated percent and bmk target', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.freshEggBreakout,
      benchmarkLookup: mockBenchmarkLookup(),
    );
    await addVisibleSample(tester);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('breakout-count-infertile')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('breakout-percent-infertile')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('breakout-percent-infertile')),
        matching: find.text('0.0%'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('breakout-bmk-infertile')),
      findsOneWidget,
    );
    expect(find.text('BMK 3.0%'), findsOneWidget);
  });

  testWidgets('breakout rows alert when calculated percent is above bmk', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.freshEggBreakout,
      benchmarkLookup: mockBenchmarkLookup(),
    );
    await addVisibleSample(tester);

    await enterVisibleNumber(
      tester,
      const ValueKey('breakout-count-infertile'),
      '10',
    );

    expect(
      find.byKey(const ValueKey('breakout-alert-infertile')),
      findsOneWidget,
    );
  });
}
