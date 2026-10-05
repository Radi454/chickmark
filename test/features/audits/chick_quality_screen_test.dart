import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/data/models/sampling_scope.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/data/repositories/audit_repository.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/temperature_capture/temperature_capture_screen.dart';
import 'package:hatchaudit/features/audits/screens/audit_context_screen.dart';
import 'package:hatchaudit/features/audits/screens/chick_quality_screen.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/providers/app_provider.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:hatchaudit/features/audits/widgets/audit_numeric_keyboard.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'support/memory_panel_sampling_state_repository.dart';

class MockSupabaseService extends Mock implements SupabaseService {}

class MockAuditRepository extends Mock implements AuditRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var screenSession = 0;
  const connectivityChannel = MethodChannel(
    'dev.fluttercommunity.plus/connectivity',
  );

  setUpAll(() {
    registerFallbackValue(
      AuditModel(
        id: 'fallback',
        auditType: 'Chicks',
        customerId: 'customer-1',
        flockId: 'flock-1',
        date: DateTime(2026, 4, 27),
        hatchNumber: 1,
        status: 'active',
        createdBy: 'auditor-1',
        createdAt: DateTime(2026, 4, 27),
        updatedAt: DateTime(2026, 4, 27),
      ),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, (call) async {
          if (call.method == 'check') return ['wifi'];
          return null;
        });
  });

  AuditProvider screenProvider() => AuditProvider(
    autosaveEnabled: false,
    panelSamplingStateRepository: MemoryPanelSamplingStateRepository(),
  );

  AuditContextData contextData({
    String? breed,
    int? flockAgeWeeks,
    String? sessionId,
  }) => AuditContextData(
    auditType: 'Chicks',
    customerId: 'customer-1',
    flockId: 'flock-1',
    sessionId: sessionId ?? 'chick-screen-${screenSession++}',
    breed: breed,
    flockAgeWeeks: flockAgeWeeks,
    date: '2026-04-27',
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    AuditProvider? provider,
    AuditContextData? contextOverride,
    AuditModel? initialAudit,
    List<StationSampleModel> initialStationSamples = const [],
    ChickBmkWeightLookup? bmkChickWeightLookup,
  }) async {
    final providerForScreen = provider ?? screenProvider();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuditProvider>(
            create: (_) => providerForScreen,
          ),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: MockSupabaseService()),
          ),
          ChangeNotifierProvider(create: (_) => AppProvider()),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: ChickQualityScreen(
            context: contextOverride ?? contextData(),
            initialAudit: initialAudit,
            initialStationSamples: initialStationSamples,
            bmkChickWeightLookup: bmkChickWeightLookup,
          ),
        ),
      ),
    );
    await providerForScreen.loadPanelSamplingState('chick_quality');
    await providerForScreen.loadPanelSamplingState('chick_weights');
    await tester.pump();
  }

  Future<void> enterAuditNumber(
    WidgetTester tester,
    Finder field,
    String value,
  ) async {
    await tester.tap(field);
    await tester.pumpAndSettle();
    for (final char in value.split('')) {
      await tester.tap(find.text(char).last);
      await tester.pump();
    }
    final hideKeyboard = find.byIcon(Icons.keyboard_hide);
    if (hideKeyboard.evaluate().isNotEmpty) {
      await tester.tap(hideKeyboard.last);
    }
    await tester.pumpAndSettle();
  }

  Future<void> addNamedScope(
    WidgetTester tester, {
    required String tooltip,
    required Map<String, String> identities,
  }) async {
    final provider = Provider.of<AuditProvider>(
      tester.element(find.byType(ChickQualityScreen)),
      listen: false,
    );
    final panelKey = tooltip.contains('house')
        ? 'chick_weights'
        : 'chick_quality';
    final state = await provider.loadPanelSamplingState(panelKey);
    final serial = state.serialHighWatermark + 1;
    final isHouse = panelKey == 'chick_weights';
    final scope = await provider.addPanelScopeIdentity(
      panelKey,
      level: isHouse ? SamplingScopeLevel.house : SamplingScopeLevel.setter,
      parentId: null,
      identity: isHouse
          ? {
              'id': 'test-house-$serial',
              'code': identities['house'] ?? '$serial',
              'name': 'House ${identities['house'] ?? serial}',
            }
          : {
              'setter': identities['setter'] ?? 'S$serial',
              'hatcher': identities['hatcher'] ?? 'H$serial',
            },
    );
    final sample = await provider.addPanelTerminalSample(
      panelKey,
      parentId: scope.id,
    );
    await provider.selectPanelSample(panelKey, sample.sampleId!);
    await tester.pumpAndSettle();
  }

  testWidgets('renders the split workbench instead of the tabbed screen', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(
      find.byKey(const ValueKey('chick-quality-header-card')),
      findsOneWidget,
    );
    expect(find.text('Audit station'), findsOneWidget);
    expect(find.text('Pasgar Score'), findsOneWidget);

    expect(
      find.byKey(const ValueKey('chick-quality-workbench')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chick-quality-tabs-bar')), findsNothing);
    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(TabBarView), findsNothing);
    expect(find.text('CHA Environmental'), findsNothing);
  });

  testWidgets('shows advisory registry quality flags without a save blocker', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      initialAudit: AuditModel(
        id: 'quality-warning-audit',
        auditType: 'Chicks',
        customerId: 'customer-1',
        flockId: 'flock-1',
        date: DateTime(2026, 4, 27),
        hatchNumber: 1,
        status: 'active',
        createdBy: 'auditor-1',
        createdAt: DateTime(2026, 4, 27),
        updatedAt: DateTime(2026, 4, 27),
        pasgarSampleSize: 40,
      ),
    );

    expect(
      find.byKey(const ValueKey('chick-quality-advisory-banner')),
      findsOneWidget,
    );
    expect(find.textContaining('Review'), findsOneWidget);
    expect(find.textContaining('save is still allowed'), findsOneWidget);
  });

  testWidgets('shows advisory persisted on a reloaded Chick sample', (
    tester,
  ) async {
    final now = DateTime(2026, 4, 27);
    await pumpScreen(
      tester,
      initialStationSamples: [
        StationSampleModel(
          id: 'persisted-quality-flag',
          auditSessionId: 'session-1',
          stationType: 'chicks',
          sectorType: StationSampleModel.sectorChickQuality,
          sampleIndex: 1,
          qualityStatus: 'FLAG',
          qualityFlags:
              '[{"tier":"FLAG","schemaKey":"chicks.legacy_combined","fieldKey":"\$sample","code":"legacy_quality_unclassified"}]',
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );

    expect(
      find.byKey(const ValueKey('chick-quality-advisory-banner')),
      findsOneWidget,
    );
  });

  testWidgets('Chicks CVT unit selector defaults to Fahrenheit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpScreen(tester);

    await tester.ensureVisible(find.text('Chick Vent Temperature').first);
    await tester.tap(find.text('Chick Vent Temperature').first);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('chicks-cvt-unit-selector')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('chicks-cvt-unit-f')))
          .selected,
      isTrue,
    );
  });

  testWidgets('renders all chick quality panels in one scrollable workbench', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(
      find.byKey(const ValueKey('chick-quality-panel-pasgar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chick-quality-panel-yfbm')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chick-quality-panel-cvt')),
      findsOneWidget,
    );
    expect(find.text('PG'), findsNothing);
    expect(find.text('YF'), findsNothing);
    expect(find.text('CVT'), findsNothing);
    expect(find.text('PM'), findsNothing);
    expect(find.byKey(const ValueKey('pasgar-sample-size-card')), findsNothing);

    await tester.ensureVisible(find.text('Pasgar Score'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pasgar Score'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('pasgar-sample-size-card')),
      findsOneWidget,
    );

    await tester.drag(
      find.byKey(const ValueKey('chick-quality-scroll')),
      const Offset(0, -1400),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('chick-quality-panel-pm')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chick-quality-panel-weights')),
      findsOneWidget,
    );
  });

  testWidgets('collapsible chick panels hide result badges', (tester) async {
    await pumpScreen(tester);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('chick-quality-panel-pasgar')),
        matching: find.text('--'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('chick-quality-panel-yfbm')),
        matching: find.text('Stable'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('chick-quality-panel-cvt')),
        matching: find.text('--'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('chick-quality-panel-pm')),
        matching: find.text('Review'),
      ),
      findsNothing,
    );
  });

  testWidgets('machine switch reloads each machine Pasgar values', (
    tester,
  ) async {
    final provider = screenProvider();
    await pumpScreen(tester, provider: provider);

    provider.addChickQualityMachineScopeSample();
    provider.updateSampleMetadata({'setterNo': 'S1', 'hatcherNo': 'H1'});
    provider.updateField('pasgarSampleSize', 40);
    provider.updateField('pasgarReflexes', 3);
    provider.updateField('pasgarBeak', 1);

    provider.addChickQualityMachineScopeSample();
    provider.updateSampleMetadata({'setterNo': 'S2', 'hatcherNo': 'H2'});
    provider.updateField('pasgarSampleSize', 40);
    provider.updateField('pasgarReflexes', 7);
    provider.updateField('pasgarBeak', 2);
    await tester.pump();

    await tester.ensureVisible(find.text('Pasgar Score'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pasgar Score'));
    await tester.pumpAndSettle();

    String pasgarFieldText(int index) {
      final fields = tester.widgetList<AuditNumericField>(
        find.descendant(
          of: find.byKey(const ValueKey('pasgar-defect-counts-card')),
          matching: find.byType(AuditNumericField),
        ),
      );
      return fields.elementAt(index).controller.text;
    }

    expect(pasgarFieldText(0), '7');
    expect(pasgarFieldText(1), '2');

    provider.switchSample(0);
    await tester.pumpAndSettle();

    expect(pasgarFieldText(0), '3');
    expect(pasgarFieldText(1), '1');
  });

  testWidgets('quality form controllers follow the active sampling leaf', (
    tester,
  ) async {
    final provider = screenProvider();
    final now = DateTime(2026, 4, 27, 12);
    final initialAudit = AuditModel(
      id: 'chick-audit-1',
      auditType: 'Chicks',
      customerId: 'customer-1',
      flockId: 'flock-1',
      date: now,
      hatchNumber: 1,
      status: 'active',
      createdBy: 'auditor-1',
      createdAt: now,
      updatedAt: now,
      pasgarSampleSize: 40,
      pasgarReflexes: 3,
      pasgarBeak: 1,
    );
    await pumpScreen(
      tester,
      provider: provider,
      initialAudit: initialAudit,
      contextOverride: contextData(sessionId: 'chick-quality-sample-switch'),
    );
    final firstSampleId = provider.activeSampleIdFor('chick_quality')!;
    final secondSample = await provider.addPanelTerminalSample(
      'chick_quality',
      parentId: null,
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Pasgar Score'));
    await tester.tap(find.text('Pasgar Score'));
    await tester.pumpAndSettle();
    List<AuditNumericField> pasgarFields() => tester
        .widgetList<AuditNumericField>(
          find.descendant(
            of: find.byKey(const ValueKey('pasgar-defect-counts-card')),
            matching: find.byType(AuditNumericField),
          ),
        )
        .toList();

    await enterAuditNumber(tester, find.byWidget(pasgarFields()[0]), '6');
    await enterAuditNumber(tester, find.byWidget(pasgarFields()[1]), '2');
    expect(provider.activeDraft.pasgarReflexes, 6);
    expect(provider.activeDraft.pasgarBeak, 2);

    await provider.selectPanelSample('chick_quality', firstSampleId);
    await tester.pumpAndSettle();
    expect(pasgarFields()[0].controller.text, '3');
    expect(pasgarFields()[1].controller.text, '1');

    await provider.selectPanelSample('chick_quality', secondSample.sampleId!);
    await tester.pumpAndSettle();
    expect(pasgarFields()[0].controller.text, '6');
    expect(pasgarFields()[1].controller.text, '2');
  });

  testWidgets('culled chicks analysis panel follows PM and updates draft', (
    tester,
  ) async {
    final provider = screenProvider();
    await pumpScreen(tester, provider: provider);

    final pmPanel = find.byKey(const ValueKey('chick-quality-panel-pm'));
    final culledPanel = find.byKey(
      const ValueKey('chick-quality-panel-culled-analysis'),
    );

    expect(pmPanel, findsOneWidget);
    expect(culledPanel, findsOneWidget);
    expect(
      tester.getTopLeft(culledPanel).dy,
      greaterThan(tester.getTopLeft(pmPanel).dy),
    );

    await tester.ensureVisible(culledPanel);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Culled Chicks Analysis'));
    await tester.pumpAndSettle();

    expect(find.text('Open / unhealed navel'), findsOneWidget);
    final navelCountField = find.byKey(
      const ValueKey('culled-chicks-count-navel_open_unhealed'),
    );
    final navelIncrementButton = find.byKey(
      const ValueKey('culled-chicks-increment-navel_open_unhealed'),
    );
    final navelDecrementButton = find.byKey(
      const ValueKey('culled-chicks-decrement-navel_open_unhealed'),
    );
    expect(navelCountField, findsOneWidget);
    expect(navelIncrementButton, findsOneWidget);
    expect(navelDecrementButton, findsOneWidget);

    await tester.tap(navelIncrementButton);
    await tester.pumpAndSettle();
    expect(provider.activeDraft.culledChicksTotalEggSet, 19200);
    expect(
      provider.activeDraft.culledChicksAffectedPct,
      closeTo(1 / 19200 * 100, 0.000001),
    );
    expect(
      provider.activeDraft.culledChicksTopSubtype,
      'Open / unhealed navel',
    );

    await tester.tap(navelDecrementButton);
    await tester.pumpAndSettle();
    expect(provider.activeDraft.culledChicksAffectedPct, 0.0);
    expect(provider.activeDraft.culledChicksTopSubtype, isNull);
    expect(navelCountField, findsOneWidget);
    expect(
      find.text('Belly not fully closed, wet or inflamed navel'),
      findsNothing,
    );
    expect(find.textContaining('Causes:'), findsNothing);
    expect(find.textContaining('Ref:'), findsNothing);
    expect(find.text('Navel'), findsOneWidget);
    expect(find.text('Belly'), findsOneWidget);
    expect(find.text('Sticky'), findsOneWidget);
    expect(find.text('Dehydrated'), findsOneWidget);
    expect(find.text('Legs'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Belly')).dy,
      greaterThan(tester.getTopLeft(find.text('Navel')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Sticky')).dy,
      greaterThan(tester.getTopLeft(find.text('Belly')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Dehydrated')).dy,
      greaterThan(tester.getTopLeft(find.text('Sticky')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Legs')).dy,
      greaterThan(tester.getTopLeft(find.text('Dehydrated')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Residual yolk / large abdomen')).dy,
      greaterThan(tester.getTopLeft(find.text('Belly')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Residual yolk / large abdomen')).dy,
      lessThan(tester.getTopLeft(find.text('Sticky')).dy),
    );
    expect(find.text('Albumen on feathers / glued down'), findsNothing);
    expect(
      find.byKey(
        const ValueKey('culled-chicks-count-sticky_albumen_glued_down'),
      ),
      findsNothing,
    );
    expect(find.text('Wet chick'), findsNothing);
    expect(
      find.byKey(const ValueKey('culled-chicks-count-sticky_wet_chick')),
      findsNothing,
    );
    expect(find.text('Short beak'), findsNothing);
    expect(
      find.byKey(const ValueKey('culled-chicks-count-head_short_beak')),
      findsNothing,
    );
    expect(find.text('Weak / inactive chick'), findsNothing);
    expect(
      find.byKey(
        const ValueKey('culled-chicks-count-small_weak_weak_inactive_chick'),
      ),
      findsNothing,
    );
    expect(
      tester.getTopLeft(find.text('Dehydrated / burned chick')).dy,
      greaterThan(tester.getTopLeft(find.text('Dehydrated')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Dehydrated / burned chick')).dy,
      lessThan(tester.getTopLeft(find.text('Legs')).dy),
    );

    expect(find.text('19200'), findsOneWidget);
    await enterAuditNumber(
      tester,
      find.byKey(const ValueKey('culled-chicks-count-navel_open_unhealed')),
      '3',
    );

    expect(provider.activeDraft.culledChicksTotalEggSet, 19200);
    expect(
      provider.activeDraft.culledChicksAnalysisJson,
      contains('navel_open_unhealed'),
    );
    expect(provider.activeDraft.culledChicksAnalysisJson, contains('"pct"'));
    expect(
      provider.activeDraft.culledChicksAnalysisJson,
      contains('"count":3'),
    );
    expect(
      provider.activeDraft.culledChicksAffectedPct,
      closeTo(3 / 19200 * 100, 0.000001),
    );
    expect(
      provider.activeDraft.culledChicksTopSubtype,
      'Open / unhealed navel',
    );
  });

  testWidgets('YFBM entries are edited from a modal entry sheet', (
    tester,
  ) async {
    final provider = screenProvider();
    await pumpScreen(tester, provider: provider);

    await tester.ensureVisible(
      find.byKey(const ValueKey('chick-quality-panel-yfbm')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('YFBM'));
    await tester.pumpAndSettle();

    expect(find.text('YFBM Entries'), findsNothing);
    expect(find.text('Enter YFBM Entries'), findsOneWidget);
    expect(find.text('0/10'), findsOneWidget);
    expect(find.text('Target 8-10%'), findsOneWidget);

    await tester.tap(find.text('Enter YFBM Entries'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('yfbm-entries-sheet')), findsOneWidget);
    expect(find.text('YFBM Entries'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('yfbm-entries-sheet')),
        matching: find.text('0 of 10 rows complete'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('yfbm-entries-sheet')),
        matching: find.text('Target 8-10%'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('yfbm-entries-sheet')),
        matching: find.text('YFBM %'),
      ),
      findsNothing,
    );

    await enterAuditNumber(
      tester,
      find.byKey(const ValueKey('yfbm-entry-chick-0')),
      '40',
    );
    await enterAuditNumber(
      tester,
      find.byKey(const ValueKey('yfbm-entry-yolk-0')),
      '4',
    );
    await tester.pumpAndSettle();

    expect(provider.activeDraft.yfbmAvgPct, 10.0);
    expect(provider.activeDraft.yfbmCvPct, 0.0);
    final entries = jsonDecode(provider.activeDraft.yfbmEntries!) as List;
    expect(entries.first['chickWeight'], 40.0);
    expect(entries.first['yolkWeight'], 4.0);
  });

  testWidgets('CVT Capture readings launches the reusable capture screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final provider = screenProvider();
    await pumpScreen(tester, provider: provider);

    await tester.ensureVisible(
      find.byKey(const ValueKey('chick-quality-panel-cvt')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chick Vent Temperature'));
    await tester.pumpAndSettle();

    final scanButton = find.widgetWithText(OutlinedButton, 'Capture readings');
    await tester.ensureVisible(scanButton);
    await tester.tap(scanButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(TemperatureCaptureScreen), findsOneWidget);
    expect(find.text('Step 1 of 9'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(TemperatureCaptureScreen), findsNothing);
  });

  testWidgets('CVT uses an EST-style grid with target and capture action', (
    tester,
  ) async {
    final provider = screenProvider();
    await pumpScreen(tester, provider: provider);

    await tester.ensureVisible(
      find.byKey(const ValueKey('chick-quality-panel-cvt')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chick Vent Temperature'));
    await tester.pumpAndSettle();

    expect(find.text('Capture readings'), findsOneWidget);
    expect(find.text('103-105°F'), findsOneWidget);
    expect(find.byKey(const ValueKey('cvt-temperature-grid')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chicks-cvt-unit-selector')),
      findsOneWidget,
    );
    expect(find.text('CVT Measurements'), findsNothing);

    expect(
      find.byKey(const ValueKey('est-grid-input-front_top')),
      findsNothing,
    );
    final frontTopCell = find.byKey(const ValueKey('est-grid-cell-front_top'));
    await tester.ensureVisible(frontTopCell);
    await tester.tap(frontTopCell);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(TemperatureCaptureScreen), findsOneWidget);
    expect(find.text('Front - Top'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    final celsiusChip = find.byKey(const ValueKey('chicks-cvt-unit-c'));
    await tester.ensureVisible(celsiusChip);
    await tester.tap(celsiusChip);
    await tester.pump();

    expect(find.text('39.4-40.6°C'), findsOneWidget);
    expect(provider.activeDraft.cvtAvg, isNull);
    expect(provider.activeDraft.cvtReadingsJson, isNull);
  });

  testWidgets('PM Necropsy shows the revised lesion checklist', (tester) async {
    final provider = screenProvider();
    await pumpScreen(tester, provider: provider);

    await tester.ensureVisible(
      find.byKey(const ValueKey('chick-quality-panel-pm')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('PM Necropsy'));
    await tester.pumpAndSettle();

    expect(find.text('Omphalitis'), findsOneWidget);
    expect(find.text('Gaseous Ceca'), findsOneWidget);
    expect(find.text('Gizzard Erosions'), findsOneWidget);
    expect(find.text('Air Sac Caseations'), findsOneWidget);
    expect(find.text('Urolithiasis (Urate Deposits)'), findsOneWidget);
    expect(find.text('Pulmonary Granuloma'), findsNothing);
    expect(find.text('Swollen Joints'), findsNothing);
    expect(find.text('Stunted Organs'), findsNothing);
    expect(find.text('Nephritis'), findsOneWidget);
    expect(find.text('General Septicemia'), findsOneWidget);
    expect(find.text('Gasping'), findsNothing);
    expect(find.text('Gasping Present'), findsNothing);
    expect(find.text('Deformities'), findsNothing);
    expect(find.text('Exposed Brain'), findsNothing);

    expect(find.text('Unabsorbed Yolk'), findsNothing);
    expect(find.text('Perihepatitis'), findsNothing);
    expect(find.text('Pericarditis'), findsNothing);
    expect(find.text('Airsac Acute'), findsNothing);
    expect(find.text('Airsac Chronic'), findsNothing);
    expect(find.text('Pulmonary Hemorrhage'), findsNothing);

    final expectedLesionOrder = [
      'Omphalitis',
      'Gaseous Ceca',
      'Air Sac Caseations',
      'Urolithiasis (Urate Deposits)',
      'Nephritis',
      'General Septicemia',
      'Gizzard Erosions',
    ];
    for (var i = 0; i < expectedLesionOrder.length - 1; i += 1) {
      expect(
        tester.getTopLeft(find.text(expectedLesionOrder[i])).dy,
        lessThan(tester.getTopLeft(find.text(expectedLesionOrder[i + 1])).dy),
      );
    }

    expect(find.text('Others'), findsWidgets);
    expect(find.byKey(const ValueKey('pm-add-other-lesion')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('pm-other-lesion-name-0')),
      'Retained shell',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('pm-other-lesion-count-0')),
    );
    await tester.pumpAndSettle();
    await enterAuditNumber(
      tester,
      find.byKey(const ValueKey('pm-other-lesion-count-0')),
      '2',
    );
    await tester.tap(find.byKey(const ValueKey('pm-add-other-lesion')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('pm-other-lesion-name-1')),
      findsOneWidget,
    );
    final otherLesions =
        jsonDecode(provider.activeDraft.pmOtherLesionsJson!) as List<dynamic>;
    expect(otherLesions.first['name'], 'Retained shell');
    expect(otherLesions.first['count'], 2);
  });

  testWidgets('separates machine quality scope from house weight scope', (
    tester,
  ) async {
    await pumpScreen(tester);

    final qualityPanel = find.byKey(
      const ValueKey('chick-quality-machine-sampling'),
    );
    expect(qualityPanel, findsOneWidget);
    expect(
      find.descendant(of: qualityPanel, matching: find.text('Sampling')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: qualityPanel, matching: find.text('Setter / Hatcher')),
      findsOneWidget,
    );
    expect(find.byTooltip('Add Setter / Hatcher'), findsOneWidget);
    expect(find.text('Machine scope'), findsNothing);
    expect(find.byTooltip('Add machine sample'), findsNothing);

    await tester.ensureVisible(
      find.byKey(const ValueKey('chick-quality-panel-weights')),
    );
    await tester.pumpAndSettle();

    final weightsPanel = find.byKey(
      const ValueKey('chick-quality-panel-weights'),
    );
    expect(
      find.descendant(of: weightsPanel, matching: find.text('Sampling')),
      findsOneWidget,
    );
    expect(find.byTooltip('Add House'), findsOneWidget);
    expect(find.text('House scope'), findsNothing);
    expect(
      find.byKey(const ValueKey('chick-weight-metric-summary')),
      findsOneWidget,
    );
    expect(find.text('Compare houses'), findsNothing);
    expect(find.byTooltip('Add house sample'), findsNothing);
    expect(find.text('Enter Weights'), findsOneWidget);
  });

  testWidgets('House comparison activates its own chick-weight leaf', (
    tester,
  ) async {
    final provider = screenProvider();
    await pumpScreen(tester, provider: provider);

    await tester.ensureVisible(
      find.byKey(const ValueKey('chick-quality-panel-weights')),
    );
    await tester.pumpAndSettle();

    final weightsPanel = find.byKey(
      const ValueKey('chick-quality-panel-weights'),
    );
    await addNamedScope(
      tester,
      tooltip: 'Add house sample',
      identities: const {'house': '12'},
    );

    final activeId = provider.activeSampleIdFor('chick_weights');
    expect(activeId, isNotNull);
    expect(
      provider.samplingStateFor('chick_weights')!.pathFor(activeId!).house,
      '12',
    );
    expect(find.text('House 12'), findsOneWidget);
    expect(provider.activeChickWeightSample.houseNo, '12');
    expect(find.byKey(const ValueKey('chick-weight-metric-summary')), findsOneWidget);
    expect(find.text('Enter Weights'), findsOneWidget);
    expect(weightsPanel, findsOneWidget);
  });

  testWidgets(
    'deleting a House branch returns chick weights to pooled state',
    (tester) async {
      final provider = screenProvider();
      await pumpScreen(tester, provider: provider);
      final weightsPanel = find.byKey(
        const ValueKey('chick-quality-panel-weights'),
      );

      await addNamedScope(
        tester,
        tooltip: 'Add house sample',
        identities: const {'house': '12'},
      );

      final state = provider.samplingStateFor('chick_weights')!;
      final house = state.nodes.singleWhere(
        (node) => node.level == SamplingScopeLevel.house,
      );
      provider.updateChickWeightSampleResult(
        weightsJson: '[42.0]',
        avgWeight: 42,
      );
      await provider.deletePanelScopeNode('chick_weights', house.id);
      await tester.pumpAndSettle();

      final pooledId = provider.activeSampleIdFor('chick_weights')!;
      expect(
        provider.samplingStateFor('chick_weights')!.pathFor(pooledId).house,
        isNull,
      );
      expect(provider.activeDraft.chickAvgWeight, isNull);
      expect(
        find.descendant(of: weightsPanel, matching: find.text('Pooled')),
        findsOneWidget,
      );
      expect(find.text('Enter Weights'), findsOneWidget);
    },
  );

  testWidgets('opens the weight sheet from the weights panel', (tester) async {
    await pumpScreen(tester);

    await tester.ensureVisible(
      find.byKey(const ValueKey('chick-quality-panel-weights')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Enter Weights'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enter Weights'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('chick-quality-weight-sheet')),
      findsOneWidget,
    );
    expect(find.text('Chick Weight Sheet'), findsOneWidget);
    expect(find.byKey(const ValueKey('weight-grid-widget')), findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
  });

  testWidgets('weight entry updates the draft after a short debounce', (
    tester,
  ) async {
    final provider = screenProvider();
    await pumpScreen(tester, provider: provider);

    await tester.ensureVisible(
      find.byKey(const ValueKey('chick-quality-panel-weights')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Enter Weights'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enter Weights'));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const ValueKey('chick-quality-weight-sheet'));
    final weightFields = find.descendant(
      of: sheet,
      matching: find.byType(TextField),
    );
    expect(weightFields, findsWidgets);

    await tester.tap(weightFields.at(0));
    await tester.pumpAndSettle();
    for (final digit in ['1', '2']) {
      await tester.tap(find.text(digit).last);
      await tester.pump();
    }

    expect(provider.activeDraft.chickSampleSize, isNull);
    expect(provider.activeDraft.chickAvgWeight, isNull);

    await tester.pump(const Duration(milliseconds: 400));

    expect(provider.activeDraft.chickSampleSize, 1);
    expect(provider.activeDraft.chickAvgWeight, 12.0);
    expect(jsonDecode(provider.activeDraft.chickWeights!), [12.0]);
  });

  testWidgets('chick weight metric summary follows reviewer order', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.ensureVisible(
      find.byKey(const ValueKey('chick-weight-metric-summary')),
    );
    await tester.pumpAndSettle();

    final summary = find.byKey(const ValueKey('chick-weight-metric-summary'));
    final orderedLabels = [
      'Sample Size',
      'BMK Chick Weight',
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

  testWidgets('weight hero renders flock context as a compact strip', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      contextOverride: contextData(breed: 'Ross308', flockAgeWeeks: 41),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('chick-quality-panel-weights')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('chick-weight-context-strip')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chick-weight-flock-tile')), findsNothing);
    expect(find.text('flock-1'), findsWidgets);
    expect(find.text('Ross308'), findsOneWidget);
    expect(find.text('41 wks'), findsWidgets);
  });

  testWidgets('chick BMK follows refreshed flock age and benchmark lookup', (
    tester,
  ) async {
    final provider = screenProvider();
    final staleAudit = AuditModel(
      id: 'chick-stale-bmk',
      auditType: 'Chicks',
      customerId: 'customer-1',
      flockId: 'flock-1',
      date: DateTime(2026, 4, 27),
      hatchNumber: 1,
      status: 'active',
      createdBy: 'auditor-1',
      createdAt: DateTime(2026, 4, 27),
      updatedAt: DateTime(2026, 4, 27),
      chickBmkAge: 30,
    );

    await pumpScreen(
      tester,
      provider: provider,
      initialAudit: staleAudit,
      contextOverride: contextData(
        breed: 'Avian',
        flockAgeWeeks: 37,
        sessionId: 'session-1',
      ),
      bmkChickWeightLookup: (breed, ageWeek) async {
        expect(breed, 'Avian');
        expect(ageWeek, 37);
        return 45;
      },
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('chick-quality-panel-weights')),
    );
    await tester.pumpAndSettle();

    expect(find.text('37 wks'), findsWidgets);
    expect(find.text('30 wks'), findsNothing);
    expect(find.text('45.0g'), findsOneWidget);
    expect(provider.activeDraft.chickBmkAge, 37);
    expect(provider.activeDraft.chickBmkWeight, 45);
  });

  testWidgets('weight hero hides uniform result pill', (tester) async {
    await pumpScreen(tester);

    await tester.ensureVisible(
      find.byKey(const ValueKey('chick-quality-panel-weights')),
    );
    await tester.pumpAndSettle();

    final weightsPanel = find.byKey(
      const ValueKey('chick-quality-panel-weights'),
    );
    expect(
      find.descendant(of: weightsPanel, matching: find.text('Uniform')),
      findsNothing,
    );
    expect(
      find.descendant(of: weightsPanel, matching: find.text('Review')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: weightsPanel,
        matching: find.text('Chick Weights & Uniformity'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('setter and Hatcher pair identity follows the active quality leaf', (
    tester,
  ) async {
    final provider = screenProvider();
    await pumpScreen(tester, provider: provider);
    final qualityPanel = find.byKey(
      const ValueKey('chick-quality-machine-sampling'),
    );

    expect(
      find.descendant(of: qualityPanel, matching: find.text('Sampling')),
      findsOneWidget,
    );

    await addNamedScope(
      tester,
      tooltip: 'Add machine sample',
      identities: const {'setter': '7', 'hatcher': '8'},
    );

    final firstId = provider.activeSampleIdFor('chick_quality')!;
    var state = provider.samplingStateFor('chick_quality')!;
    final pair = state.nodes.singleWhere(
      (node) => node.level == SamplingScopeLevel.setter,
    );
    expect(pair.identity['setter'], '7');
    expect(pair.identity['hatcher'], '8');
    expect(find.text('7 / 8'), findsOneWidget);
    await provider.editPanelScopeIdentity('chick_quality', pair.id, {
      'setter': '9',
      'hatcher': '10',
    });
    await tester.pump();
    state = provider.samplingStateFor('chick_quality')!;
    final edited = state.nodes.singleWhere((node) => node.id == pair.id);
    expect(edited.identity['setter'], '9');
    expect(edited.identity['hatcher'], '10');
    expect(provider.activeSampleIdFor('chick_quality'), firstId);
    expect(find.text('9 / 10'), findsOneWidget);
  });

  testWidgets('deleting a machine branch restores a pooled quality sample', (
    tester,
  ) async {
    final provider = screenProvider();
    await pumpScreen(tester, provider: provider);
    await addNamedScope(
      tester,
      tooltip: 'Add machine sample',
      identities: const {'setter': '7', 'hatcher': '8'},
    );
    provider.updateField('pasgarSampleSize', 100);
    final state = provider.samplingStateFor('chick_quality')!;
    final setter = state.nodes.singleWhere(
      (node) => node.level == SamplingScopeLevel.setter,
    );
    await provider.deletePanelScopeNode('chick_quality', setter.id);
    await tester.pumpAndSettle();

    final activeId = provider.activeSampleIdFor('chick_quality')!;
    expect(
      provider.samplingStateFor('chick_quality')!.pathFor(activeId).setter,
      isNull,
    );
    expect(provider.activeDraft.pasgarSampleSize, isNull);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('chick-quality-machine-sampling')),
        matching: find.text('Pooled'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('machine scope fields stay aligned on phone widths', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(tester);

    await addNamedScope(
      tester,
      tooltip: 'Add machine sample',
      identities: const {'setter': '7', 'hatcher': '8'},
    );
    expect(tester.takeException(), isNull);
    expect(find.text('7 / 8'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chick-quality-machine-sampling')),
      findsOneWidget,
    );
  });

  testWidgets('optional test cards follow the selected quality sample type', (
    tester,
  ) async {
    final provider = screenProvider();
    await pumpScreen(tester, provider: provider);

    await addNamedScope(
      tester,
      tooltip: 'Add machine sample',
      identities: const {'setter': '7', 'hatcher': '8'},
    );

    final firstId = provider.activeSampleIdFor('chick_quality')!;
    await addNamedScope(
      tester,
      tooltip: 'Add machine sample',
      identities: const {'setter': '9', 'hatcher': '10'},
    );
    final secondId = provider.activeSampleIdFor('chick_quality')!;
    expect(secondId, isNot(firstId));
    expect(provider.samplingStateFor('chick_quality')!.samples, hasLength(2));
    expect(find.text('7 / 8'), findsOneWidget);
    expect(find.text('9 / 10'), findsOneWidget);
    provider.updateField('pasgarSampleSize', 100);
    await provider.selectPanelSample('chick_quality', firstId);
    expect(provider.activeDraft.pasgarSampleSize, isNull);
    await provider.selectPanelSample('chick_quality', secondId);
    expect(provider.activeDraft.pasgarSampleSize, 100);
  });

  testWidgets('chick weight leaves retain their own measurements', (
    tester,
  ) async {
    final provider = screenProvider();
    await pumpScreen(tester, provider: provider);
    await addNamedScope(
      tester,
      tooltip: 'Add house sample',
      identities: const {'house': '12'},
    );
    final firstId = provider.activeSampleIdFor('chick_weights')!;
    await addNamedScope(
      tester,
      tooltip: 'Add house sample',
      identities: const {'house': '13'},
    );
    final secondId = provider.activeSampleIdFor('chick_weights')!;
    await provider.selectPanelSample('chick_weights', firstId);
    provider.updateChickWeightSampleResult(
      weightsJson: '[42.0]',
      avgWeight: 42,
    );
    await tester.pump();
    expect(provider.activeDraft.chickAvgWeight, 42);
    expect(jsonDecode(provider.activeDraft.chickWeights!), [42.0]);
    await provider.selectPanelSample('chick_weights', secondId);
    expect(provider.activeDraft.chickAvgWeight, isNull);
    expect(find.byKey(const ValueKey('chick-weight-metric-summary')), findsOneWidget);
  });

  testWidgets(
    'duplicate machine identity is rejected and sibling result is preserved',
    (tester) async {
      final provider = screenProvider();
      await pumpScreen(tester, provider: provider);
      await addNamedScope(
        tester,
        tooltip: 'Add machine sample',
        identities: const {'setter': '7', 'hatcher': '8'},
      );
      await addNamedScope(
        tester,
        tooltip: 'Add machine sample',
        identities: const {'setter': '9', 'hatcher': '10'},
      );
      provider.updateField('pasgarSampleSize', 100);
      final secondId = provider.activeSampleIdFor('chick_quality')!;
      await tester.pump();
      expect(provider.samplingStateFor('chick_quality')!.samples, hasLength(2));
      expect(find.text('7 / 8'), findsOneWidget);
      expect(find.text('9 / 10'), findsOneWidget);
      await provider.selectPanelSample('chick_quality', secondId);
      expect(provider.activeDraft.pasgarSampleSize, 100);
      expect(provider.activeDraft.notes, isNull);
    },
  );

  testWidgets('does not render its own sticky save footer', (tester) async {
    await pumpScreen(tester);

    expect(find.byKey(const ValueKey('chick-quality-footer')), findsNothing);
    expect(find.text('Save Draft'), findsNothing);
    expect(find.text('Complete Station'), findsNothing);
  });
}
