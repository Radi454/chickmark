import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/screens/audit_context_screen.dart';
import 'package:hatchaudit/features/audits/temperature_capture/temperature_capture_screen.dart';
import 'package:hatchaudit/features/audits/screens/egg_storage_screen.dart';
import 'package:hatchaudit/features/audits/widgets/photo_button.dart';
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

  Future<void> pumpScreen(
    WidgetTester tester, {
    AuditContextData? auditContext,
    EggBmkWeightLookup? bmkEggWeightLookup,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AuditProvider(autosaveEnabled: false),
          ),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: MockSupabaseService()),
          ),
          ChangeNotifierProvider(create: (_) => CustomersProvider()),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: EggStorageScreen(
            context: auditContext ?? contextData(),
            bmkEggWeightLookup: bmkEggWeightLookup,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> addNamedScope(
    WidgetTester tester, {
    required String tooltip,
    required Map<String, String> identities,
  }) async {
    await tester.ensureVisible(find.byTooltip(tooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(tooltip));
    await tester.pumpAndSettle();
    for (final entry in identities.entries) {
      await tester.enterText(
        find.byKey(ValueKey('scope-identity-${entry.key}')),
        entry.value,
      );
    }
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('scope-identity-add')));
    await tester.pumpAndSettle();
  }

  // The Sample Mode bar's "Compare by house" chip is now the only way to
  // switch Egg Quality out of pooled: it seeds one placeholder house. This
  // helper enters compare mode and immediately names that first house via
  // the inline identity field, so callers land on the same station-sample
  // count and houseNo values the dialog-based flow used to produce.
  Future<void> enterCompareModeWithFirstHouse(
    WidgetTester tester, {
    required String house,
  }) async {
    await tester.ensureVisible(
      find.widgetWithText(ChoiceChip, 'Compare by house'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Compare by house'));
    await tester.pumpAndSettle();
    final houseField = find.byWidgetPredicate(
      (w) =>
          w is TextFormField &&
          (w.key as ValueKey?)?.value.toString().startsWith(
                'egg-quality-house-',
              ) ==
              true,
    );
    await tester.ensureVisible(houseField);
    await tester.enterText(houseField, house);
    await tester.pump();
  }

  testWidgets('Capture readings launches the reusable capture screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(tester);

    await tester.ensureVisible(find.text('Egg Shell Temperature'));
    await tester.tap(find.text('Egg Shell Temperature'));
    await tester.pumpAndSettle();

    final scanButton = find.widgetWithText(OutlinedButton, 'Capture readings');
    await tester.ensureVisible(scanButton);
    await tester.pump();
    await tester.tap(scanButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(TemperatureCaptureScreen), findsOneWidget);
    expect(find.text('Eggshell Temperature'), findsOneWidget);

    // Close the pushed screen so the inline camera disposes its init timer.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(TemperatureCaptureScreen), findsNothing);
  });

  testWidgets('Egg EST unit selector defaults to Fahrenheit', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpScreen(tester);

    await tester.ensureVisible(find.text('Egg Shell Temperature'));
    await tester.tap(find.text('Egg Shell Temperature'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('egg-est-unit-selector')), findsOneWidget);
    final fahrenheit = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('egg-est-unit-f')),
    );
    expect(fahrenheit.selected, isTrue);
    expect(find.text('66.2-69.8°F'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('egg-est-unit-c')));
    await tester.pump();

    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('egg-est-unit-c')))
          .selected,
      isTrue,
    );
    expect(find.text('19.0-21.0°C'), findsOneWidget);
  });

  testWidgets('shows a default upside-down tray before the add tray action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(tester);

    await tester.ensureVisible(find.text('Upside Down Score'));
    await tester.pump();
    await tester.tap(find.text('Upside Down Score'));
    await tester.pumpAndSettle();

    final firstTray = find.text('Tray 1');
    final addTray = find.text('Add Tray');

    expect(firstTray, findsOneWidget);
    expect(find.text('Upside Down: 0 eggs (0.0%)'), findsOneWidget);
    expect(addTray, findsOneWidget);
    expect(
      tester.getBottomLeft(firstTray).dy,
      lessThan(tester.getTopLeft(addTray).dy),
    );
  });

  testWidgets('UV tray photo button is tied to the egg quality sync row', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(
      tester,
      auditContext: AuditContextData(
        auditType: 'Egg',
        customerId: 'customer-1',
        flockId: 'flock-1',
        sessionId: 'session-1',
        breed: 'Ross 308',
        flockAgeWeeks: 42,
        date: '2026-04-27',
      ),
    );

    await tester.ensureVisible(find.text('Egg Shell Quality'));
    await tester.pump();
    await tester.tap(find.text('Egg Shell Quality'));
    await tester.pumpAndSettle();

    final trayPhotoButton = tester.widget<PhotoButton>(
      find.descendant(
        of: find.ancestor(
          of: find.text('Affected: 0 eggs (0.0%)'),
          matching: find.byType(Row),
        ),
        matching: find.byType(PhotoButton),
      ),
    );

    expect(trayPhotoButton.panelName, 'egg_quality');
    expect(trayPhotoButton.fieldKey, 'uv_tray_0');
  });

  testWidgets('renders split egg storage workbench controls', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(tester);

    Finder expectBrandHero(String title) {
      final hero = find.ancestor(
        of: find.text(title),
        matching: find.byWidgetPredicate((widget) {
          final decoration = widget is Container ? widget.decoration : null;
          return decoration is BoxDecoration &&
              decoration.gradient is LinearGradient;
        }),
      );
      expect(hero, findsOneWidget);
      final decoration =
          tester.widget<Container>(hero).decoration as BoxDecoration;
      final gradient = decoration.gradient as LinearGradient;
      expect(gradient.colors, [AppColors.primaryLight, AppColors.primaryDark]);
      expect(gradient.begin, Alignment.topLeft);
      expect(gradient.end, Alignment.bottomRight);
      return hero;
    }

    expect(find.text('Egg'), findsWidgets);
    expect(find.text('Egg storage room'), findsOneWidget);
    final storageHero = expectBrandHero('Egg storage room');
    expect(
      find.descendant(
        of: storageHero,
        matching: find.byIcon(Icons.inventory_2_outlined),
      ),
      findsNothing,
    );
    expect(find.text('AUDIT STATION'), findsNothing);
    expect(
      find.text('Storage class, shell condition, and egg quality checks.'),
      findsNothing,
    );
    expect(find.text('Shell range'), findsNothing);
    expect(find.text('Egg Shell Temperature'), findsOneWidget);
    expect(find.text('Storage class and shell readings'), findsNothing);
    expect(find.text('19.0-21.0°C'), findsNothing);
    expect(find.text('EST'), findsNothing);
    expect(find.byKey(const ValueKey('egg-workbench-mark-EST')), findsNothing);
    expect(find.text('Pending'), findsNothing);

    final storageDaysField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Storage Days',
    );
    expect(storageDaysField, findsOneWidget);
    expect(
      tester.getTopLeft(storageDaysField).dy,
      lessThan(tester.getTopLeft(find.text('Egg Shell Temperature')).dy),
    );

    expect(find.text('Upside Down Score'), findsOneWidget);
    expect(find.text('Count incorrectly oriented eggs per tray'), findsNothing);
    expect(find.text('UD'), findsNothing);
    expect(find.byKey(const ValueKey('egg-workbench-mark-UD')), findsNothing);
    expect(find.text('Avg 0.0%'), findsNothing);
    final upsideDownHeader = find.ancestor(
      of: find.text('Upside Down Score'),
      matching: find.byType(ExpansionTile),
    );
    expect(upsideDownHeader, findsOneWidget);
    expect(
      find.descendant(
        of: upsideDownHeader,
        matching: find.byKey(const ValueKey('upside-down-inverted-egg-icon')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: upsideDownHeader,
        matching: find.byIcon(Icons.flip_to_back),
      ),
      findsNothing,
    );
    expect(find.text('Storage Checklist'), findsOneWidget);
    expect(find.text('Handling observations before set'), findsNothing);
    expect(find.text('CHK'), findsNothing);
    expect(find.byKey(const ValueKey('egg-workbench-mark-CHK')), findsNothing);
    expect(find.text('0 of 4 set'), findsNothing);
    expect(find.text('Egg quality'), findsOneWidget);
    final qualityHero = expectBrandHero('Egg quality');
    expect(
      find.descendant(
        of: qualityHero,
        matching: find.byIcon(Icons.monitor_weight_outlined),
      ),
      findsNothing,
    );
    expect(find.text('EQ'), findsNothing);
    expect(find.text('Sampling scope and 100-egg uniformity'), findsNothing);
    expect(find.text('Sample setup'), findsNothing);
    expect(find.text('Flock context and benchmark age'), findsNothing);
    expect(find.text('Flock'), findsOneWidget);
    expect(find.text('Breed'), findsOneWidget);
    expect(find.text('BMK Age'), findsWidgets);
    expect(find.text('39 wks'), findsWidgets);

    final flockDetail = find.byKey(const ValueKey('audit-hero-detail-Flock'));
    final breedDetail = find.byKey(const ValueKey('audit-hero-detail-Breed'));
    final bmkAgeDetail = find.byKey(
      const ValueKey('audit-hero-detail-BMK Age'),
    );
    expect(flockDetail, findsOneWidget);
    expect(breedDetail, findsOneWidget);
    expect(bmkAgeDetail, findsOneWidget);
    final flockRect = tester.getRect(flockDetail);
    final breedRect = tester.getRect(breedDetail);
    final bmkAgeRect = tester.getRect(bmkAgeDetail);
    expect(flockRect.top, breedRect.top);
    expect(breedRect.top, bmkAgeRect.top);
    expect((flockRect.width - breedRect.width).abs(), lessThan(1));
    expect((breedRect.width - bmkAgeRect.width).abs(), lessThan(1));

    expect(find.text('Sampling scope'), findsNothing);
    expect(find.text('Record one house or compare houses'), findsNothing);
    expect(find.text('One sample'), findsNothing);
    expect(find.text('1 sample'), findsNothing);
    expect(find.text('Multiple samples'), findsNothing);
    expect(find.byType(SegmentedButton<bool>), findsNothing);
    expect(
      find.byKey(const ValueKey('egg-sample-mode-icon-single')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('egg-sample-mode-icon-multiple')),
      findsNothing,
    );
    // The house-chip strip only renders once the station is in compare
    // mode; while pooled, "Sample mode" bars cover this state instead.
    expect(find.text('House scope'), findsNothing);
    expect(find.text('Machine scope'), findsNothing);
    expect(find.text('Sample mode'), findsWidgets);
    expect(find.text('Pool'), findsOneWidget);
    expect(find.text('UV torch inspection by tray'), findsNothing);
    expect(find.text('Optional station comments'), findsNothing);

    await tester.ensureVisible(find.text('Egg Shell Temperature'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Egg Shell Temperature'));
    await tester.pumpAndSettle();

    expect(find.text('66.2-69.8°F'), findsOneWidget);
    expect(find.text('Storage duration'), findsOneWidget);
    expect(find.text('EST target'), findsOneWidget);
    expect(find.text('Storage class'), findsNothing);
    expect(find.text('Shell target'), findsNothing);

    await tester.ensureVisible(find.text('Upside Down Score'));
    await tester.pump();
    expect(find.text('Add Tray'), findsNothing);

    await tester.tap(find.text('Upside Down Score'));
    await tester.pumpAndSettle();

    expect(find.text('Add Tray'), findsOneWidget);

    await tester.ensureVisible(find.text('Storage Checklist'));
    await tester.pump();
    expect(find.text('Egg Turning'), findsNothing);

    await tester.tap(find.text('Storage Checklist'));
    await tester.pumpAndSettle();

    expect(find.text('Egg Turning'), findsOneWidget);

    expect(find.text('House Samples'), findsNothing);
    expect(find.text('Same flock, compare egg quality by house'), findsNothing);
    expect(find.text('Egg Weights & Uniformity'), findsOneWidget);
    expect(find.text('EW'), findsNothing);
    expect(find.byKey(const ValueKey('egg-workbench-mark-EW')), findsNothing);
    expect(find.text('0/100'), findsNothing);
    // While pooled, the house-chip strip (and its "Add house sample"
    // button) is hidden; the Sample Mode bar's "Compare by house" chip is
    // the only way to switch into compare mode now.
    expect(find.byTooltip('Add house sample'), findsNothing);
    expect(find.byTooltip('Add machine sample'), findsNothing);

    await enterCompareModeWithFirstHouse(tester, house: '12');
    await tester.pumpAndSettle();

    expect(find.byTooltip('Add house sample'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byTooltip('Add house sample')).dy,
      lessThan(tester.getTopLeft(find.text('Egg Weights & Uniformity')).dy),
    );

    final h = find.widgetWithText(ChoiceChip, 'H12');
    final addHouse = find.byTooltip('Add house sample');
    final removeHouse = find.byTooltip('Remove active house sample');

    expect(find.widgetWithText(ChoiceChip, 'H1'), findsNothing);
    expect(h, findsOneWidget);
    expect(removeHouse, findsOneWidget);
    expect(tester.getCenter(addHouse).dx, greaterThan(tester.getCenter(h).dx));
    expect(
      tester.getCenter(removeHouse).dx,
      greaterThan(tester.getCenter(addHouse).dx),
    );
    expect(tester.getTopLeft(addHouse).dy, tester.getTopLeft(removeHouse).dy);

    await tester.ensureVisible(removeHouse);
    await tester.pumpAndSettle();
    await tester.tap(removeHouse);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, 'H1'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'H'), findsNothing);
    expect(find.text('Pool'), findsOneWidget);
    expect(find.byTooltip('Remove active house sample'), findsNothing);

    await tester.ensureVisible(find.text('Egg Shell Quality'));
    await tester.pump();
    expect(find.text('UV'), findsNothing);
    expect(find.byKey(const ValueKey('egg-workbench-mark-UV')), findsNothing);
    expect(find.text('Avg affected 0.0%'), findsNothing);
    expect(find.text('NT'), findsNothing);
    expect(find.byKey(const ValueKey('egg-workbench-mark-NT')), findsNothing);
    expect(find.text('Add UV Tray'), findsNothing);

    await tester.tap(find.text('Egg Shell Quality'));
    await tester.pumpAndSettle();

    final uvSummary = find.byKey(const ValueKey('uv-percent-summary-card'));
    expect(uvSummary, findsOneWidget);
    expect(
      find.descendant(of: uvSummary, matching: find.text('Cuticle Damage')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: uvSummary, matching: find.text('Washed')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: uvSummary, matching: find.text('Dirty')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: uvSummary, matching: find.text('Affected')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: uvSummary, matching: find.text('0.0%')),
      findsNWidgets(4),
    );
    expect(find.text('Add UV Tray'), findsOneWidget);

    expect(storageDaysField, findsOneWidget);
    await tester.ensureVisible(storageDaysField);
    await tester.pump();
    expect(tester.widget<TextField>(storageDaysField).controller?.text, '0');

    await tester.tap(storageDaysField);
    await tester.pump();

    expect(tester.widget<TextField>(storageDaysField).controller?.text, '');
  });

  testWidgets('egg quality BMK age follows quality storage days', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(
      tester,
      auditContext: AuditContextData(
        auditType: 'Egg',
        customerId: 'customer-1',
        flockId: 'flock-1',
        flockAgeWeeks: 42,
        date: '2026-04-27',
      ),
    );

    expect(find.text('39 wks'), findsWidgets);

    final storageDaysField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Storage Days',
    );
    expect(storageDaysField, findsOneWidget);

    await tester.enterText(storageDaysField, '14');
    await tester.pump();

    expect(find.text('39 wks'), findsWidgets);
    expect(find.text('37 wks'), findsNothing);

    final qualityStorageDaysField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Quality Storage Days',
    );
    expect(qualityStorageDaysField, findsOneWidget);

    await tester.enterText(qualityStorageDaysField, '14');
    await tester.pump();

    expect(find.text('37 wks'), findsWidgets);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('egg quality house scope card edits active sample identities', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(tester);
    final provider = Provider.of<AuditProvider>(
      tester.element(find.byType(EggStorageScreen)),
      listen: false,
    );

    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
    await tester.pumpAndSettle();

    final houseField = find.widgetWithText(TextFormField, 'House');
    expect(houseField, findsOneWidget);

    await tester.enterText(houseField, '9');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, 'H9'), findsOneWidget);
    expect(provider.activeStationSample.houseNo, '9');
    expect(provider.activeStationSample.houseLabel, 'House 9');

    expect(find.text('Machine scope'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Setter'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Hatcher'), findsNothing);
  });

  testWidgets('egg quality house field stays active while entering a number', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(tester);
    final provider = Provider.of<AuditProvider>(
      tester.element(find.byType(EggStorageScreen)),
      listen: false,
    );

    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
    await tester.pumpAndSettle();

    final houseField = find.widgetWithText(TextFormField, 'House');
    await tester.tap(houseField);
    await tester.pump();

    final editingFocus = FocusManager.instance.primaryFocus;
    expect(editingFocus, isNotNull);

    await tester.enterText(houseField, '1');
    await tester.pump();

    expect(find.widgetWithText(TextFormField, 'House'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus, same(editingFocus));
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('egg quality house field syncs metadata changes while idle', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(tester);
    final provider = Provider.of<AuditProvider>(
      tester.element(find.byType(EggStorageScreen)),
      listen: false,
    );

    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
    await tester.pumpAndSettle();

    provider.updateSampleMetadata({'houseNo': '8'});
    await tester.pumpAndSettle();

    final houseField = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'House',
      ),
    );
    expect(houseField.controller?.text, '8');
  });

  testWidgets('egg quality generated house scope labels leave fields empty', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(tester);
    final provider = Provider.of<AuditProvider>(
      tester.element(find.byType(EggStorageScreen)),
      listen: false,
    );

    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, 'H1'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'H'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is TextField &&
                  widget.decoration?.labelText == 'House',
            ),
          )
          .controller
          ?.text,
      '',
    );

    expect(find.text('Machine scope'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'SH'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Setter'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Hatcher'), findsNothing);
  });

  testWidgets(
    'egg quality shows BMK egg weight from the default storage context',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.binding.setSurfaceSize(const Size(700, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpScreen(
        tester,
        bmkEggWeightLookup: (breed, ageWeek) async {
          expect(breed, 'Ross 308');
          expect(ageWeek, 39);
          return 68.0;
        },
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Egg Weights & Uniformity'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Egg Weights & Uniformity'));
      await tester.pumpAndSettle();

      final summary = find.byKey(const ValueKey('egg-weight-metric-summary'));
      expect(summary, findsOneWidget);
      expect(
        find.descendant(of: summary, matching: find.text('BMK Egg Weight')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: summary, matching: find.text('68.0g')),
        findsOneWidget,
      );
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('egg weight summary follows chick weight card design', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(tester);

    await tester.ensureVisible(find.text('Egg Weights & Uniformity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Egg Weights & Uniformity'));
    await tester.pumpAndSettle();

    final summary = find.byKey(const ValueKey('egg-weight-metric-summary'));
    expect(summary, findsOneWidget);
    expect(
      find.descendant(of: summary, matching: find.text('BMK Age')),
      findsNothing,
    );
    expect(
      find.descendant(of: summary, matching: find.text('Min')),
      findsNothing,
    );
    expect(
      find.descendant(of: summary, matching: find.text('Max')),
      findsNothing,
    );

    final orderedLabels = [
      'Sample Size',
      'BMK Egg Weight',
      'Avg Weight',
      'Low Margin',
      'High Margin',
      'Uniformity',
      'C.V',
    ];

    var previousTop = double.negativeInfinity;
    for (final label in orderedLabels) {
      final labelFinder = find.descendant(
        of: summary,
        matching: find.text(label),
      );
      expect(labelFinder, findsOneWidget);
      final top = tester.getTopLeft(labelFinder).dy;
      expect(top, greaterThan(previousTop));
      previousTop = top;
    }
  });

  testWidgets('egg house add cancels safely and rejects normalized duplicate', (
    tester,
  ) async {
    await pumpScreen(tester);
    final provider = Provider.of<AuditProvider>(
      tester.element(find.byType(EggStorageScreen)),
      listen: false,
    );

    await enterCompareModeWithFirstHouse(tester, house: '12');
    expect(provider.isCompareMode, isTrue);
    expect(provider.stationSamples, hasLength(1));

    await tester.ensureVisible(find.byTooltip('Add house sample'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add house sample'));
    await tester.pumpAndSettle();
    expect(find.text('Add House scope'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('scope-identity-cancel')));
    await tester.pumpAndSettle();
    expect(provider.stationSamples, hasLength(1));

    await tester.ensureVisible(find.byTooltip('Add house sample'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add house sample'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('scope-identity-house')),
      'H12',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('scope-identity-add')));
    await tester.pumpAndSettle();

    expect(
      find.text('A House scope with this identity already exists.'),
      findsOneWidget,
    );
    expect(provider.stationSamples, hasLength(1));
  });

  testWidgets('egg house removal confirms before discarding entered results', (
    tester,
  ) async {
    await pumpScreen(tester);
    final provider = Provider.of<AuditProvider>(
      tester.element(find.byType(EggStorageScreen)),
      listen: false,
    );
    await enterCompareModeWithFirstHouse(tester, house: '12');
    await addNamedScope(
      tester,
      tooltip: 'Add house sample',
      identities: const {'house': '13'},
    );
    provider.updateField('esEggSampleSize', 30);
    await tester.pump();

    await tester.ensureVisible(find.byTooltip('Remove active house sample'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove active house sample'));
    await tester.pumpAndSettle();
    expect(find.text('Remove scope?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('scope-removal-cancel')));
    await tester.pumpAndSettle();
    expect(provider.stationSamples, hasLength(2));
    expect(provider.activeDraft.esEggSampleSize, 30);

    await tester.tap(find.byTooltip('Remove active house sample'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scope-removal-confirm')));
    await tester.pumpAndSettle();
    expect(provider.stationSamples, hasLength(1));
    expect(provider.activeStationSample.houseNo, '12');
  });
}
