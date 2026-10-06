import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/theme/app_theme.dart';
import 'package:hatchaudit/data/models/hatchery_machine_model.dart';
import 'package:hatchaudit/data/models/panel_sampling_state.dart';
import 'package:hatchaudit/data/models/sampling_scope.dart';
import 'package:hatchaudit/data/repositories/panel_sampling_state_repository.dart';
import 'package:hatchaudit/data/repositories/hatchery_machine_repository.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/widgets/sampling_scope_controls.dart';
import 'package:provider/provider.dart';

class _MemorySamplingRepository extends PanelSamplingStateRepository {
  _MemorySamplingRepository({this.duplicateOnAdd = false}) : super();

  final bool duplicateOnAdd;
  final List<(SamplingScopeLevel, String?)> scopeAdds = [];
  final List<String?> terminalParents = [];

  late PanelSamplingState state = PanelSamplingState(
    sessionId: 'session-1',
    panelKey: 'residue_breakout',
    serialHighWatermark: 1,
    activeSampleId: 'sample-1',
    nodes: [
      SamplingNode(
        id: 'house-1',
        sessionId: 'session-1',
        panelKey: 'residue_breakout',
        level: SamplingScopeLevel.house,
        identityKey: 'H1',
        identity: const {'code': 'H1'},
      ),
      SamplingNode(
        id: 'tray-1',
        sessionId: 'session-1',
        panelKey: 'residue_breakout',
        parentId: 'house-1',
        level: SamplingScopeLevel.tray,
        identityKey: 'T1',
        identity: const {'code': 'T1'},
        sampleId: 'sample-1',
        sampleNumber: 1,
      ),
    ],
  );
  String? addedParentId;

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
    addedParentId = parentId;
    scopeAdds.add((level, parentId));
    if (duplicateOnAdd) {
      throw ArgumentError(
        'That scope identity already exists under this parent.',
      );
    }
    final node = SamplingNode(
      id: 'added-${state.nodes.length}',
      sessionId: sessionId,
      panelKey: panelKey,
      parentId: parentId,
      level: level,
      identity: identity,
      identityKey: identity.values.join('|'),
    );
    state = PanelSamplingState(
      sessionId: state.sessionId,
      panelKey: state.panelKey,
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
    terminalParents.add(parentId);
    if (identity == null) {
      throw ArgumentError('Tray samples require an identity.');
    }
    final number = state.serialHighWatermark + 1;
    final node = SamplingNode(
      id: 'terminal-${state.nodes.length}',
      sessionId: sessionId,
      panelKey: panelKey,
      parentId: parentId,
      level: SamplingScopeLevel.tray,
      identity: identity,
      identityKey: 'Tray$number',
      sampleId: 'sample-$number',
      sampleNumber: number,
    );
    state = PanelSamplingState(
      sessionId: state.sessionId,
      panelKey: state.panelKey,
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
  }) async {}

  @override
  Future<SamplingDeletePreview> previewDeleteSubtree({
    required String nodeId,
  }) async => SamplingDeletePreview(
    nodeId: nodeId,
    scopeLabel: 'H1',
    descendantCount: 1,
    measurementCount: 1,
    photoCount: 0,
    noteCount: 0,
  );

  @override
  Future<void> deleteSubtree({required String nodeId}) async {}
}

HatcheryMachineModel _registeredMachine({
  required String id,
  required String kind,
  required String code,
}) {
  const batchSize = 10000;
  const trolleyCapacity = 2500;
  const traySize = 80;
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
    name: code,
    batchSize: batchSize,
    trolleyCapacity: trolleyCapacity,
    traySize: traySize,
    trolleyCount: counts.trolleyCount,
    traysPerTrolley: counts.traysPerTrolley,
  );
}

class _MemoryMachineRepository extends HatcheryMachineRepository {
  _MemoryMachineRepository(this.machines);

  final List<HatcheryMachineModel> machines;

  @override
  Future<List<HatcheryMachineModel>> getByHatchery(
    String hatcheryId, {
    String? kind,
  }) async => machines
      .where(
        (machine) =>
            machine.hatcheryId == hatcheryId &&
            (kind == null || machine.kind == kind),
      )
      .toList();

  @override
  Future<HatcheryMachineModel?> getById(String id) async =>
      machines.where((machine) => machine.id == id).firstOrNull;
}

Future<void> _selectMachine(
  WidgetTester tester,
  int fieldIndex,
  String code,
) async {
  final field = find.byType(DropdownButtonFormField<String>).at(fieldIndex);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(code).last);
  await tester.pumpAndSettle();
}

Future<void> _selectNumber(WidgetTester tester, String label) async {
  final field = find.byType(DropdownButtonFormField<String>).first;
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('scope labels use readable app surface colors at phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final repository = _MemorySamplingRepository();
    final provider =
        AuditProvider(
          autosaveEnabled: false,
          panelSamplingStateRepository: repository,
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
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: SamplingScopeControls(panelKey: 'residue_breakout'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final theme = AppTheme.light();
    final headers = tester.widgetList<Text>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            {'House', 'Setter', 'Hatcher', 'Trolley'}.contains(widget.data),
      ),
    );
    expect(headers, hasLength(4));
    expect(
      headers.every((text) => text.style?.color == theme.colorScheme.onSurface),
      isTrue,
    );
    final pooledChips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
    expect(
      pooledChips
          .where((chip) => chip.selected)
          .every(
            (chip) =>
                (chip.label as Text).style?.color ==
                theme.colorScheme.onPrimary,
          ),
      isTrue,
    );
    final selectedScope = tester.widget<InputChip>(
      find.byType(InputChip).first,
    );
    expect(selectedScope.selected, isTrue);
    expect(
      (selectedScope.label as Text).style?.color,
      theme.colorScheme.onPrimary,
    );
    expect(selectedScope.deleteIconColor, theme.colorScheme.onPrimary);
    expect(
      ((selectedScope.avatar as IconButton).icon as Icon).color,
      theme.colorScheme.onPrimary,
    );
    expect(find.text('Add House'), findsOneWidget);
    expect(tester.takeException(), isNull);
    provider.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('setter scope is named Setter outside paired chick quality', (
    tester,
  ) async {
    final repository = _MemorySamplingRepository()
      ..state = PanelSamplingState(
        sessionId: 'session-1',
        panelKey: 'setter_optimizing',
        serialHighWatermark: 0,
        activeSampleId: 'sample-1',
        nodes: const [],
      );
    final provider =
        AuditProvider(
          autosaveEnabled: false,
          panelSamplingStateRepository: repository,
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
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: SamplingScopeControls(
                panelKey: 'setter_optimizing',
                machineRepository: _MemoryMachineRepository([
                  _registeredMachine(
                    id: 'setter-1',
                    kind: 'setter',
                    code: 'S-01',
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('Setter'), findsOneWidget);
    expect(find.text('Setter / Hatcher'), findsNothing);
    await tester.tap(find.text('Add Setter').first);
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(of: dialog, matching: find.text('Add Setter')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Setter')),
      findsOneWidget,
    );
    expect(find.text('Setter / Hatcher'), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('S-01'), findsOneWidget);
    await tester.tap(find.text('S-01'));
    await tester.pumpAndSettle();
    provider.dispose();
  });

  testWidgets(
    'duplicate paired identity shows the duplicate-specific message',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      final repository = _MemorySamplingRepository(duplicateOnAdd: true)
        ..state = PanelSamplingState(
          sessionId: 'session-1',
          panelKey: 'chick_quality',
          serialHighWatermark: 0,
          activeSampleId: 'sample-1',
          nodes: const [],
        );
      final provider =
          AuditProvider(
            autosaveEnabled: false,
            panelSamplingStateRepository: repository,
          )..initialize(
            AuditContext(
              auditType: 'Chicks',
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
            theme: AppTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: SamplingScopeControls(
                  panelKey: 'chick_quality',
                  machineRepository: _MemoryMachineRepository([
                    _registeredMachine(
                      id: 'setter-1',
                      kind: 'setter',
                      code: 'S-01',
                    ),
                    _registeredMachine(
                      id: 'hatcher-1',
                      kind: 'hatcher',
                      code: 'H-01',
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(tester.takeException(), isNull);
      expect(find.text('Add Setter / Hatcher'), findsOneWidget);
      await tester.tap(find.text('Add Setter / Hatcher'));
      await tester.pumpAndSettle();
      await _selectMachine(tester, 0, 'S-01');
      await _selectMachine(tester, 1, 'H-01');
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();

      expect(
        find.text('That identity already exists under this parent.'),
        findsOneWidget,
      );
      expect(
        find.text('Sampling identity could not be saved. Try again.'),
        findsNothing,
      );
      provider.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets('Hatcher to Trolley gets default Tray leaves under each branch', (
    tester,
  ) async {
    final repository = _MemorySamplingRepository()
      ..state = PanelSamplingState(
        sessionId: 'session-1',
        panelKey: 'hatcher_optimizing',
        serialHighWatermark: 0,
        activeSampleId: 'sample-1',
        nodes: const [],
      );
    final provider =
        AuditProvider(
          autosaveEnabled: false,
          panelSamplingStateRepository: repository,
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
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: SamplingScopeControls(
                panelKey: 'hatcher_optimizing',
                machineRepository: _MemoryMachineRepository([
                  _registeredMachine(
                    id: 'hatcher-1',
                    kind: 'hatcher',
                    code: 'H-01',
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    await tester.tap(find.text('Add Hatcher'));
    await tester.pumpAndSettle();
    await _selectMachine(tester, 0, 'H-01');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    final hatcher = repository.state.nodes.singleWhere(
      (node) => node.level == SamplingScopeLevel.hatcher,
    );
    expect(repository.scopeAdds.single, (SamplingScopeLevel.hatcher, null));
    final hatcherTray = repository.state.samples.singleWhere(
      (sample) => sample.parentId == hatcher.id,
    );
    expect(hatcherTray.level, SamplingScopeLevel.tray);
    expect(hatcherTray.identity['code'], 'T1');
    expect(
      provider.activeSampleIdFor('hatcher_optimizing'),
      hatcherTray.sampleId,
    );

    await tester.tap(find.text('Add Trolley'));
    await tester.pumpAndSettle();
    await _selectNumber(tester, 'Trolley 1');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    final firstTrolley = repository.state.nodes.singleWhere(
      (node) => node.level == SamplingScopeLevel.trolley,
    );
    expect(firstTrolley.parentId, hatcher.id);
    final trolleyTray = repository.state.samples.singleWhere(
      (sample) => sample.parentId == firstTrolley.id,
    );
    expect(trolleyTray.identity['code'], 'T1');
    final path = repository.state.pathFor(trolleyTray.sampleId!);
    expect(path.hatcher, 'H-01');
    expect(path.trolley, 'TR1');
    expect(path.tray, 'T1');

    await tester.tap(find.text('Add Trolley'));
    await tester.pumpAndSettle();
    await _selectNumber(tester, 'Trolley 2');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    final siblingTrolley = repository.state.nodes.singleWhere(
      (node) =>
          node.level == SamplingScopeLevel.trolley &&
          node.identity['code'] == 'TR2',
    );
    expect(siblingTrolley.parentId, hatcher.id);
    await tester.tap(find.text('Trolley 1'));
    await tester.pumpAndSettle();
    expect(
      provider.activeSampleIdFor('hatcher_optimizing'),
      trolleyTray.sampleId,
    );
    expect(repository.terminalParents, [
      hatcher.id,
      firstTrolley.id,
      siblingTrolley.id,
    ]);
    provider.dispose();
  });

  testWidgets('selecting a legacy branch without a leaf creates its terminal', (
    tester,
  ) async {
    final repository = _MemorySamplingRepository()
      ..state = PanelSamplingState(
        sessionId: 'session-1',
        panelKey: 'hatcher_optimizing',
        serialHighWatermark: 8,
        activeSampleId: 'missing-sample',
        nodes: [
          SamplingNode(
            id: 'legacy-hatcher',
            sessionId: 'session-1',
            panelKey: 'hatcher_optimizing',
            level: SamplingScopeLevel.hatcher,
            identityKey: 'QA-H1',
            identity: const {'code': 'QA-H1'},
          ),
        ],
      );
    final provider =
        AuditProvider(
          autosaveEnabled: false,
          panelSamplingStateRepository: repository,
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
          theme: AppTheme.light(),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: SamplingScopeControls(panelKey: 'hatcher_optimizing'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.tap(find.text('QA-H1'));
    await tester.pumpAndSettle();

    expect(repository.terminalParents, ['legacy-hatcher']);
    expect(repository.state.samples.single.sampleNumber, 9);
    expect(
      provider.activeSampleIdFor('hatcher_optimizing'),
      repository.state.samples.single.sampleId,
    );
    provider.dispose();
  });

  testWidgets('a skipped pooled level keeps the nearest selected parent', (
    tester,
  ) async {
    final repository = _MemorySamplingRepository();
    final machines = _MemoryMachineRepository([
      _registeredMachine(id: 'hatcher-1', kind: 'hatcher', code: 'H-01'),
    ]);
    final provider =
        AuditProvider(
          autosaveEnabled: false,
          panelSamplingStateRepository: repository,
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
                panelKey: 'residue_breakout',
                machineRepository: machines,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // Tray is a terminal identity in this panel, never a pooled level. The
    // remaining scopes keep their default Pooled label, but those chips are
    // inert rather than a control for converting an existing comparison.
    expect(find.text('Pooled'), findsNWidgets(4));
    final pooledChips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
    expect(pooledChips, hasLength(4));
    expect(pooledChips.every((chip) => chip.onSelected == null), isTrue);
    expect(provider.activeSampleIdFor('residue_breakout'), 'sample-1');
    await tester.tap(find.text('Pooled').first);
    await tester.pump();
    expect(provider.activeSampleIdFor('residue_breakout'), 'sample-1');
    await tester.tap(find.byTooltip('Add Hatcher'));
    await tester.pumpAndSettle();
    await _selectMachine(tester, 0, 'H-01');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    if (find.text('Delete and continue').evaluate().isNotEmpty) {
      await tester.tap(find.text('Delete and continue'));
      await tester.pumpAndSettle();
    }

    expect(repository.addedParentId, 'house-1');
    provider.dispose();
  });
}
