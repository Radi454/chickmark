import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/data/repositories/audit_repository.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/ocr_capture/ocr_capture_screen.dart';
import 'package:hatchaudit/features/audits/screens/audit_context_screen.dart';
import 'package:hatchaudit/features/audits/screens/chick_quality_screen.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/providers/app_provider.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:hatchaudit/features/audits/widgets/audit_numeric_keyboard.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockSupabaseService extends Mock implements SupabaseService {}

class MockAuditRepository extends Mock implements AuditRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  AuditContextData contextData({String? breed, int? flockAgeWeeks}) =>
      AuditContextData(
        auditType: 'Chicks',
        customerId: 'customer-1',
        flockId: 'flock-1',
        breed: breed,
        flockAgeWeeks: flockAgeWeeks,
        date: '2026-04-27',
      );

  Future<void> pumpScreen(
    WidgetTester tester, {
    AuditProvider? provider,
    AuditContextData? contextOverride,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuditProvider>(
            create: (_) => provider ?? AuditProvider(autosaveEnabled: false),
          ),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: MockSupabaseService()),
          ),
          ChangeNotifierProvider(create: (_) => AppProvider()),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: ChickQualityScreen(context: contextOverride ?? contextData()),
        ),
      ),
    );
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

  testWidgets('renders the split workbench instead of the tabbed screen', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(
      find.byKey(const ValueKey('chick-quality-header-card')),
      findsOneWidget,
    );
    expect(find.text('Audit station'), findsOneWidget);
    expect(find.text('Chicks'), findsWidgets);
    expect(find.text('Hatchery'), findsOneWidget);

    expect(
      find.byKey(const ValueKey('chick-quality-workbench')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chick-quality-tabs-bar')), findsNothing);
    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(TabBarView), findsNothing);
    expect(find.text('CHA Environmental'), findsNothing);
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
    final provider = AuditProvider(autosaveEnabled: false);
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

  testWidgets('culled chicks analysis panel follows PM and updates draft', (
    tester,
  ) async {
    final provider = AuditProvider(autosaveEnabled: false);
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
      isNot(contains('"count"')),
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
    final provider = AuditProvider(autosaveEnabled: false);
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

  testWidgets('CVT Scan readings launches the reusable OCR capture screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final provider = AuditProvider(autosaveEnabled: false);
    await pumpScreen(tester, provider: provider);

    await tester.ensureVisible(
      find.byKey(const ValueKey('chick-quality-panel-cvt')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chick Vent Temperature'));
    await tester.pumpAndSettle();

    final scanButton = find.widgetWithText(OutlinedButton, 'Scan readings');
    await tester.ensureVisible(scanButton);
    await tester.tap(scanButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(OcrCaptureScreen), findsOneWidget);
    expect(find.text('Step 1 of 9'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(OcrCaptureScreen), findsNothing);
  });

  testWidgets('CVT uses an EST-style grid with target and capture action', (
    tester,
  ) async {
    final provider = AuditProvider(autosaveEnabled: false);
    await pumpScreen(tester, provider: provider);

    await tester.ensureVisible(
      find.byKey(const ValueKey('chick-quality-panel-cvt')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chick Vent Temperature'));
    await tester.pumpAndSettle();

    expect(find.text('Scan readings'), findsOneWidget);
    expect(find.text('103-105°F'), findsOneWidget);
    expect(find.byKey(const ValueKey('cvt-temperature-grid')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chicks-cvt-unit-selector')),
      findsOneWidget,
    );
    expect(find.text('CVT Measurements'), findsNothing);

    await enterAuditNumber(
      tester,
      find.byKey(const ValueKey('est-grid-input-front_top')),
      '104',
    );
    await tester.pumpAndSettle();

    expect(provider.activeDraft.cvtAvg, 104.0);
    expect(provider.activeDraft.cvtCvPct, 0.0);
    final readings =
        jsonDecode(provider.activeDraft.cvtReadingsJson!)
            as Map<String, dynamic>;
    expect(readings['front_top'], 104.0);

    await tester.tap(find.byKey(const ValueKey('chicks-cvt-unit-c')));
    await tester.pump();

    expect(
      tester
          .widget<AuditNumericField>(
            find.byKey(const ValueKey('est-grid-input-front_top')),
          )
          .controller
          .text,
      '40.0',
    );
    expect(provider.activeDraft.cvtAvg, 104.0);
    expect(
      (jsonDecode(provider.activeDraft.cvtReadingsJson!)
          as Map<String, dynamic>)['front_top'],
      104.0,
    );
  });

  testWidgets('PM Necropsy shows the revised lesion checklist', (tester) async {
    final provider = AuditProvider(autosaveEnabled: false);
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

    expect(
      find.byKey(const ValueKey('chick-quality-machine-sampling')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('chick-quality-machine-sampling')),
        matching: find.text('Chick Quality'),
      ),
      findsNothing,
    );
    expect(find.text('Quality sampling'), findsNothing);
    expect(find.text('Machine ID'), findsNothing);
    expect(find.text('Machine scope'), findsOneWidget);
    expect(find.text('Active machine'), findsNothing);
    expect(find.text('Setter and hatcher pair'), findsNothing);
    expect(find.text('One sample'), findsNothing);
    expect(find.text('Multisamples'), findsNothing);
    expect(find.text('Pool'), findsWidgets);
    expect(find.byTooltip('Add machine sample'), findsOneWidget);
    expect(find.byTooltip('Remove active machine sample'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Setter'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Hatcher'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('chick-quality-machine-sampling')),
        matching: find.byType(SegmentedButton<bool>),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('chick-quality-machine-sampling')),
        matching: find.byKey(const ValueKey('quality-scope-selected-icon')),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('chick-quality-machine-sampling')),
        matching: find.byKey(const ValueKey('quality-scope-multi-icon')),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('quality-scope-segment-single')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('quality-scope-segment-multiple')),
      findsNothing,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('chick-quality-panel-weights')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sample Mode'), findsNothing);
    expect(find.text('Chick Sample Mode'), findsNothing);
    expect(find.text('House scope'), findsOneWidget);
    expect(find.text('Active house'), findsNothing);
    expect(find.text('Weight sample source'), findsNothing);
    expect(find.text('One house'), findsNothing);
    expect(find.text('Compare houses'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('chick-quality-panel-weights')),
        matching: find.byType(SegmentedButton<bool>),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('house-scope-selected-icon')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('house-scope-multi-icon')), findsNothing);
    expect(
      find.byKey(const ValueKey('house-scope-segment-single')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('house-scope-segment-multiple')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('chick-weight-metric-summary')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('chick-quality-panel-weights')),
        matching: find.byType(GridView),
      ),
      findsNothing,
    );

    expect(find.text('House Samples'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('chick-quality-panel-weights')),
        matching: find.text('Pool'),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Add house sample'), findsOneWidget);
    expect(find.byTooltip('Remove active house sample'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'House'), findsNothing);
  });

  testWidgets('house scope edits the active chick weight house number', (
    tester,
  ) async {
    final provider = AuditProvider(autosaveEnabled: false);
    await pumpScreen(tester, provider: provider);

    await tester.ensureVisible(
      find.byKey(const ValueKey('chick-quality-panel-weights')),
    );
    await tester.pumpAndSettle();

    final weightsPanel = find.byKey(
      const ValueKey('chick-quality-panel-weights'),
    );
    expect(find.text('House scope'), findsOneWidget);
    expect(find.text('House Samples'), findsNothing);
    expect(find.text('Active house'), findsNothing);
    expect(find.text('Weight sample source'), findsNothing);
    expect(
      find.descendant(of: weightsPanel, matching: find.text('Pool')),
      findsOneWidget,
    );
    expect(find.text('H1'), findsNothing);
    expect(find.text('Label'), findsNothing);
    expect(find.byTooltip('Add house sample'), findsOneWidget);
    expect(find.byTooltip('Remove active house sample'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'House'), findsNothing);

    await tester.tap(find.byTooltip('Add house sample'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: weightsPanel, matching: find.text('Pool')),
      findsNothing,
    );
    expect(
      find.descendant(of: weightsPanel, matching: find.text('H1')),
      findsNothing,
    );
    expect(find.text('H'), findsWidgets);
    expect(find.byTooltip('Remove active house sample'), findsOneWidget);
    final houseField = find.widgetWithText(TextFormField, 'House');
    expect(houseField, findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: weightsPanel,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is TextField &&
                    widget.decoration?.labelText == 'House',
              ),
            ),
          )
          .controller
          ?.text,
      '',
    );

    await tester.enterText(houseField, '12');
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: weightsPanel, matching: find.text('H12')),
      findsWidgets,
    );
    expect(provider.activeChickWeightSample.houseNo, '12');
    expect(provider.activeChickWeightSample.houseLabel, 'House 12');
  });

  testWidgets(
    'house scope can remove the only active weight sample back to pool',
    (tester) async {
      final provider = AuditProvider(autosaveEnabled: false);
      await pumpScreen(tester, provider: provider);
      final weightsPanel = find.byKey(
        const ValueKey('chick-quality-panel-weights'),
      );

      await tester.ensureVisible(weightsPanel);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add house sample'));
      await tester.pumpAndSettle();

      expect(provider.isChickWeightCompareMode, isTrue);
      expect(
        provider.chickWeightSampleMode,
        StationSampleModel.sampleModeComparison,
      );
      expect(
        find.descendant(of: weightsPanel, matching: find.text('Pool')),
        findsNothing,
      );
      expect(find.byTooltip('Remove active house sample'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'House'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove active house sample'));
      await tester.pumpAndSettle();

      expect(provider.isChickWeightCompareMode, isFalse);
      expect(
        provider.chickWeightSampleMode,
        StationSampleModel.sampleModePooled,
      );
      expect(
        find.descendant(of: weightsPanel, matching: find.text('Pool')),
        findsOneWidget,
      );
      expect(find.byTooltip('Remove active house sample'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'House'), findsNothing);
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
    final provider = AuditProvider(autosaveEnabled: false);
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

  testWidgets('machine scope edits the active setter and hatcher numbers', (
    tester,
  ) async {
    final provider = AuditProvider(autosaveEnabled: false);
    await pumpScreen(tester, provider: provider);
    final machineScope = find.byKey(
      const ValueKey('chick-quality-machine-sampling'),
    );

    expect(find.text('Machine scope'), findsOneWidget);
    expect(find.text('Machine Samples'), findsNothing);
    expect(find.text('Compare setter and hatcher pairs'), findsNothing);
    expect(
      find.descendant(of: machineScope, matching: find.text('Pool')),
      findsOneWidget,
    );
    expect(find.text('S1H1'), findsNothing);
    expect(find.byTooltip('Add machine sample'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Setter'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Hatcher'), findsNothing);

    await tester.tap(find.byTooltip('Add machine sample'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: machineScope, matching: find.text('Pool')),
      findsNothing,
    );
    expect(find.text('S1H1'), findsNothing);
    expect(find.text('SH'), findsWidgets);
    expect(find.byTooltip('Remove active machine sample'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'House'), findsNothing);
    final setterField = find.widgetWithText(TextFormField, 'Setter');
    final hatcherField = find.widgetWithText(TextFormField, 'Hatcher');
    expect(setterField, findsOneWidget);
    expect(hatcherField, findsOneWidget);
    for (final label in ['Setter', 'Hatcher']) {
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: machineScope,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is TextField &&
                      widget.decoration?.labelText == label,
                ),
              ),
            )
            .controller
            ?.text,
        '',
      );
    }

    await tester.enterText(setterField, '7');
    await tester.enterText(hatcherField, '8');
    await tester.pumpAndSettle();

    expect(find.text('S7H8'), findsWidgets);
    expect(provider.activeStationSample.setterNo, '7');
    expect(provider.activeStationSample.hatcherNo, '8');
  });

  testWidgets('machine scope can remove the only active sample back to pool', (
    tester,
  ) async {
    final provider = AuditProvider(autosaveEnabled: false);
    await pumpScreen(tester, provider: provider);
    final machineScope = find.byKey(
      const ValueKey('chick-quality-machine-sampling'),
    );

    await tester.tap(find.byTooltip('Add machine sample'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: machineScope, matching: find.text('Pool')),
      findsNothing,
    );
    expect(find.byTooltip('Remove active machine sample'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Setter'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Hatcher'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove active machine sample'));
    await tester.pumpAndSettle();

    expect(provider.isCompareMode, isFalse);
    expect(provider.stationSampleMode, StationSampleModel.sampleModePooled);
    expect(
      find.descendant(of: machineScope, matching: find.text('Pool')),
      findsOneWidget,
    );
    expect(find.byTooltip('Remove active machine sample'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Setter'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Hatcher'), findsNothing);
  });

  testWidgets('machine scope fields stay aligned on phone widths', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(tester);

    await tester.tap(find.byTooltip('Add machine sample'));
    await tester.pumpAndSettle();

    expect(find.text('Machine scope'), findsOneWidget);
    final setterField = find.widgetWithText(TextFormField, 'Setter');
    final hatcherField = find.widgetWithText(TextFormField, 'Hatcher');

    expect(find.widgetWithText(TextFormField, 'House'), findsNothing);
    expect(setterField, findsOneWidget);
    expect(hatcherField, findsOneWidget);

    final setterRect = tester.getRect(setterField);
    final hatcherRect = tester.getRect(hatcherField);

    expect(hatcherRect.top, setterRect.top);
    expect(hatcherRect.width, closeTo(setterRect.width, 0.1));
    expect(hatcherRect.height, closeTo(setterRect.height, 0.1));
  });

  testWidgets('optional test cards follow the selected quality sample type', (
    tester,
  ) async {
    final provider = AuditProvider(autosaveEnabled: false);
    await pumpScreen(tester, provider: provider);

    expect(find.text('One shared sample'), findsNothing);
    expect(find.text('S1H1 setter/hatcher sample'), findsNothing);

    await tester.tap(find.byTooltip('Add machine sample'));
    await tester.pumpAndSettle();

    expect(find.text('SH setter/hatcher sample'), findsWidgets);

    await tester.tap(find.byTooltip('Add machine sample'));
    await tester.pumpAndSettle();

    expect(find.text('SH setter/hatcher sample'), findsWidgets);
  });

  testWidgets('does not render its own sticky save footer', (tester) async {
    await pumpScreen(tester);

    expect(find.byKey(const ValueKey('chick-quality-footer')), findsNothing);
    expect(find.text('Save Draft'), findsNothing);
    expect(find.text('Complete Station'), findsNothing);
  });
}
