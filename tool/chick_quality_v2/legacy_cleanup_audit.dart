import 'dart:convert';
import 'dart:io';

class CleanupEvidenceGate {
  const CleanupEvidenceGate({required this.proven, required this.reason});

  final bool proven;
  final String reason;
}

class LegacyCompatibilityReference {
  const LegacyCompatibilityReference({
    required this.path,
    required this.line,
    required this.token,
  });

  final String path;
  final int line;
  final String token;
}

class LegacyCleanupAuditResult {
  const LegacyCleanupAuditResult({
    required this.compatibilityTokens,
    required this.tokenMentions,
    required this.registryDrivenConsumers,
    required this.runtimeReaderInventoryComplete,
    required this.persistedReplacementCoverage,
    required this.backwardCompatibilityReleased,
    required this.losslessMigrationReady,
  });

  final List<String> compatibilityTokens;
  final List<LegacyCompatibilityReference> tokenMentions;
  final List<String> registryDrivenConsumers;
  final CleanupEvidenceGate runtimeReaderInventoryComplete;
  final CleanupEvidenceGate persistedReplacementCoverage;
  final CleanupEvidenceGate backwardCompatibilityReleased;
  final CleanupEvidenceGate losslessMigrationReady;

  bool get zeroRuntimeReadersProven =>
      tokenMentions.isEmpty &&
      registryDrivenConsumers.isEmpty &&
      runtimeReaderInventoryComplete.proven;

  bool get removalEligible =>
      zeroRuntimeReadersProven &&
      persistedReplacementCoverage.proven &&
      backwardCompatibilityReleased.proven &&
      losslessMigrationReady.proven;

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Chick Quality V2 Phase 5 Cleanup Audit')
      ..writeln()
      ..writeln(
        'This report is generated from the canonical station registry, '
        'conservative production-source search evidence, and the checked-in '
        'cleanup evidence.',
      )
      ..writeln()
      ..writeln('## Decision')
      ..writeln()
      ..writeln(
        removalEligible
            ? '**REMOVE ELIGIBLE** — every approved safety gate is proven.'
            : '**RETAIN** — no compatibility structures were removed.',
      )
      ..writeln()
      ..writeln('## Safety gates')
      ..writeln()
      ..writeln('| Gate | Proven | Evidence |')
      ..writeln('| --- | --- | --- |')
      ..writeln(
        '| Zero production runtime readers/writers proven | '
        '${zeroRuntimeReadersProven ? 'yes' : 'no'} | '
        '${tokenMentions.length} conservative token mention(s) and '
        '${registryDrivenConsumers.length} heuristically detected registry-'
        'driven consumer(s) found. Inventory completeness: '
        '${_yesNo(runtimeReaderInventoryComplete.proven)} — '
        '${_escapeCell(runtimeReaderInventoryComplete.reason)} |',
      )
      ..writeln(
        '| Every persisted row has a safe V2 replacement | '
        '${_yesNo(persistedReplacementCoverage.proven)} | '
        '${_escapeCell(persistedReplacementCoverage.reason)} |',
      )
      ..writeln(
        '| Backward compatibility has been released | '
        '${_yesNo(backwardCompatibilityReleased.proven)} | '
        '${_escapeCell(backwardCompatibilityReleased.reason)} |',
      )
      ..writeln(
        '| A lossless local/cloud removal migration is ready | '
        '${_yesNo(losslessMigrationReady.proven)} | '
        '${_escapeCell(losslessMigrationReady.reason)} |',
      )
      ..writeln()
      ..writeln('## Registry-derived compatibility vocabulary')
      ..writeln();
    for (final token in compatibilityTokens) {
      buffer.writeln('- `$token`');
    }
    buffer
      ..writeln()
      ..writeln('## Heuristically detected registry-driven consumers')
      ..writeln();
    if (registryDrivenConsumers.isEmpty) {
      buffer.writeln('No registry-driven compatibility consumers were found.');
    } else {
      for (final path in registryDrivenConsumers) {
        buffer.writeln('- `$path`');
      }
    }
    buffer
      ..writeln()
      ..writeln('## Conservative production token mentions')
      ..writeln()
      ..writeln(
        'These lexical mentions are cleanup blockers, not claims that every '
        'line is a Chick reader or writer. Comments, writes, and unrelated '
        'domains can appear here; a future cleanup must classify and eliminate '
        'them before the zero-reader proof can pass.',
      )
      ..writeln();
    if (tokenMentions.isEmpty) {
      buffer.writeln('No compatibility-token mentions were found.');
      return buffer.toString();
    }
    String? currentPath;
    for (final reference in tokenMentions) {
      if (reference.path != currentPath) {
        if (currentPath != null) buffer.writeln();
        currentPath = reference.path;
        buffer.writeln('### `${reference.path}`');
        buffer.writeln();
      }
      buffer.writeln('- line ${reference.line}: `${reference.token}`');
    }
    return buffer.toString();
  }

  static String _yesNo(bool value) => value ? 'yes' : 'no';

  static String _escapeCell(String value) =>
      value.replaceAll('|', r'\|').replaceAll('\n', ' ');
}

Future<LegacyCleanupAuditResult> auditLegacyCleanup({
  required Directory repositoryRoot,
  required File registryFile,
  required File evidenceFile,
}) async {
  final registry = _decodeObject(await registryFile.readAsString(), 'registry');
  final evidence = _decodeObject(await evidenceFile.readAsString(), 'evidence');
  final tokens = _compatibilityTokens(registry);
  final inventory = await _runtimeInventory(repositoryRoot, tokens);

  return LegacyCleanupAuditResult(
    compatibilityTokens: List.unmodifiable(tokens),
    tokenMentions: List.unmodifiable(inventory.tokenMentions),
    registryDrivenConsumers: List.unmodifiable(
      inventory.registryDrivenConsumers,
    ),
    runtimeReaderInventoryComplete: _evidenceGate(
      evidence,
      'runtimeReaderInventoryComplete',
    ),
    persistedReplacementCoverage: _evidenceGate(
      evidence,
      'persistedReplacementCoverage',
    ),
    backwardCompatibilityReleased: _evidenceGate(
      evidence,
      'backwardCompatibilityReleased',
    ),
    losslessMigrationReady: _evidenceGate(evidence, 'losslessMigrationReady'),
  );
}

Map<String, Object?> _decodeObject(String source, String label) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, Object?>) {
    throw FormatException('$label must be a JSON object');
  }
  return decoded;
}

List<String> _compatibilityTokens(Map<String, Object?> registry) {
  final stations = registry['stations'];
  if (stations is! List<Object?>) {
    throw const FormatException('registry.stations must be an array');
  }
  final tokens = <String>{'chicks.legacy_combined'};
  for (final rawStation in stations) {
    if (rawStation is! Map<String, Object?>) continue;
    final schemaKey = rawStation['schemaKey'];
    if (schemaKey is! String || !schemaKey.startsWith('chicks.')) continue;
    final fields = rawStation['fields'];
    if (fields is List<Object?>) {
      for (final rawField in fields) {
        if (rawField is! Map<String, Object?> ||
            rawField['observation'] is! Map<String, Object?>) {
          continue;
        }
        _addToken(tokens, rawField['fieldKey']);
        _addPersistenceTokens(tokens, rawField['persistence']);
      }
    }
    final calculations = rawStation['calculations'];
    if (calculations is List<Object?>) {
      for (final rawCalculation in calculations) {
        if (rawCalculation is! Map<String, Object?>) continue;
        _addToken(tokens, rawCalculation['fieldKey']);
        _addPersistenceTokens(tokens, rawCalculation['persistence']);
      }
    }
  }
  final sorted = tokens.toList()..sort();
  return sorted;
}

void _addToken(Set<String> tokens, Object? value) {
  if (value is String && value.trim().isNotEmpty) tokens.add(value);
}

void _addPersistenceTokens(Set<String> tokens, Object? rawPersistence) {
  if (rawPersistence is! Map<String, Object?>) return;
  _addToken(tokens, rawPersistence['localColumn']);
  _addToken(tokens, rawPersistence['remoteColumn']);
}

CleanupEvidenceGate _evidenceGate(Map<String, Object?> evidence, String key) {
  final raw = evidence[key];
  if (raw is! Map<String, Object?> ||
      raw['proven'] is! bool ||
      raw['reason'] is! String ||
      (raw['reason'] as String).trim().isEmpty) {
    throw FormatException(
      'evidence.$key requires boolean proven and non-empty reason',
    );
  }
  return CleanupEvidenceGate(
    proven: raw['proven'] as bool,
    reason: raw['reason'] as String,
  );
}

class _RuntimeInventory {
  const _RuntimeInventory({
    required this.tokenMentions,
    required this.registryDrivenConsumers,
  });

  final List<LegacyCompatibilityReference> tokenMentions;
  final List<String> registryDrivenConsumers;
}

Future<_RuntimeInventory> _runtimeInventory(
  Directory root,
  List<String> tokens,
) async {
  final tokenMentions = <LegacyCompatibilityReference>[];
  final registryDrivenConsumers = <String>[];
  for (final relativeRoot in const ['lib', 'supabase/functions']) {
    final sourceRoot = Directory('${root.path}/$relativeRoot');
    if (!sourceRoot.existsSync()) continue;
    await for (final entity in sourceRoot.list(recursive: true)) {
      if (entity is! File || !_isRuntimeSource(root, entity)) continue;
      final relativePath = _relativePath(root, entity);
      final source = await entity.readAsString();
      if (_isRegistryDrivenConsumer(source)) {
        registryDrivenConsumers.add(relativePath);
      }
      final lines = const LineSplitter().convert(source);
      for (var index = 0; index < lines.length; index++) {
        for (final token in tokens) {
          if (_containsToken(lines[index], token)) {
            tokenMentions.add(
              LegacyCompatibilityReference(
                path: relativePath,
                line: index + 1,
                token: token,
              ),
            );
          }
        }
      }
    }
  }
  tokenMentions.sort((left, right) {
    final byPath = left.path.compareTo(right.path);
    if (byPath != 0) return byPath;
    final byLine = left.line.compareTo(right.line);
    if (byLine != 0) return byLine;
    return left.token.compareTo(right.token);
  });
  registryDrivenConsumers.sort();
  return _RuntimeInventory(
    tokenMentions: tokenMentions,
    registryDrivenConsumers: registryDrivenConsumers,
  );
}

bool _isRegistryDrivenConsumer(String source) {
  final readsFields = source.contains('schema.fields');
  final readsCalculations = source.contains('schema.calculations');
  final readsPersistence =
      source.contains('field.persistence') ||
      source.contains('calculation.persistence');
  final readsColumnName =
      source.contains('localColumn') || source.contains('remoteColumn');
  return (readsFields || readsCalculations) &&
      readsPersistence &&
      readsColumnName;
}

bool _containsToken(String line, String token) {
  var start = 0;
  while (true) {
    final match = line.indexOf(token, start);
    if (match < 0) return false;
    final beforeIsIdentifier =
        match > 0 && _isIdentifierCharacterAt(line, match - 1);
    final after = match + token.length;
    final afterIsIdentifier =
        after < line.length && _isIdentifierCharacterAt(line, after);
    if (!beforeIsIdentifier && !afterIsIdentifier) return true;
    start = match + 1;
  }
}

final _unicodeIdentifierCharacter = RegExp(
  r'^[\p{L}\p{M}\p{N}\p{Pc}]$',
  unicode: true,
);

bool _isIdentifierCharacterAt(String source, int codeUnitIndex) {
  final codeUnit = source.codeUnitAt(codeUnitIndex);
  if ((codeUnit >= 48 && codeUnit <= 57) ||
      (codeUnit >= 65 && codeUnit <= 90) ||
      codeUnit == 36 ||
      codeUnit == 95 ||
      (codeUnit >= 97 && codeUnit <= 122)) {
    return true;
  }
  var start = codeUnitIndex;
  var end = codeUnitIndex + 1;
  if (codeUnit >= 0xDC00 && codeUnit <= 0xDFFF && codeUnitIndex > 0) {
    start--;
  } else if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF && end < source.length) {
    end++;
  }
  return _unicodeIdentifierCharacter.hasMatch(source.substring(start, end));
}

bool _isRuntimeSource(Directory root, File file) {
  final path = _relativePath(root, file);
  if (!(path.endsWith('.dart') || path.endsWith('.ts'))) return false;
  final name = path.split('/').last;
  if (name.endsWith('_test.dart') || name.endsWith('_test.ts')) return false;
  return path != 'lib/data/agent/station_registry.g.dart' &&
      path != 'supabase/functions/_shared/station_registry.generated.ts';
}

String _relativePath(Directory root, File file) {
  final rootPrefix = root.absolute.path.endsWith(Platform.pathSeparator)
      ? root.absolute.path
      : '${root.absolute.path}${Platform.pathSeparator}';
  return file.absolute.path
      .substring(rootPrefix.length)
      .replaceAll(Platform.pathSeparator, '/');
}
