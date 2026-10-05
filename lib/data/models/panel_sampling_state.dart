import 'sampling_scope.dart';

class PanelSamplingState {
  PanelSamplingState({
    required this.sessionId,
    required this.panelKey,
    required List<SamplingNode> nodes,
    required this.serialHighWatermark,
    required this.activeSampleId,
  }) : nodes = List.unmodifiable(nodes) {
    if (this.nodes.any(
      (node) => node.sessionId != sessionId || node.panelKey != panelKey,
    )) {
      throw ArgumentError(
        'Sampling nodes must belong to the state session and panel.',
      );
    }
    final ids = this.nodes.map((node) => node.id).toSet();
    if (ids.length != this.nodes.length) {
      throw ArgumentError('Sampling node ids must be unique.');
    }
  }

  final String sessionId;
  final String panelKey;
  final List<SamplingNode> nodes;
  final int serialHighWatermark;
  final String activeSampleId;

  List<SamplingNode> get samples {
    final parents = nodes
        .map((node) => node.parentId)
        .whereType<String>()
        .toSet();
    return List.unmodifiable(
      nodes.where(
        (node) => node.sampleId != null && !parents.contains(node.id),
      ),
    );
  }

  String? get resolvedActiveSampleId {
    if (samples.any((sample) => sample.sampleId == activeSampleId)) {
      return activeSampleId;
    }
    final ordered = [...samples]
      ..sort((a, b) {
        final numberOrder = (a.sampleNumber ?? 0).compareTo(
          b.sampleNumber ?? 0,
        );
        return numberOrder == 0
            ? a.sampleId!.compareTo(b.sampleId!)
            : numberOrder;
      });
    return ordered.isEmpty ? null : ordered.first.sampleId;
  }

  List<SamplingNode> childrenOf(String? parentId, SamplingScopeLevel level) =>
      List.unmodifiable(
        nodes.where((node) => node.parentId == parentId && node.level == level),
      );

  bool isComparisonAt({
    required String? parentId,
    required SamplingScopeLevel level,
  }) => nodes.any((node) => node.parentId == parentId && node.level == level);

  bool hasIdentityUnderParent({
    required String? parentId,
    required SamplingScopeLevel level,
    required Map<String, String> identity,
  }) => nodes.any(
    (node) =>
        node.parentId == parentId &&
        node.level == level &&
        canonicalScopeIdentity(
              node.identity.isNotEmpty
                  ? node.identity
                  : {'code': node.identityKey ?? ''},
              level,
            ) ==
            canonicalScopeIdentity(identity, level),
  );

  SamplingScopePath pathFor(String sampleId) {
    SamplingNode? current;
    for (final node in samples) {
      if (node.sampleId == sampleId) {
        current = node;
        break;
      }
    }
    if (current == null) {
      throw StateError('No terminal sample with id "$sampleId" exists.');
    }
    final sample = current;
    if (sample.sampleNumber == null) {
      throw StateError('Sample "$sampleId" has no serial number.');
    }

    final chain = <SamplingNode>[];
    final visited = <String>{};
    while (current != null) {
      if (!visited.add(current.id)) {
        throw StateError(
          'Sampling tree contains a parent cycle at ${current.id}.',
        );
      }
      chain.add(current);
      final parentId = current.parentId;
      if (parentId == null) break;
      SamplingNode? parent;
      for (final candidate in nodes) {
        if (candidate.id == parentId) {
          parent = candidate;
          break;
        }
      }
      if (parent == null ||
          parent.sessionId != sessionId ||
          parent.panelKey != panelKey) {
        throw StateError('Sampling node ${current.id} has a dangling parent.');
      }
      current = parent;
    }

    String? house;
    String? setter;
    String? hatcher;
    String? trolley;
    String? tray;
    final unknown = <SamplingScopeLevel>{};
    for (final node in chain.reversed) {
      switch (node.level) {
        case SamplingScopeLevel.house:
          house = _identityValue(node);
        case SamplingScopeLevel.setter:
          setter =
              _pairedValue(node, SamplingScopeLevel.setter) ??
              _identityValue(node);
          hatcher = _pairedValue(node, SamplingScopeLevel.hatcher) ?? hatcher;
        case SamplingScopeLevel.hatcher:
          hatcher =
              _pairedValue(node, SamplingScopeLevel.hatcher) ??
              _identityValue(node);
          setter = _pairedValue(node, SamplingScopeLevel.setter) ?? setter;
        case SamplingScopeLevel.trolley:
          trolley = _identityValue(node);
        case SamplingScopeLevel.tray:
          tray = _identityValue(node);
        case SamplingScopeLevel.sample:
          break;
      }
      final unknownValue = node.identity['_unknownLevels'];
      if (unknownValue != null) {
        for (final name in unknownValue.split(',')) {
          final matching = SamplingScopeLevel.values.where(
            (level) => level.name == name,
          );
          if (matching.isNotEmpty) unknown.add(matching.first);
        }
      }
    }
    return SamplingScopePath(
      house: house,
      setter: setter,
      hatcher: hatcher,
      trolley: trolley,
      tray: tray,
      sampleId: sample.sampleId!,
      sampleNumber: sample.sampleNumber!,
      unknownLevels: unknown,
    );
  }

  bool pooledAt(String sampleId, SamplingScopeLevel level) =>
      pathFor(sampleId).pooledAt(level);

  static String? _pairedValue(SamplingNode node, SamplingScopeLevel level) =>
      node.identity[level.name];

  static String? _identityValue(SamplingNode node) =>
      node.identity['code'] ?? node.identityKey;
}
