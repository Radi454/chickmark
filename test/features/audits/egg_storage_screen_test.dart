import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
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

  AuditContextData contextData() => AuditContextData(
    auditType: 'Egg',
    customerId: 'customer-1',
    flockId: 'flock-1',
    breed: 'Ross 308',
    flockAgeWeeks: 42,
    date: '2026-04-27',
  );

  Future<void> pumpScreen(WidgetTester tester) async {
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
        child: MaterialApp(home: EggStorageScreen(context: contextData())),
      ),
    );
    await tester.pump();
  }

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

    expect(find.text('Sampling scope'), findsOneWidget);
    expect(find.text('Record one house or compare houses'), findsNothing);
    expect(find.text('One sample'), findsOneWidget);
    expect(find.text('1 sample'), findsNothing);
    expect(find.text('Multiple samples'), findsOneWidget);
    expect(find.byType(SegmentedButton<bool>), findsNothing);
    expect(
      find.byKey(const ValueKey('egg-sample-mode-icon-single')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('egg-sample-mode-icon-multiple')),
      findsNothing,
    );
    expect(find.text('UV torch inspection by tray'), findsNothing);
    expect(find.text('Optional station comments'), findsNothing);

    await tester.tap(find.text('Egg Shell Temperature'));
    await tester.pumpAndSettle();

    expect(find.text('19.0-21.0°C'), findsOneWidget);
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

    final multiHouseChip = find.byKey(
      const ValueKey('egg-sample-mode-segment-multiple'),
    );
    await tester.ensureVisible(multiHouseChip);
    await tester.pump();
    await tester.tap(multiHouseChip);
    await tester.pumpAndSettle();

    expect(find.text('House Samples'), findsNothing);
    expect(find.text('Same flock, compare egg quality by house'), findsNothing);
    expect(find.text('Egg Weights & Uniformity'), findsOneWidget);
    expect(find.text('EW'), findsNothing);
    expect(find.byKey(const ValueKey('egg-workbench-mark-EW')), findsNothing);
    expect(find.text('0/100'), findsNothing);
    expect(find.byTooltip('Add house sample'), findsNothing);

    await tester.tap(find.text('Egg Weights & Uniformity'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Add house sample'), findsOneWidget);

    await tester.tap(find.byTooltip('Add house sample'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add house sample'));
    await tester.pumpAndSettle();

    final h3 = find.widgetWithText(ChoiceChip, 'H3');
    final addHouse = find.byTooltip('Add house sample');
    final removeHouse = find.byTooltip('Remove active house sample');

    expect(h3, findsOneWidget);
    expect(removeHouse, findsOneWidget);
    expect(tester.getCenter(addHouse).dx, greaterThan(tester.getCenter(h3).dx));
    expect(
      tester.getCenter(removeHouse).dx,
      greaterThan(tester.getCenter(addHouse).dx),
    );
    expect(tester.getTopLeft(addHouse).dy, tester.getTopLeft(removeHouse).dy);

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

    expect(find.text('Add UV Tray'), findsOneWidget);

    expect(storageDaysField, findsOneWidget);
    await tester.ensureVisible(storageDaysField);
    await tester.pump();
    expect(tester.widget<TextField>(storageDaysField).controller?.text, '0');

    await tester.tap(storageDaysField);
    await tester.pump();

    expect(tester.widget<TextField>(storageDaysField).controller?.text, '');
  });

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
}
