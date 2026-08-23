import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/screens/audit_context_screen.dart';
import 'package:hatchaudit/features/audits/screens/egg_storage_screen.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockSupabaseService extends Mock implements SupabaseService {}

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
    auditType: 'Egg',
    customerId: 'customer-1',
    flockId: 'flock-1',
    breed: 'Ross 308',
    flockAgeWeeks: 42,
    date: '2026-04-27',
  );

  late AuditProvider providerUnderTest;

  Future<void> pumpEggStation(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    providerUnderTest = AuditProvider(autosaveEnabled: false);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuditProvider>.value(value: providerUnderTest),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: MockSupabaseService()),
          ),
          ChangeNotifierProvider(create: (_) => CustomersProvider()),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: EggStorageScreen(context: contextData()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('egg storage shows a disabled pool-only sample mode bar', (
    tester,
  ) async {
    await pumpEggStation(tester);

    expect(find.text('Sample mode'), findsWidgets);
    expect(find.text('Pool'), findsWidgets);
    expect(
      find.text('Egg storage is always measured as one pool.'),
      findsOneWidget,
    );
    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Pool').first,
    );
    expect(chip.onSelected, isNull);
  });

  testWidgets('egg quality offers exactly pooled and compare by house', (
    tester,
  ) async {
    await pumpEggStation(tester);
    await tester.tap(find.text('Egg quality'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.widgetWithText(ChoiceChip, 'Pooled'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Compare by house'), findsOneWidget);
    // Exactly these two chips exist in the Sample mode bar row -- no other
    // comparison-scope options (tray, trolley, machine, ...) are offered.
    expect(find.byType(ChoiceChip), findsNWidgets(3));
  });

  testWidgets('switching back to pooled asks before discarding houses', (
    tester,
  ) async {
    await pumpEggStation(tester);
    await tester.tap(find.text('Egg quality'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Compare by house'));
    await tester.pump(const Duration(milliseconds: 300));

    // A second house is added through the vetted identity-dialog "+" button
    // (not by re-tapping the mode chip, which is disabled once compare mode
    // is already active) so the second sample gets a real, distinct house
    // number instead of colliding with the first sample's placeholder.
    await tester.tap(find.byTooltip('Add house sample'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byKey(const ValueKey('scope-identity-house')),
      'H2',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('scope-identity-add')));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.widgetWithText(ChoiceChip, 'Pooled'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('will be discarded'), findsOneWidget);
  });

  testWidgets(
    'selected compare by house stays enabled and repeated selection is a no-op',
    (tester) async {
      await pumpEggStation(tester);
      await tester.tap(find.text('Egg quality'));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.widgetWithText(ChoiceChip, 'Compare by house'));
      await tester.pump(const Duration(milliseconds: 300));

      // Re-tapping "Compare by house" while already in compare mode stays an
      // enabled, safe no-op and must not add a duplicate house sample.
      final compareChip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Compare by house'),
      );
      expect(compareChip.onSelected, isNotNull);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Compare by house'));
      await tester.pump(const Duration(milliseconds: 300));

      final houseSamples = providerUnderTest.stationSamples.where(
        (s) => s.sampleKind == StationSampleModel.sampleKindHouse,
      );
      expect(houseSamples.length, 1);
    },
  );

  testWidgets('typing a duplicate house number inline is rejected', (
    tester,
  ) async {
    await pumpEggStation(tester);
    await tester.tap(find.text('Egg quality'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Compare by house'));
    await tester.pump(const Duration(milliseconds: 300));

    // Name the first house H1.
    final houseField = find.byWidgetPredicate(
      (w) =>
          w is TextFormField &&
          (w.key as ValueKey?)?.value.toString().startsWith(
                'egg-quality-house-',
              ) ==
              true,
    );
    await tester.enterText(houseField, 'H1');
    await tester.pump(const Duration(milliseconds: 100));

    // Add a second house named H2 through the vetted identity dialog.
    await tester.tap(find.byTooltip('Add house sample'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byKey(const ValueKey('scope-identity-house')),
      'H2',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('scope-identity-add')));
    await tester.pump(const Duration(milliseconds: 300));

    // Switch back to H1 and try renaming it to H2 (a duplicate).
    await tester.tap(find.widgetWithText(ChoiceChip, 'H1'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(houseField, 'H2');
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.text('A House scope with this identity already exists.'),
      findsOneWidget,
    );
    expect(providerUnderTest.activeStationSample.houseNo, 'H1');
  });

  Future<void> enterCompareModeWithTwoValuedHouses(
    WidgetTester tester, {
    required int house1Value,
    required int house2Value,
  }) async {
    await pumpEggStation(tester);
    await tester.tap(find.text('Egg quality'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Compare by house'));
    await tester.pump(const Duration(milliseconds: 300));

    final houseField = find.byWidgetPredicate(
      (w) =>
          w is TextFormField &&
          (w.key as ValueKey?)?.value.toString().startsWith(
                'egg-quality-house-',
              ) ==
              true,
    );
    await tester.enterText(houseField, 'H1');
    await tester.pump(const Duration(milliseconds: 100));
    providerUnderTest.updateField('esEggSampleSize', house1Value);
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('Add house sample'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byKey(const ValueKey('scope-identity-house')),
      'H2',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('scope-identity-add')));
    await tester.pump(const Duration(milliseconds: 300));
    providerUnderTest.updateField('esEggSampleSize', house2Value);
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets(
    'canceling the pooled-mode confirmation keeps both houses and their values',
    (tester) async {
      await enterCompareModeWithTwoValuedHouses(
        tester,
        house1Value: 30,
        house2Value: 55,
      );

      await tester.tap(find.widgetWithText(ChoiceChip, 'Pooled'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('will be discarded'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(providerUnderTest.isCompareMode, isTrue);
      expect(providerUnderTest.stationSamples, hasLength(2));
      expect(providerUnderTest.stationSamples.map((s) => s.houseNo).toList(), [
        'H1',
        'H2',
      ]);
      expect(providerUnderTest.drafts, hasLength(2));
      expect(providerUnderTest.drafts[0].esEggSampleSize, 30);
      expect(providerUnderTest.drafts[1].esEggSampleSize, 55);
    },
  );

  testWidgets(
    'confirming the pooled-mode switch discards house 2 and keeps house 1\'s value',
    (tester) async {
      await enterCompareModeWithTwoValuedHouses(
        tester,
        house1Value: 30,
        house2Value: 55,
      );

      await tester.tap(find.widgetWithText(ChoiceChip, 'Pooled'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('will be discarded'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Discard and pool'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(providerUnderTest.isCompareMode, isFalse);
      expect(providerUnderTest.stationSamples, hasLength(1));
      expect(providerUnderTest.drafts, hasLength(1));
      expect(providerUnderTest.drafts.single.esEggSampleSize, 30);
    },
  );
}
