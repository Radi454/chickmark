import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hatchaudit/l10n/app_localizations.dart';
import 'package:hatchaudit/core/theme/app_theme.dart';
import 'package:hatchaudit/data/models/hatchery_machine_model.dart';
import 'package:hatchaudit/data/models/panel_sampling_state.dart';
import 'package:hatchaudit/data/repositories/hatchery_machine_repository.dart';
import 'package:hatchaudit/data/models/sampling_scope.dart';
import 'package:hatchaudit/data/repositories/panel_sampling_state_repository.dart';
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
              child: SamplingScopeControls(
                panelKey: 'residue_breakout',
                machineRepository: _MemoryMachineRepository([]),
              ),
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
    expect(find.byType(InputChip), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byTooltip('Sampling actions'), findsOneWidget);
    final selectedScope = tester.widget<Semantics>(
      find.byKey(const ValueKey('sampling-node-house-1')),
    );
    expect(selectedScope.properties.selected, isTrue);
    expect(find.text('Selected sample: SA1'), findsOneWidget);
    expect(find.text('Add House'), findsOneWidget);
    expect(tester.takeException(), isNull);
    provider.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('navigator selects trays and confirms removal through actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _MemorySamplingRepository();
    repository.state = PanelSamplingState(
      sessionId: 'session-1',
      panelKey: 'residue_breakout',
      serialHighWatermark: 2,
      activeSampleId: 'sample-1',
      nodes: [
        ...repository.state.nodes,
        SamplingNode(
          id: 'tray-2',
          sessionId: 'session-1',
          panelKey: 'residue_breakout',
          parentId: 'house-1',
          level: SamplingScopeLevel.tray,
          identityKey: 'T2',
          identity: const {'code': 'T2'},
          sampleId: 'sample-2',
          sampleNumber: 2,
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
            date: '2026-10-07',
          ),
          sessionId: 'session-1',
          notify: false,
        );
    addTearDown(provider.dispose);
    Widget app(TextDirection direction) => ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: Locale(direction == TextDirection.rtl ? 'ar' : 'en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: SingleChildScrollView(
              child: SamplingScopeControls(
                panelKey: 'residue_breakout',
                machineRepository: _MemoryMachineRepository([]),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(app(TextDirection.ltr));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    final house = find.byKey(const ValueKey('sampling-node-house-1'));
    final tray = find.byKey(const ValueKey('sampling-node-tray-2'));
    expect(
      tester.getTopLeft(tray).dx,
      greaterThan(tester.getTopRight(house).dx),
    );
    await tester.tap(tray);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(provider.activeSampleIdFor('residue_breakout'), 'sample-2');
    expect(find.text('Selected sample: SA2'), findsOneWidget);
    await tester.tap(find.byTooltip('Sampling actions'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('sampling-remove-tray-2')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Delete H1?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(provider.activeSampleIdFor('residue_breakout'), 'sample-2');
    tester.view.physicalSize = const Size(320, 1200);
    await tester.pumpWidget(app(TextDirection.rtl));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(
      tester.getTopLeft(tray).dy,
      greaterThan(tester.getBottomLeft(house).dy),
    );
    expect(find.byTooltip('إجراءات أخذ العينات'), findsOneWidget);
    provider.setEditMode(false);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sampling-node-tray-1')));
    await tester.pump();
    expect(provider.activeSampleIdFor('residue_breakout'), 'sample-2');
    expect(
      tester
          .widget<PopupMenuButton<(SamplingNode, bool)>>(
            find.byType(PopupMenuButton<(SamplingNode, bool)>),
          )
          .enabled,
      isFalse,
    );
    expect(tester.takeException(), isNull);
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
          home: Scaffold(
            body: SingleChildScrollView(
              child: SamplingScopeControls(
                panelKey: 'hatcher_optimizing',
                machineRepository: _MemoryMachineRepository([]),
              ),
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
    // empty scopes keep an inert Pooled label rather than a control for
    // converting an existing comparison.
    expect(find.text('Pooled'), findsNWidgets(3));
    expect(find.byType(ChoiceChip), findsNothing);
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
