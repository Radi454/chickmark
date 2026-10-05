import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/data/models/panel_sampling_state.dart';
import 'package:hatchaudit/data/models/sampling_scope.dart';
import 'package:hatchaudit/data/repositories/panel_sampling_state_repository.dart';

/// Small deterministic scope-tree fake for station screen widget tests. The
/// real SQLite persistence and reopen behavior is covered by repository tests.
class MemoryPanelSamplingStateRepository extends PanelSamplingStateRepository {
  MemoryPanelSamplingStateRepository() : super();

  final Map<String, PanelSamplingState> _states = {};
  int _nextId = 0;

  String _key(String sessionId, String panelKey) => '$sessionId::$panelKey';

  @override
  Future<PanelSamplingState> loadOrCreateDefault({
    required String sessionId,
    required String panelKey,
  }) async {
    return _states.putIfAbsent(
      _key(sessionId, panelKey),
      () => _defaultState(sessionId, panelKey, serial: 1),
    );
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
    var state = await loadOrCreateDefault(
      sessionId: sessionId,
      panelKey: panelKey,
    );
    final config = PanelSampleSchema.samplingConfigFor(panelKey);
    final terminal = level == config.terminalLevel;
    final serial = state.serialHighWatermark + 1;
    final normalized = Map<String, String>.unmodifiable(identity);
    if (state.nodes.any(
      (node) =>
          node.parentId == parentId &&
          node.level == level &&
          node.identity.toString() == normalized.toString(),
    )) {
      throw ArgumentError('That scope identity already exists under this parent.');
    }
    var nodes = [...state.nodes];
    if (!terminal && level != SamplingScopeLevel.tray) {
      nodes.removeWhere(
        (node) =>
            node.parentId == parentId &&
            node.level == SamplingScopeLevel.sample &&
            node.identity.isEmpty,
      );
    }
    final node = SamplingNode(
      id: 'node-${_nextId++}',
      sessionId: sessionId,
      panelKey: panelKey,
      parentId: parentId,
      level: level,
      identityKey: normalized.values.join('|'),
      identity: normalized,
      sampleId: terminal ? 'sample-$serial' : null,
      sampleNumber: terminal ? serial : null,
    );
    nodes.add(node);
    state = PanelSamplingState(
      sessionId: sessionId,
      panelKey: panelKey,
      nodes: nodes,
      serialHighWatermark: serial,
      activeSampleId: node.sampleId ?? state.activeSampleId,
    );
    _states[_key(sessionId, panelKey)] = state;
    return node;
  }

  @override
  Future<SamplingNode> addTerminalSample({
    required String sessionId,
    required String panelKey,
    required String? parentId,
    Map<String, String>? identity,
  }) async {
    final state = await loadOrCreateDefault(
      sessionId: sessionId,
      panelKey: panelKey,
    );
    final serial = state.serialHighWatermark + 1;
    final node = SamplingNode(
      id: 'node-${_nextId++}',
      sessionId: sessionId,
      panelKey: panelKey,
      parentId: parentId,
      level: PanelSampleSchema.samplingConfigFor(panelKey).terminalLevel,
      identity: identity ?? const {},
      identityKey: identity?.values.join('|'),
      sampleId: 'sample-$serial',
      sampleNumber: serial,
    );
    _states[_key(sessionId, panelKey)] = PanelSamplingState(
      sessionId: sessionId,
      panelKey: panelKey,
      nodes: [...state.nodes, node],
      serialHighWatermark: serial,
      activeSampleId: node.sampleId!,
    );
    return node;
  }

  @override
  Future<void> updateScopeIdentity({
    required String nodeId,
    required Map<String, String> identity,
  }) async {
    for (final entry in _states.entries) {
      final index = entry.value.nodes.indexWhere((node) => node.id == nodeId);
      if (index < 0) continue;
      final nodes = [...entry.value.nodes];
      nodes[index] = nodes[index].copyWith(
        identity: identity,
        identityKey: identity.values.join('|'),
      );
      _states[entry.key] = PanelSamplingState(
        sessionId: entry.value.sessionId,
        panelKey: entry.value.panelKey,
        nodes: nodes,
        serialHighWatermark: entry.value.serialHighWatermark,
        activeSampleId: entry.value.activeSampleId,
      );
      return;
    }
  }

  @override
  Future<SamplingDeletePreview> previewDeleteSubtree({
    required String nodeId,
  }) async => SamplingDeletePreview(
    nodeId: nodeId,
    scopeLabel: 'scope',
    descendantCount: 1,
    measurementCount: 0,
    photoCount: 0,
    noteCount: 0,
  );

  @override
  Future<void> deleteSubtree({required String nodeId}) async {
    for (final entry in _states.entries) {
      final state = entry.value;
      if (!state.nodes.any((node) => node.id == nodeId)) continue;
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
      var nodes = state.nodes.where((node) => !removed.contains(node.id)).toList();
      var active = state.activeSampleId;
      if (nodes.where((node) => node.sampleId != null).isEmpty) {
        final fallback = _defaultState(
          state.sessionId,
          state.panelKey,
          serial: state.serialHighWatermark + 1,
        );
        nodes = [...nodes, ...fallback.nodes];
        active = fallback.activeSampleId;
      }
      _states[entry.key] = PanelSamplingState(
        sessionId: state.sessionId,
        panelKey: state.panelKey,
        nodes: nodes,
        serialHighWatermark: state.serialHighWatermark + 1,
        activeSampleId: active,
      );
      return;
    }
  }

  PanelSamplingState _defaultState(
    String sessionId,
    String panelKey, {
    required int serial,
  }) {
    final config = PanelSampleSchema.samplingConfigFor(panelKey);
    final isTray = config.terminalLevel == SamplingScopeLevel.tray;
    final sampleId = '$panelKey-default-$serial';
    final node = SamplingNode(
      id: 'node-${_nextId++}',
      sessionId: sessionId,
      panelKey: panelKey,
      level: config.terminalLevel,
      identity: isTray ? const {'code': 'Tray1'} : const {},
      identityKey: isTray ? 'Tray1' : null,
      sampleId: sampleId,
      sampleNumber: serial,
    );
    return PanelSamplingState(
      sessionId: sessionId,
      panelKey: panelKey,
      nodes: [node],
      serialHighWatermark: serial,
      activeSampleId: sampleId,
    );
  }
}
