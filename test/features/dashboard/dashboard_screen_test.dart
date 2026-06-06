import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/features/audits/models/culled_chicks_analysis.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/features/dashboard/models/chick_quality_models.dart';
import 'package:hatchaudit/features/dashboard/models/egg_storage_models.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';
import 'package:hatchaudit/features/dashboard/providers/scope_comparison_provider.dart';
import 'package:hatchaudit/features/dashboard/screens/dashboard_screen.dart';
import 'package:hatchaudit/features/dashboard/widgets/sections/stub_sections.dart';
import 'package:hatchaudit/providers/app_provider.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockSupabaseService extends Mock implements SupabaseService {}

class _StaticDashboardProvider extends DashboardProvider {
  final List<CustomerModel> _testCustomers;
  final EggStorageTrend? _testEggStorageLatest;
  final EggStorageEstEvidence? _testEggStorageEvidence;
  final CulledChicksAnalysisAvg? _testCulledChicksAnalysis;

  _StaticDashboardProvider({
    required List<CustomerModel> customers,
    EggStorageTrend? eggStorageLatest,
    EggStorageEstEvidence? eggStorageEvidence,
    CulledChicksAnalysisAvg? culledChicksAnalysis,
  }) : _testCustomers = customers,
       _testEggStorageLatest = eggStorageLatest,
       _testEggStorageEvidence = eggStorageEvidence,
       _testCulledChicksAnalysis = culledChicksAnalysis;

  @override
  List<CustomerModel> get customers => _testCustomers;

  @override
  bool get isLoading => false;

  @override
  bool get isLoadingGoveeCaptures => false;

  @override
  List<EggStorageTrend> get eggStorageTrend =>
      _testEggStorageLatest == null ? const [] : [_testEggStorageLatest];

  @override
  EggStorageTrend? get eggStorageLatest => _testEggStorageLatest;

  @override
  EggStorageEstEvidence? get eggStorageEstEvidence => _testEggStorageEvidence;

  @override
  CulledChicksAnalysisAvg? get culledChicksAnalysis =>
      _testCulledChicksAnalysis;

  @override
  Future<void> init({UserModel? currentUser}) async {}
}

void main() {
  testWidgets('dashboard renders Govee and Scopes sections (egg via scope only)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppProvider()),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(
              supabaseService: _MockSupabaseService(),
              bypassAuth: true,
            ),
          ),
          ChangeNotifierProvider(create: (_) => ScopeComparisonProvider()),
          ChangeNotifierProvider<DashboardProvider>(
            create: (_) => _StaticDashboardProvider(
              customers: [
                CustomerModel(
                  id: 'customer-1',
                  name: 'Customer 1',
                  createdAt: DateTime(2026, 5, 1),
                  createdBy: 'test',
                ),
              ],
            ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: const DashboardScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Dashboard'), findsOneWidget);
    // Legacy bespoke egg cards must NOT render on the dashboard — egg is shown
    // by the Scopes section only, so each sector appears exactly once.
    expect(find.byType(EggStorageSection, skipOffstage: false), findsNothing);
    expect(find.byType(EggQualitySection, skipOffstage: false), findsNothing);
    expect(find.byType(ChickQualitySection, skipOffstage: false), findsNothing);
    expect(find.text('21-Day Hatch Residue Breakout'), findsNothing);
    expect(find.text('Visit Sessions'), findsNothing);

    // The Scopes & Parameters section renders, grouped by station. The section
    // header band was removed; the station cards are the render guard now.
    // Egg Storage & Handling is a single scope station card (no duplicate from
    // the old legacy section) — the regression guard for repeated sectors.
    expect(
      find.text('Egg Storage & Handling', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('Chicks', skipOffstage: false), findsWidgets);
    expect(
      find.text('Hatch Analysis & Egg Breakouts', skipOffstage: false),
      findsWidgets,
    );
    expect(find.text('Setters', skipOffstage: false), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Govee Environmental Readings'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Govee Environmental Readings'), findsWidgets);
  });

  testWidgets('dashboard mobile layout avoids filter and egg card overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppProvider()),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(
              supabaseService: _MockSupabaseService(),
              bypassAuth: true,
            ),
          ),
          ChangeNotifierProvider(create: (_) => ScopeComparisonProvider()),
          ChangeNotifierProvider<DashboardProvider>(
            create: (_) => _StaticDashboardProvider(
              customers: [
                CustomerModel(
                  id: 'customer-1',
                  name: 'Demo Customer',
                  createdAt: DateTime(2026, 5, 1),
                  createdBy: 'test',
                ),
              ],
              eggStorageLatest: EggStorageTrend.fromMap(const {
                'date': '2026-05-18',
                'shellTempC': 27.1,
                'estAvgF': 27.1,
                'estCvPct': 8.8,
                'storageDays': 2,
                'turningTimes': 1,
                'traySpacing': 'Tight',
                'coolerProximity': 'Far',
                'condensationPresent': 1,
                'upsideDownCount': 4,
                'upsideDownPct': 2.7,
              }),
              eggStorageEvidence: EggStorageEstEvidence.fromJsonStrings(
                readingsJson:
                    '{"front_top":27.8,"middle_top":27.4,"back_top":28.7,"front_middle":28.5,"middle_middle":23.0,"back_middle":23.0,"front_bottom":28.7,"middle_bottom":29.0,"back_bottom":27.4}',
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: const DashboardScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(ChickQualitySection, skipOffstage: false), findsNothing);

    await tester.pumpAndSettle();
    // Target the vertical body list explicitly — a horizontal filter strip is
    // also a ListView, so a bare byType(ListView) finder is ambiguous.
    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('egg dashboard sector renders evidence-first EST alarm layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<DashboardProvider>(
        create: (_) => _StaticDashboardProvider(
          customers: const [],
          eggStorageLatest: EggStorageTrend.fromMap(const {
            'date': '2026-05-18',
            'shellTempC': 27.1,
            'estAvgF': 27.1,
            'estCvPct': 8.8,
            'storageDays': 6,
            'turningTimes': 4,
            'traySpacing': 'Adequate',
            'coolerProximity': 'Far',
            'condensationPresent': 0,
            'upsideDownCount': 12,
            'upsideDownPct': 4.0,
          }),
          eggStorageEvidence: EggStorageEstEvidence.fromJsonStrings(
            readingsJson:
                '{"front_top":28.7,"middle_top":28.5,"back_top":27.8,"front_middle":29.0,"middle_middle":23.0,"back_middle":27.4,"front_bottom":28.7,"middle_bottom":23.0,"back_bottom":27.4}',
            photosJson:
                '{"front_top":"/missing/front-top.jpg","middle_top":"/missing/middle-top.jpg"}',
          ),
        ),
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: EggStorageSection()),
          ),
        ),
      ),
    );

    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Egg Storage & Handling'), findsOneWidget);
    expect(find.text('Temperature Readings (°C)'), findsOneWidget);
    expect(find.text('Average'), findsOneWidget);
    expect(find.text('27.1°C'), findsOneWidget);
    expect(find.text('High vs target'), findsOneWidget);
    expect(find.text('Target'), findsOneWidget);
    expect(find.text('18-20°C'), findsOneWidget);
    expect(find.text('Medium storage'), findsWidgets);
    expect(find.text('CV%'), findsOneWidget);
    expect(find.text('8.8%'), findsOneWidget);
    expect(find.text('Limit <= 8.0%'), findsOneWidget);
    expect(find.text('Alarm'), findsOneWidget);
    expect(find.textContaining('Average is above target'), findsOneWidget);
    expect(find.text('Upside Down Egg'), findsOneWidget);
    expect(find.text('12 eggs'), findsOneWidget);
    expect(find.text('4.0%'), findsOneWidget);
    expect(find.text('Storage Checklist Metadata'), findsNothing);
    expect(find.text('Storage Checklist'), findsNothing);
    expect(find.text('Handling Metadata'), findsNothing);
    expect(find.text('Storage Info'), findsOneWidget);
    expect(find.text('Storage'), findsOneWidget);
    expect(find.text('6 days'), findsOneWidget);
    expect(find.text('Turning'), findsOneWidget);
    expect(find.text('4 times'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Recorded'), findsOneWidget);
    expect(find.text('Tray spacing'), findsOneWidget);
    expect(find.text('Adequate'), findsOneWidget);
    expect(find.text('Cooler'), findsOneWidget);
    expect(find.text('Far'), findsOneWidget);
    expect(find.text('Condensation'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
    expect(find.text('Uniformity'), findsNothing);
    expect(find.text('UV'), findsNothing);
    expect(find.text('CO₂'), findsNothing);

    final decorationColors = _boxDecorationColors(tester).toList();
    expect(decorationColors, contains(AppColors.statusErrorBg));
    expect(decorationColors, isNot(contains(AppColors.statusWarningBg)));
    expect(
      decorationColors,
      isNot(contains(AppColors.statusWarning.withValues(alpha: 0.14))),
    );
    final photoIcons = tester.widgetList<Icon>(
      find.byIcon(Icons.add_photo_alternate_outlined),
    );
    expect(
      photoIcons.where((icon) => icon.color == AppColors.statusWarning),
      isEmpty,
    );
  });

  testWidgets('egg quality dashboard sector renders weights and UV alarms', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<DashboardProvider>(
        create: (_) => _StaticDashboardProvider(
          customers: const [],
          eggStorageLatest: EggStorageTrend.fromMap(const {
            'date': '2026-05-18',
            'avgWeightG': 62.0,
            'uniformityPct': 82.0,
            'cvPct': 8.4,
            'eggSampleSize': 86,
            'eggBmkWeight': 63.0,
            'uvCuticleDamagePct': 2.0,
            'uvWashedPct': 3.0,
            'uvDirtyPct': 2.0,
            'uvAffectedPct': 7.0,
          }),
        ),
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: EggQualitySection()),
          ),
        ),
      ),
    );

    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Egg Quality'), findsOneWidget);
    expect(find.text('Egg Weights & Uniformity'), findsOneWidget);
    expect(find.text('Average'), findsOneWidget);
    expect(find.text('62.0g'), findsOneWidget);
    expect(find.text('Uniformity'), findsOneWidget);
    expect(find.text('82.0%'), findsOneWidget);
    expect(find.text('C.V'), findsOneWidget);
    expect(find.text('8.4%'), findsOneWidget);
    expect(find.text('Limit <= 8.0%'), findsOneWidget);
    expect(find.text('Alarm'), findsWidgets);
    expect(find.textContaining('C.V is above'), findsOneWidget);
    expect(find.text('Sample Size'), findsOneWidget);
    expect(find.text('86/100'), findsOneWidget);
    expect(find.text('BMK Egg Weight'), findsOneWidget);
    expect(find.text('63.0g'), findsOneWidget);
    expect(find.text('Low Margin'), findsOneWidget);
    expect(find.text('55.8g'), findsOneWidget);
    expect(find.text('High Margin'), findsOneWidget);
    expect(find.text('68.2g'), findsOneWidget);
    expect(find.text('Shell Quality UV'), findsOneWidget);
    expect(find.text('Affected'), findsOneWidget);
    expect(find.text('7.0%'), findsOneWidget);
    expect(find.text('Target'), findsOneWidget);
    expect(find.text('<= 5.0%'), findsOneWidget);
    expect(find.textContaining('UV affected is above'), findsOneWidget);
    expect(find.text('Cuticle Damage'), findsOneWidget);
    expect(find.text('Washed'), findsOneWidget);
    expect(find.text('Dirty'), findsOneWidget);
  });

  testWidgets('chick dashboard sector renders culled analysis interpretation', (
    tester,
  ) async {
    final summary = CulledChicksAnalysisSummary.fromJson(
      CulledChicksAnalysisCodec.encodeCounts({
        'navel_open_unhealed': 4,
        'sticky_dehydrated_burned_chick': 1,
      }, totalEggSet: 19200),
      totalEggSet: 19200,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<DashboardProvider>(
        create: (_) => _StaticDashboardProvider(
          customers: const [],
          culledChicksAnalysis: CulledChicksAnalysisAvg.fromSummary(summary),
        ),
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: const Scaffold(body: ChickQualitySection()),
        ),
      ),
    );

    await tester.tap(find.text('Culled'));
    await tester.pumpAndSettle();

    expect(find.text('Culled Chicks Analysis'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Open / unhealed navel'), findsOneWidget);
    expect(find.textContaining('High eggshell temperature'), findsOneWidget);
  });
}

Iterable<Color> _boxDecorationColors(WidgetTester tester) sync* {
  for (final container in tester.widgetList<Container>(
    find.byType(Container),
  )) {
    final decoration = container.decoration;
    if (decoration is BoxDecoration && decoration.color != null) {
      yield decoration.color!;
    }
  }
  for (final decoratedBox in tester.widgetList<DecoratedBox>(
    find.byType(DecoratedBox),
  )) {
    final decoration = decoratedBox.decoration;
    if (decoration is BoxDecoration && decoration.color != null) {
      yield decoration.color!;
    }
  }
}
