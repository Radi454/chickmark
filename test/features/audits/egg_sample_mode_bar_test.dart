import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/panel_sampling_state.dart';
import 'package:hatchaudit/data/models/poultry_hierarchy_models.dart';
import 'package:hatchaudit/data/models/sampling_scope.dart';
import 'package:hatchaudit/data/repositories/panel_sampling_state_repository.dart';
import 'package:hatchaudit/data/repositories/poultry_hierarchy_repository.dart';
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

class _SamplingRepository extends PanelSamplingStateRepository {
  _SamplingRepository() {
    state = _state(
      [
        _sample(
          id: 'pooled-node',
          sampleId: 'pooled-sample',
          number: 1,
          parentId: null,
        ),
      ],
      activeSampleId: 'pooled-sample',
      highWatermark: 1,
    );
  }

  late PanelSamplingState state;
  int _nextId = 0;
  int _nextNumber = 1;

  SamplingNode _sample({
    required String id,
    required String sampleId,
    required int number,
    required String? parentId,
  }) => SamplingNode(
    id: id,
    sessionId: 'session-1',
    panelKey: 'egg_quality',
    parentId: parentId,
    level: SamplingScopeLevel.sample,
    identityKey: 'SA$number',
    identity: const {},
    sampleId: sampleId,
    sampleNumber: number,
  );

  PanelSamplingState _state(
    List<SamplingNode> nodes, {
    required String activeSampleId,
    required int highWatermark,
  }) => PanelSamplingState(
    sessionId: 'session-1',
    panelKey: 'egg_quality',
    nodes: nodes,
    activeSampleId: activeSampleId,
    serialHighWatermark: highWatermark,
  );

  @override
  Future<PanelSamplingState> loadOrCreateDefault({
    required String sessionId,
    required String panelKey,
  }) async {
    if (panelKey == 'egg_storage') {
      final sample = SamplingNode(
        id: 'storage-sample-node',
        sessionId: sessionId,
        panelKey: panelKey,
        level: SamplingScopeLevel.sample,
        identityKey: 'SA1',
        identity: const {},
        sampleId: 'storage-sample',
        sampleNumber: 1,
      );
      return PanelSamplingState(
        sessionId: sessionId,
        panelKey: panelKey,
        nodes: [sample],
        activeSampleId: 'storage-sample',
        serialHighWatermark: 1,
      );
    }
    return state;
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
    final node = SamplingNode(
      id: 'house-node-${++_nextId}',
      sessionId: sessionId,
      panelKey: panelKey,
      parentId: parentId,
      level: level,
      identityKey: identity['code'],
      identity: identity,
    );
    state = _state(
      [...state.nodes.where((item) => item.sampleId == null), node],
      activeSampleId: '',
      highWatermark: state.serialHighWatermark,
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
    final number = ++_nextNumber;
    final node = _sample(
      id: 'sample-node-$number',
      sampleId: 'sample-$number',
      number: number,
      parentId: parentId,
    );
    state = _state(
      [...state.nodes, node],
      activeSampleId: node.sampleId!,
      highWatermark: number,
    );
    return node;
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
    final removed = <String>{nodeId};
    var changed = true;
    while (changed) {
      changed = false;
      for (final node in state.nodes) {
        if (node.parentId != null &&
            removed.contains(node.parentId) &&
            removed.add(node.id)) {
          changed = true;
        }
      }
    }
    var remaining = state.nodes
        .where((node) => !removed.contains(node.id))
        .toList();
    if (!remaining.any((node) => node.sampleId != null)) {
      final number = ++_nextNumber;
      remaining = [
        _sample(
          id: 'sample-node-$number',
          sampleId: 'sample-$number',
          number: number,
          parentId: null,
        ),
      ];
    }
    final active = remaining
        .where((node) => node.sampleId != null)
        .first
        .sampleId!;
    state = _state(
      remaining,
      activeSampleId: active,
      highWatermark: _nextNumber,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(AuditProvider, _SamplingRepository)> pumpSampling(
    WidgetTester tester, {
    required String panelKey,
  }) async {
    final repository = _SamplingRepository();
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

  testWidgets('egg storage has one pool and no comparison controls', (
    tester,
  ) async {
    await pumpSampling(tester, panelKey: 'egg_storage');

    expect(find.text('Sampling'), findsOneWidget);
    expect(find.text('SA1'), findsOneWidget);
    expect(find.byTooltip('Add House'), findsNothing);
    expect(find.byTooltip('Add Tray'), findsNothing);
  });

  testWidgets('House comparisons use registered houses and delete by branch', (
    tester,
  ) async {
    final (provider, repository) = await pumpSampling(
      tester,
      panelKey: 'egg_quality',
    );

    await tester.tap(find.byTooltip('Add House'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Registered houses could not be loaded.'), findsNothing);
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

    final house = repository.state.nodes.singleWhere(
      (node) => node.level == SamplingScopeLevel.house,
    );
    expect(house.identity['id'], 'house-1');
    expect(house.identity['code'], 'N01');
    expect(repository.state.samples, hasLength(1));
    expect(
      repository.state.pathFor(repository.state.samples.single.sampleId!).house,
      'N01',
    );

    await tester.tap(find.byTooltip('Remove North House'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.textContaining('1 branches, 1 measurements, 2 photos, and 1 notes'),
      findsOneWidget,
    );
    await tester.tap(find.text('Delete').last);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      repository.state.nodes.where(
        (node) => node.level == SamplingScopeLevel.house,
      ),
      isEmpty,
    );
    expect(repository.state.samples, hasLength(1));
    expect(repository.state.samples.single.sampleId, isNot('pooled-sample'));
    provider.dispose();
  });
}
