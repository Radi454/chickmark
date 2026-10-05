import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/panel_sampling_state.dart';
import 'package:hatchaudit/data/models/sampling_scope.dart';
import 'package:hatchaudit/data/repositories/panel_sampling_state_repository.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/widgets/sampling_scope_controls.dart';
import 'package:provider/provider.dart';

class _MemorySamplingRepository extends PanelSamplingStateRepository {
  _MemorySamplingRepository() : super();

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
    final number = state.serialHighWatermark + 1;
    final node = SamplingNode(
      id: 'terminal-${state.nodes.length}',
      sessionId: sessionId,
      panelKey: panelKey,
      parentId: parentId,
      level: SamplingScopeLevel.tray,
      identity: identity ?? const {'code': 'Tray1'},
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a skipped pooled level keeps the nearest selected parent', (
    tester,
  ) async {
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
        child: const MaterialApp(
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
    await tester.enterText(find.byType(TextFormField), 'H2');
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
