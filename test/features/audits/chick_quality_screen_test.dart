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
        auditType: 'Chick Quality',
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

  AuditContextData contextData() => AuditContextData(
    auditType: 'Chick Quality',
    customerId: 'customer-1',
    flockId: 'flock-1',
    date: '2026-04-27',
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    AuditProvider? provider,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuditProvider>(
            create: (_) => provider ?? AuditProvider(),
          ),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: MockSupabaseService()),
          ),
          ChangeNotifierProvider(create: (_) => AppProvider()),
        ],
        child: MaterialApp(home: ChickQualityScreen(context: contextData())),
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
    expect(find.text('Chick Quality'), findsWidgets);
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

  testWidgets('YFBM entries are edited from a modal entry sheet', (
    tester,
  ) async {
    final provider = AuditProvider();
    await pumpScreen(tester, provider: provider);

    await tester.ensureVisible(
      find.byKey(const ValueKey('chick-quality-panel-yfbm')),
    );
    await tester.pumpAndSettle();

    expect(find.text('YFBM Entries'), findsNothing);
    expect(find.text('Enter YFBM Entries'), findsOneWidget);

    await tester.tap(find.text('Enter YFBM Entries'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('yfbm-entries-sheet')), findsOneWidget);
    expect(find.text('YFBM Entries'), findsOneWidget);

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
    final provider = AuditProvider();
    await pumpScreen(tester, provider: provider);

    await tester.ensureVisible(
      find.byKey(const ValueKey('chick-quality-panel-cvt')),
    );
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

  testWidgets('keeps sample controls inside the chick weights panel', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.ensureVisible(
      find.byKey(const ValueKey('chick-quality-panel-weights')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sample Mode'), findsNothing);
    expect(find.text('Chick Sample Mode'), findsOneWidget);
    expect(find.text('Single Sample'), findsOneWidget);
    expect(find.text('Multi House Samples'), findsOneWidget);

    final modeTop = tester.getTopLeft(find.text('Chick Sample Mode')).dy;
    final panelTop = tester
        .getTopLeft(find.byKey(const ValueKey('chick-quality-panel-weights')))
        .dy;
    expect(modeTop, greaterThan(panelTop));
  });

  testWidgets(
    'comparison mode shows house chips and add/remove controls in weights panel',
    (tester) async {
      await pumpScreen(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('chick-quality-panel-weights')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Multi House Samples'));
      await tester.pumpAndSettle();

      expect(find.text('House Samples'), findsOneWidget);
      expect(find.text('Sample 1'), findsOneWidget);
      expect(find.byTooltip('Add sample'), findsOneWidget);
      expect(find.byTooltip('Remove active sample'), findsOneWidget);

      await tester.tap(find.byTooltip('Add sample'));
      await tester.pumpAndSettle();

      expect(find.text('Sample 2'), findsOneWidget);
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
  });

  testWidgets('renders footer save actions', (tester) async {
    await pumpScreen(tester);

    expect(find.byKey(const ValueKey('chick-quality-footer')), findsOneWidget);
    expect(find.text('Save Draft'), findsOneWidget);
    expect(find.text('Complete Station'), findsOneWidget);
    expect(
      find.text('Unsaved changes in this chick quality station.'),
      findsOneWidget,
    );
  });

  testWidgets('Save Draft uses the existing provider save flow', (
    tester,
  ) async {
    final auditRepository = MockAuditRepository();
    final supabaseService = MockSupabaseService();
    when(
      () => auditRepository.getAuditById(any()),
    ).thenAnswer((_) async => null);
    when(() => auditRepository.insertAudit(any())).thenAnswer((_) async {});
    when(() => supabaseService.syncAudit(any())).thenAnswer((_) async {});

    final provider = AuditProvider(
      repository: auditRepository,
      supabaseService: supabaseService,
    );
    await pumpScreen(tester, provider: provider);
    provider.updateField('pasgarFinalScore', 25.0);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save Draft'));
    await tester.pumpAndSettle();

    verify(() => auditRepository.insertAudit(any())).called(1);
    expect(provider.isDirty, isFalse);
  });
}
