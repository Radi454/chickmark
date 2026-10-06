import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/hatchery_machine_model.dart';
import 'package:hatchaudit/data/models/panel_sampling_state.dart';
import 'package:hatchaudit/data/models/sampling_scope.dart';
import 'package:hatchaudit/data/repositories/hatchery_machine_repository.dart';
import 'package:hatchaudit/data/repositories/panel_sampling_state_repository.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/widgets/sampling_scope_controls.dart';
import 'package:provider/provider.dart';

final _setter = _machine(
  id: 'setter-id',
  kind: 'setter',
  code: 'S-01',
  name: 'Setter One',
);
final _hatcher = _machine(
  id: 'hatcher-id',
  kind: 'hatcher',
  code: 'H-01',
  name: 'Hatcher One',
);

HatcheryMachineModel _machine({
  required String id,
  required String kind,
  required String code,
  required String name,
  int batchSize = 10000,
  int trolleyCapacity = 2500,
  int traySize = 80,
}) {
  final counts = HatcheryMachineModel.calculateCounts(
    batchSize: batchSize,
    trolleyCapacity: trolleyCapacity,
    traySize: traySize,
  );
  return HatcheryMachineModel(
    id: id,
    hatcheryId: 'hatchery-1',
    kind: kind,
    code: code,
    name: name,
    batchSize: batchSize,
    trolleyCapacity: trolleyCapacity,
    traySize: traySize,
    trolleyCount: counts.trolleyCount,
    traysPerTrolley: counts.traysPerTrolley,
  );
}

class _MachineRepository extends HatcheryMachineRepository {
  _MachineRepository([Iterable<HatcheryMachineModel> initial = const []])
    : machines = [...initial];

  final List<HatcheryMachineModel> machines;
  final requestedHatcheries = <String>[];
  final requestedIds = <String>[];
  final requestedKinds = <String?>[];
  final saved = <HatcheryMachineModel>[];

  @override
  Future<List<HatcheryMachineModel>> getByHatchery(
    String hatcheryId, {
    String? kind,
  }) async {
    requestedHatcheries.add(hatcheryId);
    requestedKinds.add(kind);
    return machines
        .where(
          (machine) =>
              machine.hatcheryId == hatcheryId &&
              (kind == null || machine.kind == kind),
        )
        .toList();
  }

  @override
  Future<HatcheryMachineModel?> getById(String id) async {
    requestedIds.add(id);
    return machines.where((machine) => machine.id == id).firstOrNull;
  }

  @override
  Future<void> saveMachine(HatcheryMachineModel machine) async {
    saved.add(machine);
    machines.removeWhere((item) => item.id == machine.id);
    machines.add(machine);
  }
}

class _SamplingRepository extends PanelSamplingStateRepository {
  _SamplingRepository({
    String panelKey = 'hatcher_optimizing',
    List<SamplingNode> nodes = const [],
    int serial = 1,
  }) : state = PanelSamplingState(
         sessionId: 'session-1',
         panelKey: panelKey,
         serialHighWatermark: serial,
         activeSampleId: 'sample-1',
         nodes: nodes,
       );

  PanelSamplingState state;
  int _next = 0;

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
      id: 'new-${_next++}',
      sessionId: sessionId,
      panelKey: panelKey,
      parentId: parentId,
      level: level,
      identityKey: identity['code'],
      identity: identity,
    );
    state = _replace([...state.nodes, node]);
    return node;
  }

  @override
  Future<SamplingNode> addTerminalSample({
    required String sessionId,
    required String panelKey,
    required String? parentId,
    Map<String, String>? identity,
  }) async {
    final number = state.serialHighWatermark + 1;
    final node = SamplingNode(
      id: 'terminal-${_next++}',
      sessionId: sessionId,
      panelKey: panelKey,
      parentId: parentId,
      level: SamplingScopeLevel.tray,
      identityKey: identity?['code'] ?? 'T1',
      identity: identity ?? const {'code': 'T1'},
      sampleId: 'sample-$number',
      sampleNumber: number,
    );
    state = PanelSamplingState(
      sessionId: sessionId,
      panelKey: panelKey,
      serialHighWatermark: number,
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
    state = _replace([
      for (final node in state.nodes)
        if (node.id == nodeId)
          SamplingNode(
            id: node.id,
            sessionId: node.sessionId,
            panelKey: node.panelKey,
            parentId: node.parentId,
            level: node.level,
            identityKey: identity['code'] ?? identity.values.firstOrNull,
            identity: identity,
            sampleId: node.sampleId,
            sampleNumber: node.sampleNumber,
          )
        else
          node,
    ]);
  }

  PanelSamplingState _replace(List<SamplingNode> nodes) => PanelSamplingState(
    sessionId: state.sessionId,
    panelKey: state.panelKey,
    serialHighWatermark: state.serialHighWatermark,
    activeSampleId: state.activeSampleId,
    nodes: nodes,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(AuditProvider, _SamplingRepository)> mount(
    WidgetTester tester, {
    required _MachineRepository machines,
    String panelKey = 'hatcher_optimizing',
    List<SamplingNode> nodes = const [],
  }) async {
    final sampling = _SamplingRepository(panelKey: panelKey, nodes: nodes);
    final provider =
        AuditProvider(
          autosaveEnabled: false,
          panelSamplingStateRepository: sampling,
        )..initialize(
          AuditContext(
            auditType: 'Hatch Analysis & Egg Breakouts',
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
                panelKey: panelKey,
                machineRepository: machines,
              ),
            ),
          ),
        ),
      ),
    );
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return (provider, sampling);
  }

  testWidgets(
    'machine picker filters by kind, saves stable identity, and opens inline registration/edit',
    (tester) async {
      final machines = _MachineRepository([_setter, _hatcher]);
      final (provider, sampling) = await mount(tester, machines: machines);

      await tester.tap(find.text('Add Hatcher'));
      await tester.pumpAndSettle();
      expect(machines.requestedHatcheries, contains('hatchery-1'));
      expect(find.text('S-01 · Setter One'), findsNothing);
      expect(find.text('Register machine'), findsOneWidget);

      await tester.tap(find.text('Register machine'));
      await tester.pumpAndSettle();
      expect(find.text('Register Hatcher'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      expect(find.text('S-01 · Setter One'), findsNothing);
      expect(find.text('H-01 · Hatcher One'), findsNothing);
      expect(find.text('H-01'), findsOneWidget);
      await tester.tap(find.text('H-01').last);
      await tester.pumpAndSettle();
      expect(find.text('Edit capacities'), findsOneWidget);
      await tester.tap(find.text('Edit capacities'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Hatcher capacities'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();

      final hatcher = sampling.state.nodes.singleWhere(
        (node) => node.level == SamplingScopeLevel.hatcher,
      );
      expect(hatcher.identity['hatcher'], 'H-01');
      expect(hatcher.identity['hatcherMachineId'], 'hatcher-id');
      provider.dispose();
    },
  );

  testWidgets('trolley picker offers the registered four trolley positions', (
    tester,
  ) async {
    final hatcherNode = SamplingNode(
      id: 'hatcher-node',
      sessionId: 'session-1',
      panelKey: 'hatcher_optimizing',
      level: SamplingScopeLevel.hatcher,
      identityKey: 'H-01',
      identity: const {
        'code': 'H-01',
        'hatcher': 'H-01',
        'hatcherMachineId': 'hatcher-id',
      },
    );
    final machines = _MachineRepository([_setter, _hatcher]);
    final (provider, _) = await mount(
      tester,
      machines: machines,
      nodes: [
        hatcherNode,
        SamplingNode(
          id: 'sample-node',
          sessionId: 'session-1',
          panelKey: 'hatcher_optimizing',
          parentId: 'hatcher-node',
          level: SamplingScopeLevel.tray,
          identityKey: 'T1',
          identity: const {'code': 'T1'},
          sampleId: 'sample-1',
          sampleNumber: 1,
        ),
      ],
    );

    await tester.tap(find.text('Add Trolley'));
    await tester.pumpAndSettle();
    final trolleyField = find.byType(DropdownButtonFormField<String>).last;
    await tester.tap(trolleyField);
    await tester.pumpAndSettle();
    for (var number = 1; number <= 4; number++) {
      expect(find.text('Trolley $number').last, findsOneWidget);
    }
    expect(find.text('Trolley 5'), findsNothing);
    await tester.tap(find.text('Trolley 4').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    provider.dispose();
  });

  testWidgets(
    'tray picker excludes used and offers remaining registered positions',
    (tester) async {
      final nodes = [
        SamplingNode(
          id: 'hatcher-node',
          sessionId: 'session-1',
          panelKey: 'hatcher_optimizing',
          level: SamplingScopeLevel.hatcher,
          identityKey: 'H-01',
          identity: const {
            'code': 'H-01',
            'hatcher': 'H-01',
            'hatcherMachineId': 'hatcher-id',
          },
        ),
        SamplingNode(
          id: 'trolley-node',
          sessionId: 'session-1',
          panelKey: 'hatcher_optimizing',
          parentId: 'hatcher-node',
          level: SamplingScopeLevel.trolley,
          identityKey: 'TR1',
          identity: const {'code': 'TR1', 'name': 'Trolley 1'},
        ),
        SamplingNode(
          id: 'sample-node',
          sessionId: 'session-1',
          panelKey: 'hatcher_optimizing',
          parentId: 'trolley-node',
          level: SamplingScopeLevel.tray,
          identityKey: 'T1',
          identity: const {'code': 'T1'},
          sampleId: 'sample-1',
          sampleNumber: 1,
        ),
      ];
      final machines = _MachineRepository([_setter, _hatcher]);
      final (provider, _) = await mount(
        tester,
        machines: machines,
        nodes: nodes,
      );
      expect(provider.isLoading, isFalse);
      expect(provider.isReadOnly, isFalse);

      await tester.tap(find.text('Add Tray'));
      await tester.pumpAndSettle();
      expect(machines.requestedIds, contains('hatcher-id'));
      expect(
        find.text(
          'Select or register a setter or hatcher before adding numbered trolley and tray options.',
        ),
        findsNothing,
      );
      final dropdown = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      final labels = dropdown.items!
          .map((item) => (item.child as Text).data)
          .toList();
      expect(labels, hasLength(31));
      expect(labels.first, 'Tray 2');
      expect(labels.last, 'Tray 32');
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      provider.dispose();
    },
  );

  testWidgets(
    'number picker excludes used siblings but retains current edit value',
    (tester) async {
      final nodes = [
        SamplingNode(
          id: 'hatcher-node',
          sessionId: 'session-1',
          panelKey: 'hatcher_optimizing',
          level: SamplingScopeLevel.hatcher,
          identityKey: 'H-01',
          identity: const {
            'code': 'H-01',
            'hatcher': 'H-01',
            'hatcherMachineId': 'hatcher-id',
          },
        ),
        SamplingNode(
          id: 'trolley-node',
          sessionId: 'session-1',
          panelKey: 'hatcher_optimizing',
          parentId: 'hatcher-node',
          level: SamplingScopeLevel.trolley,
          identityKey: 'TR1',
          identity: const {'code': 'TR1', 'name': 'Trolley 1'},
        ),
        for (final number in [1, 2])
          SamplingNode(
            id: 'tray-$number',
            sessionId: 'session-1',
            panelKey: 'hatcher_optimizing',
            parentId: 'trolley-node',
            level: SamplingScopeLevel.tray,
            identityKey: 'T$number',
            identity: {'code': 'T$number'},
            sampleId: 'sample-$number',
            sampleNumber: number,
          ),
        SamplingNode(
          id: 'other-hatcher-node',
          sessionId: 'session-1',
          panelKey: 'hatcher_optimizing',
          level: SamplingScopeLevel.hatcher,
          identityKey: 'H-02',
          identity: const {
            'code': 'H-02',
            'hatcher': 'H-02',
            'hatcherMachineId': 'hatcher-two-id',
          },
        ),
        SamplingNode(
          id: 'other-trolley-node',
          sessionId: 'session-1',
          panelKey: 'hatcher_optimizing',
          parentId: 'other-hatcher-node',
          level: SamplingScopeLevel.trolley,
          identityKey: 'TR1',
          identity: const {'code': 'TR1'},
        ),
        SamplingNode(
          id: 'other-tray-node',
          sessionId: 'session-1',
          panelKey: 'hatcher_optimizing',
          parentId: 'other-trolley-node',
          level: SamplingScopeLevel.tray,
          identityKey: 'T3',
          identity: const {'code': 'T3'},
          sampleId: 'sample-other',
          sampleNumber: 3,
        ),
      ];
      final (provider, _) = await mount(
        tester,
        machines: _MachineRepository([
          _hatcher,
          _machine(
            id: 'hatcher-two-id',
            kind: 'hatcher',
            code: 'H-02',
            name: 'Hatcher Two',
          ),
        ]),
        nodes: nodes,
      );

      await tester.tap(find.text('Add Tray'));
      await tester.pumpAndSettle();
      final addField = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(addField.items!.map((item) => item.value), isNot(contains('1')));
      expect(addField.items!.map((item) => item.value), isNot(contains('2')));
      expect(
        addField.items!.map((item) => item.value),
        contains('3'),
        reason: 'a tray in a different trolley branch does not reserve T3 here',
      );
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();

      final secondTrayChip = find.byWidgetPredicate(
        (widget) =>
            widget is InputChip &&
            widget.label is Text &&
            (widget.label as Text).data == 'T2',
      );
      final edit = find.descendant(
        of: secondTrayChip,
        matching: find.byType(IconButton),
      );
      tester.widget<IconButton>(edit).onPressed!();
      await tester.pumpAndSettle();
      final editField = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(editField.value, '2');
      expect(editField.items!.map((item) => item.value), contains('2'));
      expect(editField.items!.map((item) => item.value), isNot(contains('1')));
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      provider.dispose();
    },
  );

  testWidgets(
    'out-of-capacity legacy tray survives editing with active sample identity',
    (tester) async {
      final nodes = [
        SamplingNode(
          id: 'hatcher-node',
          sessionId: 'session-1',
          panelKey: 'hatcher_optimizing',
          level: SamplingScopeLevel.hatcher,
          identityKey: 'H-01',
          identity: const {
            'code': 'H-01',
            'hatcher': 'H-01',
            'hatcherMachineId': 'hatcher-id',
          },
        ),
        SamplingNode(
          id: 'trolley-node',
          sessionId: 'session-1',
          panelKey: 'hatcher_optimizing',
          parentId: 'hatcher-node',
          level: SamplingScopeLevel.trolley,
          identityKey: 'TR1',
          identity: const {'code': 'TR1', 'name': 'Trolley 1'},
        ),
        SamplingNode(
          id: 'tray-node',
          sessionId: 'session-1',
          panelKey: 'hatcher_optimizing',
          parentId: 'trolley-node',
          level: SamplingScopeLevel.tray,
          identityKey: 'T40',
          identity: const {'code': 'T40'},
          sampleId: 'sample-1',
          sampleNumber: 1,
        ),
      ];
      final machines = _MachineRepository([_hatcher]);
      final (provider, sampling) = await mount(
        tester,
        machines: machines,
        nodes: nodes,
      );
      expect(provider.activeSampleIdFor('hatcher_optimizing'), 'sample-1');

      final trayChip = find.byWidgetPredicate(
        (widget) =>
            widget is InputChip &&
            widget.label is Text &&
            (widget.label as Text).data == 'T40',
      );
      final editButton = find.descendant(
        of: trayChip,
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(editButton).onPressed, isNotNull);
      tester.widget<IconButton>(editButton).onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('Legacy · T40'), findsOneWidget);
      expect(
        find.text(
          'This saved value is above the registered capacity. It remains available for this existing sampling branch.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();

      expect(
        sampling.state.nodes
            .singleWhere((node) => node.id == 'tray-node')
            .identity['code'],
        'T40',
      );
      expect(provider.activeSampleIdFor('hatcher_optimizing'), 'sample-1');
      provider.dispose();
    },
  );

  testWidgets(
    'shrinking capacity preserves an existing choice as legacy and clears a new choice',
    (tester) async {
      final nodes = [
        SamplingNode(
          id: 'hatcher-node',
          sessionId: 'session-1',
          panelKey: 'hatcher_optimizing',
          level: SamplingScopeLevel.hatcher,
          identityKey: 'H-01',
          identity: const {
            'code': 'H-01',
            'hatcher': 'H-01',
            'hatcherMachineId': 'hatcher-id',
          },
        ),
        SamplingNode(
          id: 'trolley-node',
          sessionId: 'session-1',
          panelKey: 'hatcher_optimizing',
          parentId: 'hatcher-node',
          level: SamplingScopeLevel.trolley,
          identityKey: 'TR1',
          identity: const {'code': 'TR1'},
        ),
        SamplingNode(
          id: 'tray-node',
          sessionId: 'session-1',
          panelKey: 'hatcher_optimizing',
          parentId: 'trolley-node',
          level: SamplingScopeLevel.tray,
          identityKey: 'T20',
          identity: const {'code': 'T20'},
          sampleId: 'sample-1',
          sampleNumber: 1,
        ),
      ];
      final machines = _MachineRepository([_hatcher]);
      final (provider, sampling) = await mount(
        tester,
        machines: machines,
        nodes: nodes,
      );

      final trayChip = find.byWidgetPredicate(
        (widget) =>
            widget is InputChip &&
            widget.label is Text &&
            (widget.label as Text).data == 'T20',
      );
      tester
          .widget<IconButton>(
            find.descendant(of: trayChip, matching: find.byType(IconButton)),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit capacities'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(3), '2500');
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      expect(find.text('Legacy · T20'), findsOneWidget);
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      expect(
        sampling.state.nodes
            .singleWhere((node) => node.id == 'tray-node')
            .identity['code'],
        'T20',
      );

      await tester.tap(find.text('Add Tray'));
      await tester.pumpAndSettle();
      final field = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(field.items!.map((item) => item.value), isNot(contains('2')));
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(provider.activeSampleIdFor('hatcher_optimizing'), 'sample-1');
      provider.dispose();
    },
  );

  testWidgets('capacity shrink clears an unavailable newly selected tray', (
    tester,
  ) async {
    final (provider, _) = await mount(
      tester,
      machines: _MachineRepository([_hatcher]),
      nodes: [
        SamplingNode(
          id: 'hatcher-node',
          sessionId: 'session-1',
          panelKey: 'hatcher_optimizing',
          level: SamplingScopeLevel.hatcher,
          identityKey: 'H-01',
          identity: const {
            'code': 'H-01',
            'hatcher': 'H-01',
            'hatcherMachineId': 'hatcher-id',
          },
        ),
        SamplingNode(
          id: 'trolley-node',
          sessionId: 'session-1',
          panelKey: 'hatcher_optimizing',
          parentId: 'hatcher-node',
          level: SamplingScopeLevel.trolley,
          identityKey: 'TR1',
          identity: const {'code': 'TR1'},
        ),
        SamplingNode(
          id: 'tray-node',
          sessionId: 'session-1',
          panelKey: 'hatcher_optimizing',
          parentId: 'trolley-node',
          level: SamplingScopeLevel.tray,
          identityKey: 'T1',
          identity: const {'code': 'T1'},
          sampleId: 'sample-1',
          sampleNumber: 1,
        ),
      ],
    );

    await tester.tap(find.text('Add Tray'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tray 2').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit capacities'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(3), '2500');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    final field = tester.widget<DropdownButton<String>>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(DropdownButton<String>),
      ),
    );
    expect(field.value, isNull);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    provider.dispose();
  });

  for (final legacyCode in ['0', 'QA-T2']) {
    testWidgets(
      'legacy tray code $legacyCode remains explicit and keeps sample identity',
      (tester) async {
        final nodes = [
          SamplingNode(
            id: 'hatcher-node',
            sessionId: 'session-1',
            panelKey: 'hatcher_optimizing',
            level: SamplingScopeLevel.hatcher,
            identityKey: 'H-01',
            identity: const {
              'code': 'H-01',
              'hatcher': 'H-01',
              'hatcherMachineId': 'hatcher-id',
            },
          ),
          SamplingNode(
            id: 'trolley-node',
            sessionId: 'session-1',
            panelKey: 'hatcher_optimizing',
            parentId: 'hatcher-node',
            level: SamplingScopeLevel.trolley,
            identityKey: 'TR1',
            identity: const {'code': 'TR1', 'name': 'Trolley 1'},
          ),
          SamplingNode(
            id: 'tray-node',
            sessionId: 'session-1',
            panelKey: 'hatcher_optimizing',
            parentId: 'trolley-node',
            level: SamplingScopeLevel.tray,
            identityKey: legacyCode,
            identity: {'code': legacyCode},
            sampleId: 'sample-1',
            sampleNumber: 1,
          ),
        ];
        final (provider, sampling) = await mount(
          tester,
          machines: _MachineRepository([_hatcher]),
          nodes: nodes,
        );

        final trayChip = find.byWidgetPredicate(
          (widget) =>
              widget is InputChip &&
              widget.label is Text &&
              (widget.label as Text).data == legacyCode,
        );
        final editButton = find.descendant(
          of: trayChip,
          matching: find.byType(IconButton),
        );
        expect(tester.widget<IconButton>(editButton).onPressed, isNotNull);
        tester.widget<IconButton>(editButton).onPressed!();
        await tester.pumpAndSettle();
        expect(find.text('Legacy · $legacyCode'), findsOneWidget);
        await tester.tap(find.text('Save').last);
        await tester.pumpAndSettle();

        expect(
          sampling.state.nodes
              .singleWhere((node) => node.id == 'tray-node')
              .identity['code'],
          legacyCode,
        );
        expect(provider.activeSampleIdFor('hatcher_optimizing'), 'sample-1');
        provider.dispose();
      },
    );
  }

  testWidgets(
    'machine picker omits sibling-used machines and shows code only',
    (tester) async {
      final nodes = [
        SamplingNode(
          id: 'hatcher-one',
          sessionId: 'session-1',
          panelKey: 'hatcher_optimizing',
          level: SamplingScopeLevel.hatcher,
          identityKey: 'H-01',
          identity: const {
            'code': 'H-01',
            'hatcher': 'H-01',
            'hatcherMachineId': 'hatcher-id',
          },
        ),
        SamplingNode(
          id: 'sample-one',
          sessionId: 'session-1',
          panelKey: 'hatcher_optimizing',
          parentId: 'hatcher-one',
          level: SamplingScopeLevel.tray,
          identityKey: 'T1',
          identity: const {'code': 'T1'},
          sampleId: 'sample-1',
          sampleNumber: 1,
        ),
      ];
      final (provider, _) = await mount(
        tester,
        machines: _MachineRepository([
          _setter,
          _hatcher,
          _machine(
            id: 'hatcher-two-id',
            kind: 'hatcher',
            code: 'H-02',
            name: 'Hatcher Two',
          ),
        ]),
        nodes: nodes,
      );

      await tester.tap(find.text('Add Hatcher'));
      await tester.pumpAndSettle();
      final field = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(
        field.items!.map((item) => item.value),
        isNot(contains('hatcher-id')),
      );
      expect(
        field.items!.map(
          (item) => item.child is Text ? (item.child as Text).data : null,
        ),
        ['H-02'],
      );
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      provider.dispose();
    },
  );

  testWidgets(
    'editing a machine keeps its current choice and excludes used sibling',
    (tester) async {
      final secondHatcher = _machine(
        id: 'hatcher-two-id',
        kind: 'hatcher',
        code: 'H-02',
        name: 'Hatcher Two',
      );
      final nodes = [
        SamplingNode(
          id: 'hatcher-one',
          sessionId: 'session-1',
          panelKey: 'hatcher_optimizing',
          level: SamplingScopeLevel.hatcher,
          identityKey: 'H-01',
          identity: const {
            'code': 'H-01',
            'hatcher': 'H-01',
            'hatcherMachineId': 'hatcher-id',
          },
        ),
        SamplingNode(
          id: 'sample-one',
          sessionId: 'session-1',
          panelKey: 'hatcher_optimizing',
          parentId: 'hatcher-one',
          level: SamplingScopeLevel.tray,
          identityKey: 'T1',
          identity: const {'code': 'T1'},
          sampleId: 'sample-1',
          sampleNumber: 1,
        ),
        SamplingNode(
          id: 'hatcher-two',
          sessionId: 'session-1',
          panelKey: 'hatcher_optimizing',
          level: SamplingScopeLevel.hatcher,
          identityKey: 'H-02',
          identity: const {
            'code': 'H-02',
            'hatcher': 'H-02',
            'hatcherMachineId': 'hatcher-two-id',
          },
        ),
      ];
      final (provider, _) = await mount(
        tester,
        machines: _MachineRepository([_setter, _hatcher, secondHatcher]),
        nodes: nodes,
      );
      final chip = find.byWidgetPredicate(
        (widget) =>
            widget is InputChip &&
            widget.label is Text &&
            (widget.label as Text).data == 'H-01',
      );
      final edit = find.descendant(of: chip, matching: find.byType(IconButton));
      tester.widget<IconButton>(edit).onPressed!();
      await tester.pumpAndSettle();
      final field = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(field.value, 'hatcher-id');
      expect(field.items!.map((item) => item.value), ['hatcher-id']);
      expect(find.text('H-01'), findsNWidgets(2));
      expect(find.text('Hatcher One'), findsNothing);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      provider.dispose();
    },
  );

  testWidgets(
    'paired machine picker filters complete pairs instead of components',
    (tester) async {
      final secondHatcher = _machine(
        id: 'hatcher-two-id',
        kind: 'hatcher',
        code: 'H-02',
        name: 'Hatcher Two',
      );
      final pair = SamplingNode(
        id: 'pair-one',
        sessionId: 'session-1',
        panelKey: 'chick_quality',
        level: SamplingScopeLevel.setter,
        identityKey: 'S-01|H-01',
        identity: const {
          'setter': 'S-01',
          'hatcher': 'H-01',
          'setterMachineId': 'setter-id',
          'hatcherMachineId': 'hatcher-id',
        },
      );
      final sample = SamplingNode(
        id: 'sample-one',
        sessionId: 'session-1',
        panelKey: 'chick_quality',
        parentId: 'pair-one',
        level: SamplingScopeLevel.sample,
        identityKey: 'SA1',
        identity: const {},
        sampleId: 'sample-1',
        sampleNumber: 1,
      );
      final (provider, _) = await mount(
        tester,
        panelKey: 'chick_quality',
        machines: _MachineRepository([_setter, _hatcher, secondHatcher]),
        nodes: [pair, sample],
      );

      await tester.tap(find.text('Add Setter / Hatcher'));
      await tester.pumpAndSettle();
      final setterField = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == 'Setter',
      );
      await tester.tap(setterField);
      await tester.pumpAndSettle();
      expect(find.text('S-01'), findsOneWidget);
      await tester.tap(find.text('S-01').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is DropdownButtonFormField<String> &&
              widget.decoration.labelText == 'Hatcher',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('H-01'), findsNothing);
      expect(find.text('H-02'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      provider.dispose();
    },
  );

  testWidgets('editing a pair cannot change into an already used full pair', (
    tester,
  ) async {
    final setterTwo = _machine(
      id: 'setter-two-id',
      kind: 'setter',
      code: 'S-02',
      name: 'Setter Two',
    );
    final hatcherTwo = _machine(
      id: 'hatcher-two-id',
      kind: 'hatcher',
      code: 'H-02',
      name: 'Hatcher Two',
    );
    final currentPair = SamplingNode(
      id: 'pair-one',
      sessionId: 'session-1',
      panelKey: 'chick_quality',
      level: SamplingScopeLevel.setter,
      identityKey: 'S-01|H-01',
      identity: const {
        'setter': 'S-01',
        'hatcher': 'H-01',
        'setterMachineId': 'setter-id',
        'hatcherMachineId': 'hatcher-id',
      },
    );
    final usedPair = SamplingNode(
      id: 'pair-two',
      sessionId: 'session-1',
      panelKey: 'chick_quality',
      level: SamplingScopeLevel.setter,
      identityKey: 'S-01|H-02',
      identity: const {
        'setter': 'S-01',
        'hatcher': 'H-02',
        'setterMachineId': 'setter-id',
        'hatcherMachineId': 'hatcher-two-id',
      },
    );
    final (provider, _) = await mount(
      tester,
      panelKey: 'chick_quality',
      machines: _MachineRepository([_setter, setterTwo, _hatcher, hatcherTwo]),
      nodes: [
        currentPair,
        usedPair,
        SamplingNode(
          id: 'sample-one',
          sessionId: 'session-1',
          panelKey: 'chick_quality',
          parentId: currentPair.id,
          level: SamplingScopeLevel.sample,
          identityKey: 'SA1',
          identity: const {},
          sampleId: 'sample-1',
          sampleNumber: 1,
        ),
      ],
    );
    final pairChip = find.byWidgetPredicate(
      (widget) =>
          widget is InputChip &&
          widget.label is Text &&
          (widget.label as Text).data == 'S-01 / H-01',
    );
    tester
        .widget<IconButton>(
          find.descendant(of: pairChip, matching: find.byType(IconButton)),
        )
        .onPressed!();
    await tester.pumpAndSettle();

    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == 'Setter',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('S-02').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == 'Hatcher',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('H-02').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == 'Setter',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('S-01'), findsNothing);
    expect(find.text('S-02'), findsNWidgets(2));
    await tester.tap(find.text('Cancel').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    provider.dispose();
  });

  testWidgets(
    'number picker resolves a missing catalog id by same hatchery kind and code',
    (tester) async {
      final hatcherNode = SamplingNode(
        id: 'hatcher-node',
        sessionId: 'session-1',
        panelKey: 'hatcher_optimizing',
        level: SamplingScopeLevel.hatcher,
        identityKey: 'H-01',
        identity: const {
          'code': 'H-01',
          'hatcher': 'H-01',
          'hatcherMachineId': 'retired-id',
        },
      );
      final (provider, _) = await mount(
        tester,
        machines: _MachineRepository([_setter, _hatcher]),
        nodes: [
          hatcherNode,
          SamplingNode(
            id: 'sample-node',
            sessionId: 'session-1',
            panelKey: 'hatcher_optimizing',
            parentId: 'hatcher-node',
            level: SamplingScopeLevel.tray,
            identityKey: 'T1',
            identity: const {'code': 'T1'},
            sampleId: 'sample-1',
            sampleNumber: 1,
          ),
        ],
      );
      await tester.tap(find.text('Add Trolley'));
      await tester.pumpAndSettle();
      final field = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(field.items!.map((item) => item.value), ['1', '2', '3', '4']);
      await tester.tap(find.text('Cancel').last, warnIfMissed: false);
      await tester.pumpAndSettle();
      provider.dispose();
    },
  );

  testWidgets(
    'unavailable nearer hatcher does not borrow ancestor setter capacity',
    (tester) async {
      final setterNode = SamplingNode(
        id: 'setter-node',
        sessionId: 'session-1',
        panelKey: 'hatcher_optimizing',
        level: SamplingScopeLevel.setter,
        identityKey: 'S-01',
        identity: const {
          'code': 'S-01',
          'setter': 'S-01',
          'setterMachineId': 'setter-id',
        },
      );
      final hatcherNode = SamplingNode(
        id: 'hatcher-node',
        sessionId: 'session-1',
        panelKey: 'hatcher_optimizing',
        parentId: setterNode.id,
        level: SamplingScopeLevel.hatcher,
        identityKey: 'H-99',
        identity: const {
          'code': 'H-99',
          'hatcher': 'H-99',
          'hatcherMachineId': 'retired-hatcher-id',
        },
      );
      final trolleyNode = SamplingNode(
        id: 'trolley-node',
        sessionId: 'session-1',
        panelKey: 'hatcher_optimizing',
        parentId: hatcherNode.id,
        level: SamplingScopeLevel.trolley,
        identityKey: 'TR1',
        identity: const {'code': 'TR1'},
      );
      final machines = _MachineRepository([_setter, _hatcher]);
      final (provider, _) = await mount(
        tester,
        machines: machines,
        nodes: [
          setterNode,
          hatcherNode,
          trolleyNode,
          SamplingNode(
            id: 'sample-node',
            sessionId: 'session-1',
            panelKey: 'hatcher_optimizing',
            parentId: trolleyNode.id,
            level: SamplingScopeLevel.tray,
            identityKey: 'T1',
            identity: const {'code': 'T1'},
            sampleId: 'sample-1',
            sampleNumber: 1,
          ),
        ],
      );
      await tester.tap(find.text('Add Trolley'));
      await tester.pumpAndSettle();
      expect(machines.requestedIds, contains('retired-hatcher-id'));
      expect(machines.requestedIds, isNot(contains('setter-id')));
      expect(
        find.text(
          'This machine is not available in the selected hatchery. Edit its scope to select a registered machine before adding numbered options.',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.text('Cancel').last, warnIfMissed: false);
      await tester.pumpAndSettle();
      provider.dispose();
    },
  );

  testWidgets('sample display omits fallback path and one-sample selector', (
    tester,
  ) async {
    final (provider, _) = await mount(
      tester,
      machines: _MachineRepository([_hatcher]),
      nodes: [
        SamplingNode(
          id: 'hatcher-node',
          sessionId: 'session-1',
          panelKey: 'hatcher_optimizing',
          level: SamplingScopeLevel.hatcher,
          identityKey: 'H-01',
          identity: const {
            'code': 'H-01',
            'hatcher': 'H-01',
            'hatcherMachineId': 'hatcher-id',
          },
        ),
        SamplingNode(
          id: 'sample-node',
          sessionId: 'session-1',
          panelKey: 'hatcher_optimizing',
          parentId: 'hatcher-node',
          level: SamplingScopeLevel.tray,
          identityKey: 'T2',
          identity: const {'code': 'T2'},
          sampleId: 'sample-1',
          sampleNumber: 1,
        ),
      ],
    );

    expect(find.textContaining('Active sample:'), findsNothing);
    expect(
      find.textContaining(
        'Complete customer, hatchery, and flock sampling codes',
      ),
      findsNothing,
    );
    expect(find.text('Selected sample: SA1'), findsOneWidget);
    provider.dispose();
  });
}
