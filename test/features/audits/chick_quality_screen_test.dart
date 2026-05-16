import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/data/repositories/audit_repository.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/screens/audit_context_screen.dart';
import 'package:hatchaudit/features/audits/screens/chick_quality_screen.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/providers/app_provider.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
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

    await tester.tap(find.text('Enter YFBM Entries'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('yfbm-entries-sheet')), findsOneWidget);
    expect(find.text('YFBM Entries'), findsOneWidget);
    expect(find.text('0 of 10 rows complete'), findsOneWidget);
    expect(find.text('Target 8-10%'), findsOneWidget);

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

  testWidgets('CVT uses an EST-style grid with target and unit controls', (
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

    expect(find.text('Guided CVT capture'), findsOneWidget);
    expect(find.text('103-105°F / 39.4-40.6°C'), findsOneWidget);
    expect(find.byKey(const ValueKey('cvt-temperature-grid')), findsOneWidget);
    expect(find.byKey(const ValueKey('cvt-unit-toggle')), findsOneWidget);
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
  });

  testWidgets('PM Necropsy shows the revised lesion checklist', (tester) async {
    await pumpScreen(tester);

    await tester.ensureVisible(
      find.byKey(const ValueKey('chick-quality-panel-pm')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('PM Necropsy'));
    await tester.pumpAndSettle();

    expect(find.text('Omphalitis (Yolk Sacculitis)'), findsOneWidget);
    expect(find.text('Gaseous Ceca'), findsOneWidget);
    expect(find.text('Gizzard Erosions'), findsOneWidget);
    expect(find.text('Air Sac Caseations'), findsOneWidget);
    expect(find.text('Nephritis'), findsOneWidget);
    expect(find.text('General Septicemia'), findsOneWidget);

    expect(find.text('Unabsorbed Yolk'), findsNothing);
    expect(find.text('Perihepatitis'), findsNothing);
    expect(find.text('Pericarditis'), findsNothing);
    expect(find.text('Airsac Acute'), findsNothing);
    expect(find.text('Airsac Chronic'), findsNothing);
    expect(find.text('Pulmonary Hemorrhage'), findsNothing);
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
    expect(find.text('Quality sampling'), findsOneWidget);
    expect(find.text('Machine ID'), findsOneWidget);
    expect(find.text('Active machine'), findsNothing);
    expect(find.text('Setter and hatcher pair'), findsNothing);
    expect(find.text('One sample'), findsWidgets);
    expect(find.text('Multisamples'), findsWidgets);
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
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('quality-scope-segment-multiple')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('chick-quality-panel-weights')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sample Mode'), findsNothing);
    expect(find.text('Chick Sample Mode'), findsNothing);
    expect(find.text('House scope'), findsOneWidget);
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
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('house-scope-segment-multiple')),
      findsOneWidget,
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

    final modeTop = tester.getTopLeft(find.text('House scope')).dy;
    final panelTop = tester
        .getTopLeft(find.byKey(const ValueKey('chick-quality-panel-weights')))
        .dy;
    expect(modeTop, greaterThan(panelTop));
  });

  testWidgets(
    'weight comparison mode shows house chips and add/remove controls',
    (tester) async {
      await pumpScreen(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('chick-quality-panel-weights')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('chick-quality-panel-weights')),
          matching: find.text('Multisamples'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('House Samples'), findsOneWidget);
      expect(find.text('H1'), findsWidgets);
      expect(find.text('Label'), findsNothing);
      expect(find.byTooltip('Add house sample'), findsOneWidget);
      expect(find.byTooltip('Remove active house sample'), findsNothing);

      await tester.tap(find.byTooltip('Add house sample'));
      await tester.pumpAndSettle();

      expect(find.text('H2'), findsWidgets);
      expect(find.byTooltip('Remove active house sample'), findsOneWidget);
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

  testWidgets('quality multisamples use setter and hatcher chip labels', (
    tester,
  ) async {
    final provider = AuditProvider(autosaveEnabled: false);
    await pumpScreen(tester, provider: provider);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('chick-quality-machine-sampling')),
        matching: find.text('Multisamples'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Machine Samples'), findsNothing);
    expect(find.text('Compare setter and hatcher pairs'), findsNothing);
    expect(find.text('S1H1'), findsWidgets);
    expect(find.byTooltip('Add machine sample'), findsOneWidget);

    await tester.tap(find.byTooltip('Add machine sample'));
    await tester.pumpAndSettle();

    expect(find.text('S2H2'), findsWidgets);
  });

  testWidgets('active machine fields stay aligned on phone widths', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(tester);

    final setterField = find.widgetWithText(TextFormField, 'Setter');
    final hatcherField = find.widgetWithText(TextFormField, 'Hatcher');

    expect(setterField, findsOneWidget);
    expect(hatcherField, findsOneWidget);

    final setterRect = tester.getRect(setterField);
    final hatcherRect = tester.getRect(hatcherField);

    expect(hatcherRect.top, setterRect.top);
    expect(hatcherRect.width, setterRect.width);
    expect(hatcherRect.height, setterRect.height);
  });

  testWidgets('optional test cards follow the selected quality sample type', (
    tester,
  ) async {
    final provider = AuditProvider(autosaveEnabled: false);
    await pumpScreen(tester, provider: provider);

    expect(find.text('One shared sample'), findsNothing);
    expect(find.text('S1H1 setter/hatcher sample'), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('chick-quality-machine-sampling')),
        matching: find.text('Multisamples'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('S1H1 setter/hatcher sample'), findsWidgets);

    await tester.tap(find.byTooltip('Add machine sample'));
    await tester.pumpAndSettle();

    expect(find.text('S2H2 setter/hatcher sample'), findsWidgets);
    expect(find.text('S1H1 setter/hatcher sample'), findsNothing);
  });

  testWidgets('does not render its own sticky save footer', (tester) async {
    await pumpScreen(tester);

    expect(find.byKey(const ValueKey('chick-quality-footer')), findsNothing);
    expect(find.text('Save Draft'), findsNothing);
    expect(find.text('Complete Station'), findsNothing);
  });
}
