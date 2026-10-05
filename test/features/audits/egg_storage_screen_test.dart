import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/data/models/panel_sampling_state.dart';
import 'package:hatchaudit/data/models/poultry_hierarchy_models.dart';
import 'package:hatchaudit/data/models/sampling_scope.dart';
import 'package:hatchaudit/data/repositories/panel_sampling_state_repository.dart';
import 'package:hatchaudit/data/repositories/poultry_hierarchy_repository.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/screens/audit_context_screen.dart';
import 'package:hatchaudit/features/audits/temperature_capture/temperature_capture_screen.dart';
import 'package:hatchaudit/features/audits/screens/egg_storage_screen.dart';
import 'package:hatchaudit/features/audits/widgets/photo_button.dart';
import 'package:hatchaudit/features/audits/widgets/sampling_scope_controls.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockSupabaseService extends Mock implements SupabaseService {}

class _RegisteredHouseRepository extends PoultryHierarchyRepository {
  @override
  Future<List<HouseModel>> listHouses(
    String flockId, {
    bool activeOnly = true,
  }) async => [
    HouseModel(
      id: 'house-1',
      flockId: flockId,
      name: 'North House',
      code: 'N01',
    ),
  ];
}

class _ScreenSamplingRepository extends PanelSamplingStateRepository {
  final Map<String, PanelSamplingState> _states = {};
  int _nextNodeId = 0;

  String _key(String sessionId, String panelKey) => '$sessionId:$panelKey';

  SamplingNode _sample({
    required String sessionId,
    required String panelKey,
    required int number,
    required String? parentId,
  }) => SamplingNode(
    id: 'sample-node-${++_nextNodeId}',
    sessionId: sessionId,
    panelKey: panelKey,
    parentId: parentId,
    level: SamplingScopeLevel.sample,
    identityKey: 'SA$number',
    identity: const {},
    sampleId: 'sample-$number',
    sampleNumber: number,
  );

  PanelSamplingState _state(
    String sessionId,
    String panelKey,
    List<SamplingNode> nodes, {
    required String activeSampleId,
    required int highWatermark,
  }) => PanelSamplingState(
    sessionId: sessionId,
    panelKey: panelKey,
    nodes: nodes,
    activeSampleId: activeSampleId,
    serialHighWatermark: highWatermark,
  );

  @override
  Future<PanelSamplingState> loadOrCreateDefault({
    required String sessionId,
    required String panelKey,
  }) async {
    return _states.putIfAbsent(_key(sessionId, panelKey), () {
      final sample = _sample(
        sessionId: sessionId,
        panelKey: panelKey,
        number: 1,
        parentId: null,
      );
      return _state(
        sessionId,
        panelKey,
        [sample],
        activeSampleId: sample.sampleId!,
        highWatermark: 1,
      );
    });
  }

  @override
  Future<SamplingNode> addScopeIdentity({
    required String sessionId,
    required String panelKey,
    required String? parentId,
    required SamplingScopeLevel level,
    required Map<String, String> identity,
    bool discardPooledData = false,
  }) async {
    final key = _key(sessionId, panelKey);
    final current = await loadOrCreateDefault(
      sessionId: sessionId,
      panelKey: panelKey,
    );
    if (current.hasIdentityUnderParent(
      parentId: parentId,
      level: level,
      identity: identity,
    )) {
      throw StateError('That identity already exists under this parent.');
    }
    final node = SamplingNode(
      id: 'scope-node-${++_nextNodeId}',
      sessionId: sessionId,
      panelKey: panelKey,
      parentId: parentId,
      level: level,
      identityKey: identity['code'],
      identity: identity,
    );
    final nodes = current.nodes
        .where(
          (item) =>
              !(item.parentId == parentId &&
                  item.level == SamplingScopeLevel.sample &&
                  item.identity.isEmpty),
        )
        .toList();
    _states[key] = _state(
      sessionId,
      panelKey,
      [...nodes, node],
      activeSampleId: '',
      highWatermark: current.serialHighWatermark,
    );
    return node;
  }

  @override
  Future<SamplingNode> addTerminalSample({
    required String sessionId,
    required String panelKey,
    required String? parentId,
    Map<String, String>? identity,
  }) async {
    final key = _key(sessionId, panelKey);
    final current = await loadOrCreateDefault(
      sessionId: sessionId,
      panelKey: panelKey,
    );
    final number = current.serialHighWatermark + 1;
    final sample = _sample(
      sessionId: sessionId,
      panelKey: panelKey,
      number: number,
      parentId: parentId,
    );
    _states[key] = _state(
      sessionId,
      panelKey,
      [...current.nodes, sample],
      activeSampleId: sample.sampleId!,
      highWatermark: number,
    );
    return sample;
  }

  @override
  Future<void> updateScopeIdentity({
    required String nodeId,
    required Map<String, String> identity,
  }) async {
    for (final entry in _states.entries) {
      final current = entry.value;
      final index = current.nodes.indexWhere((node) => node.id == nodeId);
      if (index < 0) continue;
      final nodes = [...current.nodes];
      nodes[index] = nodes[index].copyWith(
        identity: identity,
        identityKey: identity['code'],
      );
      _states[entry.key] = _state(
        current.sessionId,
        current.panelKey,
        nodes,
        activeSampleId: current.activeSampleId,
        highWatermark: current.serialHighWatermark,
      );
      return;
    }
  }

  @override
  Future<SamplingDeletePreview> previewDeleteSubtree({
    required String nodeId,
  }) async => SamplingDeletePreview(
    nodeId: nodeId,
    scopeLabel: 'North House',
    descendantCount: 1,
    measurementCount: 1,
    photoCount: 2,
    noteCount: 1,
  );

  @override
  Future<void> deleteSubtree({required String nodeId}) async {
    for (final entry in _states.entries) {
      final current = entry.value;
      if (!current.nodes.any((node) => node.id == nodeId)) continue;
      final removed = <String>{nodeId};
      var changed = true;
      while (changed) {
        changed = false;
        for (final node in current.nodes) {
          if (node.parentId != null &&
              removed.contains(node.parentId) &&
              removed.add(node.id)) {
            changed = true;
          }
        }
      }
      var nodes = current.nodes
          .where((node) => !removed.contains(node.id))
          .toList();
      var highWatermark = current.serialHighWatermark;
      if (!nodes.any((node) => node.sampleId != null)) {
        final sample = _sample(
          sessionId: current.sessionId,
          panelKey: current.panelKey,
          number: ++highWatermark,
          parentId: null,
        );
        nodes = [...nodes, sample];
      }
      final active = nodes.firstWhere((node) => node.sampleId != null);
      _states[entry.key] = _state(
        current.sessionId,
        current.panelKey,
        nodes,
        activeSampleId: active.sampleId!,
        highWatermark: highWatermark,
      );
      return;
    }
  }
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
    final samplingRepository = _ScreenSamplingRepository();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AuditProvider(
              autosaveEnabled: false,
              panelSamplingStateRepository: samplingRepository,
            ),
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

  Future<(AuditProvider, _ScreenSamplingRepository)> pumpSamplingControls(
    WidgetTester tester, {
    required String panelKey,
  }) async {
    final repository = _ScreenSamplingRepository();
    final provider =
        AuditProvider(
          autosaveEnabled: false,
          panelSamplingStateRepository: repository,
        )..initialize(
          AuditContext(
            auditType: 'Egg',
            customerId: 'customer-1',
            flockId: 'flock-1',
            hatcheryId: 'hatchery-1',
            breed: 'Ross 308',
            date: '2026-04-27',
          ),
          sessionId: 'session-1',
          notify: false,
        );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(create: (_) => CustomersProvider()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SamplingScopeControls(
                panelKey: panelKey,
                houseRepository: _RegisteredHouseRepository(),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return (provider, repository);
  }

  Future<void> chooseRegisteredNorthHouse(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Add House'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(
      find.byWidgetPredicate((widget) => widget is DropdownButtonFormField),
    );
    await tester.pump();
    await tester.tap(find.text('North House').last);
    await tester.pump();
    await tester.tap(find.text('Save').last);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
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

    expect(find.byType(SamplingScopeControls), findsNWidgets(2));
    expect(find.byType(SegmentedButton<bool>), findsNothing);
    expect(
      find.byKey(const ValueKey('egg-sample-mode-icon-single')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('egg-sample-mode-icon-multiple')),
      findsNothing,
    );
    expect(find.byTooltip('Add House'), findsNothing);
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

    expect(find.byType(SamplingScopeControls), findsNWidgets(2));

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

  testWidgets('egg quality uses registered House identities for samples', (
    tester,
  ) async {
    final (provider, repository) = await pumpSamplingControls(
      tester,
      panelKey: 'egg_quality',
    );

    await chooseRegisteredNorthHouse(tester);

    final house = repository._states.values
        .expand((state) => state.nodes)
        .singleWhere((node) => node.level == SamplingScopeLevel.house);
    expect(house.identity['id'], 'house-1');
    expect(house.identity['code'], 'N01');
    expect(house.identity['name'], 'North House');
    expect(find.text('North House'), findsOneWidget);
    expect(find.textContaining('HN01'), findsOneWidget);
    expect(repository._states.values.single.samples, hasLength(1));

    expect(provider.samplingStateFor('egg_quality')?.samples, hasLength(1));
    provider.dispose();
  });

  testWidgets('registered House picker cancellation and duplicate are safe', (
    tester,
  ) async {
    final (provider, repository) = await pumpSamplingControls(
      tester,
      panelKey: 'egg_quality',
    );

    await tester.tap(find.byTooltip('Add House'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.text('Cancel').last);
    await tester.pump();
    expect(repository._states.values.single.samples, hasLength(1));

    await chooseRegisteredNorthHouse(tester);
    await tester.tap(find.byTooltip('Add House'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(
      find.byWidgetPredicate((widget) => widget is DropdownButtonFormField),
    );
    await tester.pump();
    await tester.tap(find.text('North House').last);
    await tester.pump();
    await tester.tap(find.text('Save').last);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      find.text('That identity already exists under this parent.'),
      findsOneWidget,
    );
    expect(
      repository._states.values.single.nodes.where(
        (node) => node.level == SamplingScopeLevel.house,
      ),
      hasLength(1),
    );
    provider.dispose();
  });

  testWidgets('measured Pooled egg quality requires explicit reset', (
    tester,
  ) async {
    final (provider, repository) = await pumpSamplingControls(
      tester,
      panelKey: 'egg_quality',
    );
    provider.updateField('esEggSampleSize', 30);
    await tester.pump();

    await chooseRegisteredNorthHouse(tester);
    expect(find.text('Reset Pooled sample?'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pump();
    expect(repository._states.values.single.samples, hasLength(1));
    expect(
      repository._states.values.single.nodes.where(
        (node) => node.level == SamplingScopeLevel.house,
      ),
      isEmpty,
    );

    await chooseRegisteredNorthHouse(tester);
    expect(find.text('Reset Pooled sample?'), findsOneWidget);
    await tester.tap(find.text('Delete and continue'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(repository._states.values.single.samples, hasLength(1));
    expect(
      repository._states.values.single.nodes.where(
        (node) => node.level == SamplingScopeLevel.house,
      ),
      hasLength(1),
    );
    provider.dispose();
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

  testWidgets('removing a registered House requires delete confirmation', (
    tester,
  ) async {
    final (provider, repository) = await pumpSamplingControls(
      tester,
      panelKey: 'egg_quality',
    );
    await chooseRegisteredNorthHouse(tester);

    final removeHouse = find.byTooltip('Remove North House');
    expect(removeHouse, findsOneWidget);
    await tester.tap(removeHouse);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Delete North House?'), findsOneWidget);
    expect(
      find.textContaining('1 branches, 1 measurements, 2 photos, and 1 notes'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel').last);
    await tester.pump();
    expect(
      repository._states.values.single.nodes.where(
        (node) => node.level == SamplingScopeLevel.house,
      ),
      hasLength(1),
    );

    await tester.tap(removeHouse);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.text('Delete').last);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      repository._states.values.single.nodes.where(
        (node) => node.level == SamplingScopeLevel.house,
      ),
      isEmpty,
    );
    expect(repository._states.values.single.samples, hasLength(1));
    expect(provider.samplingStateFor('egg_quality')?.samples, hasLength(1));
    provider.dispose();
  });
}
