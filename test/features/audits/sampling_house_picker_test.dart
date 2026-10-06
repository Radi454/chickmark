import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/poultry_hierarchy_models.dart';
import 'package:hatchaudit/data/models/sampling_scope.dart';
import 'package:hatchaudit/data/repositories/poultry_hierarchy_repository.dart';
import 'package:hatchaudit/data/models/panel_sampling_state.dart';
import 'package:hatchaudit/data/repositories/panel_sampling_state_repository.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/widgets/sampling_scope_controls.dart';
import 'package:provider/provider.dart';

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

class _EmptyHouseRepository extends PoultryHierarchyRepository {
  @override
  Future<List<HouseModel>> listHouses(
    String flockId, {
    bool activeOnly = true,
  }) async => const [];
}

class _EditableHouseRepository extends PoultryHierarchyRepository {
  _EditableHouseRepository([Iterable<HouseModel> initial = const []])
    : houses = [...initial];

  final List<HouseModel> houses;
  final List<HouseModel> saved = [];
  final requestedFlocks = <String>[];

  @override
  Future<List<HouseModel>> listHouses(
    String flockId, {
    bool activeOnly = true,
  }) async {
    requestedFlocks.add(flockId);
    return houses
        .where(
          (house) =>
              house.flockId == flockId && (!activeOnly || house.isActive),
        )
        .toList();
  }

  @override
  Future<void> saveHouse(HouseModel house) async {
    saved.add(house);
    houses.removeWhere((existing) => existing.id == house.id);
    houses.add(house);
  }
}

class _PickerSamplingRepository extends PanelSamplingStateRepository {
  PanelSamplingState state = PanelSamplingState(
    sessionId: 'session-1',
    panelKey: 'egg_quality',
    serialHighWatermark: 1,
    activeSampleId: 'sample-1',
    nodes: [
      SamplingNode(
        id: 'sample-node-1',
        sessionId: 'session-1',
        panelKey: 'egg_quality',
        level: SamplingScopeLevel.sample,
        identityKey: 'SA1',
        identity: {},
        sampleId: 'sample-1',
        sampleNumber: 1,
      ),
    ],
  );

  @override
  Future<PanelSamplingState> loadOrCreateDefault({
    required String sessionId,
    required String panelKey,
  }) async => state;

  @override
  Future<SamplingNode> addScopeIdentity({
    required String sessionId,
    required String panelKey,
    required String? parentId,
    required SamplingScopeLevel level,
    required Map<String, String> identity,
    bool discardPooledData = false,
  }) async {
    final node = SamplingNode(
      id: 'house-node-1',
      sessionId: sessionId,
      panelKey: panelKey,
      parentId: parentId,
      level: level,
      identityKey: identity['code']!,
      identity: identity,
    );
    state = PanelSamplingState(
      sessionId: sessionId,
      panelKey: panelKey,
      serialHighWatermark: state.serialHighWatermark,
      activeSampleId: state.activeSampleId,
      nodes: [...state.nodes, node],
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
    final node = SamplingNode(
      id: 'sample-node-2',
      sessionId: sessionId,
      panelKey: panelKey,
      parentId: parentId,
      level: SamplingScopeLevel.sample,
      identityKey: 'SA2',
      identity: const {},
      sampleId: 'sample-2',
      sampleNumber: 2,
    );
    state = PanelSamplingState(
      sessionId: sessionId,
      panelKey: panelKey,
      serialHighWatermark: 2,
      activeSampleId: node.sampleId!,
      nodes: [...state.nodes, node],
    );
    return node;
  }

  @override
  Future<void> updateScopeIdentity({
    required String nodeId,
    required Map<String, String> identity,
  }) async {
    final old = state.nodes.singleWhere((node) => node.id == nodeId);
    final nodes = [
      for (final node in state.nodes)
        if (node.id == nodeId)
          SamplingNode(
            id: old.id,
            sessionId: old.sessionId,
            panelKey: old.panelKey,
            parentId: old.parentId,
            level: old.level,
            identityKey: identity['code'],
            identity: identity,
            sampleId: old.sampleId,
            sampleNumber: old.sampleNumber,
          )
        else
          node,
    ];
    state = PanelSamplingState(
      sessionId: state.sessionId,
      panelKey: state.panelKey,
      serialHighWatermark: state.serialHighWatermark,
      activeSampleId: state.activeSampleId,
      nodes: nodes,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSampling(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets(
    'registered House picker identity is accepted by the repository',
    (tester) async {
      final samplingRepository = _PickerSamplingRepository();
      final provider =
          AuditProvider(
            autosaveEnabled: false,
            panelSamplingStateRepository: samplingRepository,
          )..initialize(
            AuditContext(
              auditType: 'Egg',
              customerId: 'customer-1',
              flockId: 'flock-1',
              hatcheryId: 'hatchery-1',
              breed: 'Ross308',
              date: '2026-10-05',
            ),
            sessionId: 'session-1',
            notify: false,
          );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SamplingScopeControls(
                  panelKey: 'egg_quality',
                  houseRepository: _RegisteredHouseRepository(),
                ),
              ),
            ),
          ),
        ),
      );
      await pumpSampling(tester);
      expect(find.text('Sampling'), findsOneWidget);
      expect(find.text('Selected sample: SA1'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ChoiceChip &&
              widget.label is Text &&
              (widget.label as Text).data == 'SA1',
        ),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Add House'));
      await pumpSampling(tester);
      expect(find.text('Registered houses could not be loaded.'), findsNothing);
      await tester.tap(
        find.byWidgetPredicate((widget) => widget is DropdownButtonFormField),
      );
      await pumpSampling(tester);
      await tester.tap(find.text('North House').last);
      await pumpSampling(tester);
      await tester.tap(find.text('Save').last);
      await pumpSampling(tester);

      final state = samplingRepository.state;
      final house = state.nodes.singleWhere(
        (node) => node.level == SamplingScopeLevel.house,
      );
      expect(house.identity['id'], 'house-1');
      expect(house.identity['code'], 'N01');
      expect(house.identity['name'], 'North House');
      expect(state.samples, hasLength(2));
      provider.dispose();
    },
  );

  testWidgets('empty House picker explains how to add registered houses', (
    tester,
  ) async {
    final provider =
        AuditProvider(
          autosaveEnabled: false,
          panelSamplingStateRepository: _PickerSamplingRepository(),
        )..initialize(
          AuditContext(
            auditType: 'Egg',
            customerId: 'customer-1',
            flockId: 'customer-flock-no-houses',
            hatcheryId: 'hatchery-1',
            breed: 'Ross308',
            date: '2026-10-05',
          ),
          sessionId: 'session-empty-houses',
          notify: false,
        );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SamplingScopeControls(
                panelKey: 'egg_quality',
                houseRepository: _EmptyHouseRepository(),
              ),
            ),
          ),
        ),
      ),
    );
    await pumpSampling(tester);
    await tester.tap(find.text('Add House'));
    await pumpSampling(tester);

    expect(
      find.text('No houses are registered for this flock yet.'),
      findsOneWidget,
    );
    expect(find.text('Register house'), findsOneWidget);
    expect(tester.takeException(), isNull);
    provider.dispose();
  });

  testWidgets('House picker omits a house already used at the same parent', (
    tester,
  ) async {
    final samplingRepository = _PickerSamplingRepository()
      ..state = PanelSamplingState(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
        serialHighWatermark: 1,
        activeSampleId: 'sample-1',
        nodes: [
          SamplingNode(
            id: 'sample-node-1',
            sessionId: 'session-1',
            panelKey: 'egg_quality',
            level: SamplingScopeLevel.sample,
            identityKey: 'SA1',
            identity: const {},
            sampleId: 'sample-1',
            sampleNumber: 1,
          ),
          SamplingNode(
            id: 'house-node-1',
            sessionId: 'session-1',
            panelKey: 'egg_quality',
            level: SamplingScopeLevel.house,
            identityKey: 'N01',
            identity: const {
              'id': 'house-1',
              'code': 'N01',
              'name': 'North House',
            },
          ),
        ],
      );
    final houses = _EditableHouseRepository([
      HouseModel(
        id: 'house-1',
        flockId: 'flock-1',
        name: 'North House',
        code: 'N01',
      ),
      HouseModel(
        id: 'house-2',
        flockId: 'flock-1',
        name: 'South House',
        code: 'S01',
      ),
    ]);
    final provider =
        AuditProvider(
          autosaveEnabled: false,
          panelSamplingStateRepository: samplingRepository,
        )..initialize(
          AuditContext(
            auditType: 'Egg',
            customerId: 'customer-1',
            flockId: 'flock-1',
            hatcheryId: 'hatchery-1',
            date: '2026-10-05',
          ),
          sessionId: 'session-1',
          notify: false,
        );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SamplingScopeControls(
                panelKey: 'egg_quality',
                houseRepository: houses,
              ),
            ),
          ),
        ),
      ),
    );
    await pumpSampling(tester);
    await tester.tap(find.text('Add House'));
    await pumpSampling(tester);

    final dropdown = tester.widget<DropdownButton<String>>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(DropdownButton<String>),
      ),
    );
    expect(dropdown.items!.map((item) => item.value), ['house-2']);
    expect(dropdown.items!.map((item) => (item.child as Text).data), [
      'South House',
    ]);
    await tester.tap(find.text('Cancel').last);
    await pumpSampling(tester);
    provider.dispose();
  });

  testWidgets(
    'House identity dialog supports inline registration and ID-preserving edits',
    (tester) async {
      final samplingRepository = _PickerSamplingRepository();
      final houses = _EditableHouseRepository();
      final provider =
          AuditProvider(
            autosaveEnabled: false,
            panelSamplingStateRepository: samplingRepository,
          )..initialize(
            AuditContext(
              auditType: 'Egg',
              customerId: 'customer-1',
              flockId: 'flock-1',
              hatcheryId: 'hatchery-1',
              breed: 'Ross308',
              date: '2026-10-05',
            ),
            sessionId: 'session-1',
            notify: false,
          );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SamplingScopeControls(
                  panelKey: 'egg_quality',
                  houseRepository: houses,
                ),
              ),
            ),
          ),
        ),
      );
      await pumpSampling(tester);

      expect(find.text('Selected sample: SA1'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ChoiceChip &&
              widget.label is Text &&
              (widget.label as Text).data == 'SA1',
        ),
        findsNothing,
      );
      expect(find.textContaining('Active sample:'), findsNothing);
      expect(
        find.textContaining(
          'Complete customer, hatchery, and flock sampling codes',
        ),
        findsNothing,
      );

      await tester.tap(find.text('Add House'));
      await pumpSampling(tester);
      expect(find.text('Register house'), findsOneWidget);
      await tester.tap(find.text('Register house'));
      await pumpSampling(tester);
      expect(find.text('Register House'), findsOneWidget);
      final houseFields = find.byType(TextFormField);
      await tester.enterText(houseFields.at(0), 'North House');
      await tester.enterText(houseFields.at(1), 'N01');
      await tester.tap(find.text('Save').last);
      await pumpSampling(tester);
      expect(houses.saved, hasLength(1));
      final registered = houses.saved.single;
      expect(registered.flockId, 'flock-1');
      expect(registered.name, 'North House');
      expect(registered.code, 'N01');
      expect(registered.id, isNotEmpty);
      expect(find.text('North House'), findsOneWidget);
      await tester.tap(find.text('Save').last);
      await pumpSampling(tester);

      final houseNode = samplingRepository.state.nodes.singleWhere(
        (node) => node.level == SamplingScopeLevel.house,
      );
      final historicSampleId = samplingRepository.state.activeSampleId;
      expect(houseNode.identity, {
        'id': registered.id,
        'code': 'N01',
        'name': 'North House',
      });

      final houseChip = find.byWidgetPredicate(
        (widget) =>
            widget is InputChip &&
            widget.label is Text &&
            (widget.label as Text).data == 'North House',
      );
      final editButton = find.descendant(
        of: houseChip,
        matching: find.byType(IconButton),
      );
      tester.widget<IconButton>(editButton).onPressed!();
      await pumpSampling(tester);
      expect(find.text('Edit house'), findsOneWidget);
      await tester.tap(find.text('Edit house'));
      await pumpSampling(tester);
      expect(find.text('Edit House'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'North House Updated',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'N02');
      await tester.tap(find.text('Save').last);
      await pumpSampling(tester);
      expect(houses.saved, hasLength(2));
      expect(houses.saved.last.id, registered.id);
      expect(houses.saved.last.flockId, 'flock-1');
      expect(houses.saved.last.name, 'North House Updated');
      expect(houses.saved.last.code, 'N02');
      await tester.tap(find.text('Save').last);
      await pumpSampling(tester);

      final updatedHouseNode = samplingRepository.state.nodes.singleWhere(
        (node) => node.id == houseNode.id,
      );
      expect(updatedHouseNode.identity['id'], registered.id);
      expect(updatedHouseNode.identity['name'], 'North House Updated');
      expect(updatedHouseNode.identity['code'], 'N02');
      expect(samplingRepository.state.activeSampleId, historicSampleId);
      expect(
        samplingRepository.state.samples.map((sample) => sample.sampleId),
        contains(historicSampleId),
      );
      expect(houses.requestedFlocks, everyElement('flock-1'));
      provider.dispose();
    },
  );
}
