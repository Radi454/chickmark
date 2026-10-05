import 'dart:convert';

enum SamplingScopeLevel { house, setter, hatcher, trolley, tray, sample }

String normalizeScopeIdentity(SamplingScopeLevel level, String raw) {
  final value = raw.trim().toUpperCase();
  final displayPrefix = switch (level) {
    SamplingScopeLevel.house => 'H',
    SamplingScopeLevel.setter => 'S',
    SamplingScopeLevel.hatcher => 'HT',
    SamplingScopeLevel.trolley => 'TR',
    SamplingScopeLevel.tray => 'T',
    SamplingScopeLevel.sample => '',
  };
  if (displayPrefix.isNotEmpty &&
      RegExp('^$displayPrefix[0-9]+\$').hasMatch(value)) {
    return value.substring(displayPrefix.length);
  }
  if (level == SamplingScopeLevel.tray) {
    final trayLabel = RegExp(r'^TRAY\s+([0-9]+)$').firstMatch(value);
    if (trayLabel != null) return trayLabel.group(1)!;
  }
  return value;
}

String samplingScopeSegment(SamplingScopeLevel level, String raw) {
  final prefix = switch (level) {
    SamplingScopeLevel.house => 'H',
    SamplingScopeLevel.setter => 'S',
    SamplingScopeLevel.hatcher => 'HT',
    SamplingScopeLevel.trolley => 'TR',
    SamplingScopeLevel.tray => 'T',
    SamplingScopeLevel.sample => '',
  };
  return '$prefix${normalizeScopeIdentity(level, raw)}';
}

String canonicalScopeIdentity(
  Map<String, String> identity,
  SamplingScopeLevel fallbackLevel,
) {
  final entries = identity.entries.toList()
    ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
  return entries
      .map((entry) {
        final field = entry.key.trim().toLowerCase();
        final level = switch (field) {
          'house' => SamplingScopeLevel.house,
          'setter' => SamplingScopeLevel.setter,
          'hatcher' => SamplingScopeLevel.hatcher,
          'trolley' => SamplingScopeLevel.trolley,
          'tray' => SamplingScopeLevel.tray,
          _ => fallbackLevel,
        };
        return '$field=${normalizeScopeIdentity(level, entry.value)}';
      })
      .join('&');
}

/// The scopes a panel may use, in physical hierarchy order.
class PanelSamplingConfig {
  PanelSamplingConfig({
    required this.panelKey,
    required List<SamplingScopeLevel> levels,
    required this.terminalLevel,
    required this.registeredIdentitySource,
    List<SamplingScopeLevel>? pairedLevels,
  }) : levels = List.unmodifiable(levels),
       pairedLevels = pairedLevels == null
           ? null
           : List.unmodifiable(pairedLevels) {
    if (this.pairedLevels != null &&
        (this.pairedLevels!.length < 2 ||
            !this.pairedLevels!.every(this.levels.contains))) {
      throw ArgumentError.value(pairedLevels, 'pairedLevels');
    }
    if (this.levels.toSet().length != this.levels.length) {
      throw ArgumentError.value(
        levels,
        'levels',
        'Scope levels must be unique.',
      );
    }
    if (this.levels.contains(SamplingScopeLevel.sample)) {
      throw ArgumentError.value(
        levels,
        'levels',
        'The terminal sample is not a comparison scope.',
      );
    }
    if (terminalLevel != SamplingScopeLevel.sample &&
        terminalLevel != SamplingScopeLevel.tray) {
      throw ArgumentError.value(terminalLevel, 'terminalLevel');
    }
    for (var index = 1; index < this.levels.length; index++) {
      if (this.levels[index - 1].index >= this.levels[index].index) {
        throw ArgumentError.value(
          levels,
          'levels',
          'Scope levels must follow physical order.',
        );
      }
    }
    if (terminalLevel == SamplingScopeLevel.tray &&
        !this.levels.contains(SamplingScopeLevel.tray)) {
      throw ArgumentError('Tray terminal requires Tray in configured levels.');
    }
    if (this.pairedLevels != null) {
      final first = this.levels.indexOf(this.pairedLevels!.first);
      final second = this.levels.indexOf(this.pairedLevels!.last);
      if (second != first + 1) {
        throw ArgumentError.value(
          pairedLevels,
          'pairedLevels',
          'Must be adjacent and ordered.',
        );
      }
    }
  }

  final String panelKey;
  final List<SamplingScopeLevel> levels;
  final SamplingScopeLevel terminalLevel;
  final String registeredIdentitySource;
  final List<SamplingScopeLevel>? pairedLevels;

  /// Returns the preceding configured node level, accounting for paired nodes.
  SamplingScopeLevel? parentLevelOf(SamplingScopeLevel level) {
    if (pairedLevels != null && pairedLevels!.contains(level)) {
      final firstIndex = levels.indexOf(pairedLevels!.first);
      return firstIndex <= 0 ? null : levels[firstIndex - 1];
    }
    final index = levels.indexOf(level);
    if (index <= 0) return null;
    final previous = levels[index - 1];
    if (pairedLevels != null && pairedLevels!.contains(previous)) {
      return pairedLevels!.first;
    }
    return previous;
  }

  bool get requiresTerminalIdentity => terminalLevel == SamplingScopeLevel.tray;

  void validatePath(SamplingScopePath path) {
    for (final level in const [
      SamplingScopeLevel.house,
      SamplingScopeLevel.setter,
      SamplingScopeLevel.hatcher,
      SamplingScopeLevel.trolley,
      SamplingScopeLevel.tray,
    ]) {
      if (!levels.contains(level) && path.identityFor(level) != null) {
        throw ArgumentError('Panel $panelKey does not have a $level scope.');
      }
    }
    if (requiresTerminalIdentity &&
        (path.tray == null || path.tray!.trim().isEmpty)) {
      throw ArgumentError('Panel $panelKey requires an identified Tray.');
    }
    if (!requiresTerminalIdentity && path.tray != null) {
      throw ArgumentError('Panel $panelKey does not have a Tray scope.');
    }
    if (pairedLevels != null) {
      final hasAny = pairedLevels!.any(
        (level) => path.identityFor(level) != null,
      );
      final hasAll = pairedLevels!.every((level) {
        final identity = path.identityFor(level);
        return identity != null && identity.trim().isNotEmpty;
      });
      if (hasAny && !hasAll) {
        throw ArgumentError('Panel $panelKey requires every paired identity.');
      }
    }
  }
}

class SamplingScopePath {
  SamplingScopePath({
    this.house,
    this.setter,
    this.hatcher,
    this.trolley,
    this.tray,
    required this.sampleId,
    required this.sampleNumber,
    Set<SamplingScopeLevel> unknownLevels = const {},
  }) : unknownLevels = Set.unmodifiable(unknownLevels) {
    if (sampleId.trim().isEmpty) {
      throw ArgumentError.value(sampleId, 'sampleId', 'Must not be blank.');
    }
    if (sampleNumber < 1) {
      throw ArgumentError.value(
        sampleNumber,
        'sampleNumber',
        'Must be positive.',
      );
    }
  }

  final String? house;
  final String? setter;
  final String? hatcher;
  final String? trolley;
  final String? tray;
  final String sampleId;
  final int sampleNumber;
  final Set<SamplingScopeLevel> unknownLevels;

  String? identityFor(SamplingScopeLevel level) => switch (level) {
    SamplingScopeLevel.house => house,
    SamplingScopeLevel.setter => setter,
    SamplingScopeLevel.hatcher => hatcher,
    SamplingScopeLevel.trolley => trolley,
    SamplingScopeLevel.tray => tray,
    SamplingScopeLevel.sample => sampleId,
  };

  bool pooledAt(SamplingScopeLevel level) => identityFor(level) == null;

  Map<String, Object?> toJson() => {
    'house': house,
    'setter': setter,
    'hatcher': hatcher,
    'trolley': trolley,
    'tray': tray,
    'sampleId': sampleId,
    'sampleNumber': sampleNumber,
    'unknownLevels': unknownLevels.map((level) => level.name).toList()..sort(),
  };

  String toJsonString() => jsonEncode(toJson());

  factory SamplingScopePath.fromJson(Map<String, Object?> json) {
    final unknown = (json['unknownLevels'] as List<Object?>? ?? const [])
        .map((value) => SamplingScopeLevel.values.byName(value! as String))
        .toSet();
    return SamplingScopePath(
      house: json['house'] as String?,
      setter: json['setter'] as String?,
      hatcher: json['hatcher'] as String?,
      trolley: json['trolley'] as String?,
      tray: json['tray'] as String?,
      sampleId: json['sampleId']! as String,
      sampleNumber: (json['sampleNumber']! as num).toInt(),
      unknownLevels: unknown,
    );
  }

  factory SamplingScopePath.decode(String source) =>
      SamplingScopePath.fromJson(jsonDecode(source) as Map<String, Object?>);
}

class SamplingNode {
  SamplingNode({
    required this.id,
    required this.sessionId,
    required this.panelKey,
    String? parentId,
    required this.level,
    String? identityKey,
    Map<String, String> identity = const {},
    this.sampleId,
    this.sampleNumber,
    this.createdAt,
    this.updatedAt,
  }) : parentId = parentId == null || parentId.trim().isEmpty ? null : parentId,
       identityKey = identityKey == null || identityKey.trim().isEmpty
           ? null
           : identityKey,
       identity = Map.unmodifiable(identity) {
    if (id.trim().isEmpty ||
        sessionId.trim().isEmpty ||
        panelKey.trim().isEmpty) {
      throw ArgumentError(
        'Sampling node id, session, and panel must not be blank.',
      );
    }
    if (sampleId != null && sampleId!.trim().isEmpty) {
      throw ArgumentError.value(sampleId, 'sampleId', 'Must not be blank.');
    }
    if (sampleNumber != null && sampleNumber! < 1) {
      throw ArgumentError.value(
        sampleNumber,
        'sampleNumber',
        'Must be positive.',
      );
    }
  }

  final String id;
  final String sessionId;
  final String panelKey;
  final String? parentId;
  final SamplingScopeLevel level;
  final String? identityKey;
  final Map<String, String> identity;
  final String? sampleId;
  final int? sampleNumber;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// JSON string retained for storage rows that historically used this field.
  String? get identityJson => identity.isEmpty ? null : jsonEncode(identity);

  SamplingNode copyWith({
    String? identityKey,
    Map<String, String>? identity,
    String? sampleId,
    int? sampleNumber,
    String? parentId,
    bool clearParentId = false,
    DateTime? updatedAt,
  }) => SamplingNode(
    id: id,
    sessionId: sessionId,
    panelKey: panelKey,
    parentId: clearParentId ? null : (parentId ?? this.parentId),
    level: level,
    identityKey: identityKey ?? this.identityKey,
    identity: identity ?? this.identity,
    sampleId: sampleId ?? this.sampleId,
    sampleNumber: sampleNumber ?? this.sampleNumber,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'sessionId': sessionId,
    'panelKey': panelKey,
    'parentId': parentId ?? '',
    'level': level.name,
    'identityKey': identityKey ?? identity['code'] ?? '',
    'identityJson': identityJson,
    'sampleId': sampleId,
    'sampleNumber': sampleNumber,
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory SamplingNode.fromMap(Map<String, Object?> row) {
    final rawIdentity = row['identity'];
    final rawJson = row['identityJson'] as String?;
    final decoded = rawIdentity is Map
        ? rawIdentity
        : rawJson == null || rawJson.trim().isEmpty
        ? const <Object?, Object?>{}
        : jsonDecode(rawJson) as Map<Object?, Object?>;
    return SamplingNode(
      id: row['id']! as String,
      sessionId: row['sessionId']! as String,
      panelKey: row['panelKey']! as String,
      parentId: _nullableString(row['parentId']),
      level: SamplingScopeLevel.values.byName(row['level']! as String),
      identityKey:
          _nullableString(row['identityKey']) ??
          (decoded['code']?.toString().trim().isNotEmpty == true
              ? decoded['code'].toString()
              : null),
      identity: decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
      sampleId: row['sampleId'] as String?,
      sampleNumber: (row['sampleNumber'] as num?)?.toInt(),
      createdAt: _dateTime(row['createdAt']),
      updatedAt: _dateTime(row['updatedAt']),
    );
  }

  static DateTime? _dateTime(Object? value) =>
      value == null ? null : DateTime.parse(value as String);

  static String? _nullableString(Object? value) {
    if (value == null) return null;
    final normalized = value as String;
    return normalized.trim().isEmpty ? null : normalized;
  }
}

class SamplingDeletePreview {
  const SamplingDeletePreview({
    required this.nodeId,
    required this.scopeLabel,
    required this.descendantCount,
    required this.measurementCount,
    required this.photoCount,
    required this.noteCount,
  });

  final String nodeId;
  final String scopeLabel;
  final int descendantCount;
  final int measurementCount;
  final int photoCount;
  final int noteCount;
}

const samplingBreedAbbreviations = <String, String>{
  'Ross308': 'RS',
  'Arbo': 'AR',
  'Avian': 'AV',
  'Cobb500': 'CB',
  'Hubbard': 'HB',
  'IR': 'IR',
};
