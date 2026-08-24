import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/chick_quality_v2/legacy_cleanup_audit.dart';

void main() {
  test('runtime compatibility reader blocks cleanup', () async {
    final fixture = await _AuditFixture.create(
      runtimeSource: "final weights = row['weightsJson'];",
    );
    addTearDown(fixture.dispose);

    final result = await fixture.audit();

    expect(result.zeroRuntimeReadersProven, isFalse);
    expect(result.removalEligible, isFalse);
    expect(result.tokenMentions, hasLength(1));
    expect(result.tokenMentions.single.token, 'weightsJson');
    expect(result.tokenMentions.single.path, 'lib/runtime_reader.dart');
    expect(result.tokenMentions.single.line, 1);
  });

  test('all four independent proofs permit cleanup', () async {
    final fixture = await _AuditFixture.create(
      runtimeSource: 'final normalized = observations;',
    );
    addTearDown(fixture.dispose);

    final result = await fixture.audit();

    expect(result.zeroRuntimeReadersProven, isTrue);
    expect(result.persistedReplacementCoverage.proven, isTrue);
    expect(result.backwardCompatibilityReleased.proven, isTrue);
    expect(result.losslessMigrationReady.proven, isTrue);
    expect(result.removalEligible, isTrue);
  });

  test('unproven non-code gate blocks removal with zero readers', () async {
    final fixture = await _AuditFixture.create(
      runtimeSource: 'final normalized = observations;',
      replacementProven: false,
    );
    addTearDown(fixture.dispose);

    final result = await fixture.audit();

    expect(result.zeroRuntimeReadersProven, isTrue);
    expect(result.persistedReplacementCoverage.proven, isFalse);
    expect(result.removalEligible, isFalse);
  });

  test('derived compatibility cache reader also blocks cleanup', () async {
    final fixture = await _AuditFixture.create(
      runtimeSource: "final average = row['avgWeight'];",
    );
    addTearDown(fixture.dispose);

    final result = await fixture.audit();

    expect(result.tokenMentions, hasLength(1));
    expect(result.tokenMentions.single.token, 'avgWeight');
    expect(result.removalEligible, isFalse);
  });

  test('compatibility tokens do not match inside longer identifiers', () async {
    final fixture = await _AuditFixture.create(
      runtimeSource: r'''
final ascii = row['prefixavgWeightSuffix'];
final dollar = row['avgWeight$cache'];
final unicode = row['avgWeightبيانات'];
''',
    );
    addTearDown(fixture.dispose);

    final result = await fixture.audit();

    expect(result.tokenMentions, isEmpty);
  });

  test(
    'only exact registry definitions are excluded from token mentions',
    () async {
      final fixture = await _AuditFixture.create(
        runtimeSource: 'final normalized = observations;',
        extraSources: const {
          'test/runtime_reader_test.dart': "row['weightsJson'];",
          'docs/compatibility.md': 'weightsJson',
          'lib/data/agent/station_registry.g.dart': 'weightsJson',
          'supabase/functions/_shared/station_registry.generated.ts':
              'weightsJson',
          'lib/generated_compatibility_serializer.g.dart': 'weightsJson',
        },
      );
      addTearDown(fixture.dispose);

      final result = await fixture.audit();

      expect(result.tokenMentions, hasLength(1));
      expect(
        result.tokenMentions.single.path,
        'lib/generated_compatibility_serializer.g.dart',
      );
      expect(result.removalEligible, isFalse);
    },
  );

  test('generated registry driven adapter blocks zero-reader proof', () async {
    final fixture = await _AuditFixture.create(
      runtimeSource: 'final normalized = observations;',
      extraSources: const {
        'lib/data/agent/station_registry.g.dart': 'weightsJson',
        'lib/dynamic_adapter.dart': '''
for (final field in schema.fields) {
  final column = field.persistence['localColumn'];
  result[field.fieldKey] = row[column];
}
''',
      },
    );
    addTearDown(fixture.dispose);

    final result = await fixture.audit();

    expect(result.tokenMentions, isEmpty);
    expect(result.registryDrivenConsumers, ['lib/dynamic_adapter.dart']);
    expect(result.zeroRuntimeReadersProven, isFalse);
    expect(result.removalEligible, isFalse);
  });

  test(
    'indirect reader stays blocked until inventory completeness is proven',
    () async {
      final fixture = await _AuditFixture.create(
        runtimeSource: '''
return AgentStationAdapter.fieldValuesFromLocalRow(schema, row);
''',
        runtimeInventoryComplete: false,
      );
      addTearDown(fixture.dispose);

      final result = await fixture.audit();

      expect(result.tokenMentions, isEmpty);
      expect(result.registryDrivenConsumers, isEmpty);
      expect(result.runtimeReaderInventoryComplete.proven, isFalse);
      expect(result.zeroRuntimeReadersProven, isFalse);
      expect(result.removalEligible, isFalse);
    },
  );

  test(
    'comments writers and unrelated domains stay conservative mentions',
    () async {
      final fixture = await _AuditFixture.create(
        runtimeSource: '''
// avgWeight remains a compatibility candidate.
row['weightsJson'] = encoded;
final eggSampleSize = eggRow['sampleSize'];
''',
      );
      addTearDown(fixture.dispose);

      final result = await fixture.audit();

      expect(result.tokenMentions.map((mention) => mention.token), [
        'avgWeight',
        'weightsJson',
        'sampleSize',
      ]);
      expect(result.zeroRuntimeReadersProven, isFalse);
    },
  );

  test(
    'checked-in cleanup report matches the current repository audit',
    () async {
      final process = await Process.run('dart', const [
        'run',
        'tool/chick_quality_v2/audit_legacy_cleanup.dart',
        '--check',
      ], workingDirectory: Directory.current.path);

      expect(
        process.exitCode,
        0,
        reason: '${process.stdout}\n${process.stderr}',
      );
    },
  );
}

class _AuditFixture {
  _AuditFixture(this.root);

  final Directory root;

  File get registryFile =>
      File('${root.path}/tool/agent_schema/station_registry.json');
  File get evidenceFile =>
      File('${root.path}/tool/chick_quality_v2/legacy_cleanup_evidence.json');

  static Future<_AuditFixture> create({
    required String runtimeSource,
    bool replacementProven = true,
    bool compatibilityReleased = true,
    bool migrationSafe = true,
    bool runtimeInventoryComplete = true,
    Map<String, String> extraSources = const {},
  }) async {
    final root = await Directory.systemTemp.createTemp('chick-cleanup-audit-');
    final fixture = _AuditFixture(root);
    await fixture.registryFile.parent.create(recursive: true);
    await fixture.registryFile.writeAsString(
      jsonEncode({
        'registryVersion': 1,
        'stations': [
          {
            'schemaKey': 'chicks.weights',
            'fields': [
              {
                'fieldKey': 'weightsJson',
                'persistence': {
                  'localColumn': 'weightsJson',
                  'remoteColumn': 'weights_json',
                },
                'observation': {'kind': 'series', 'key': 'weightsJson'},
              },
            ],
            'calculations': [
              {
                'fieldKey': 'avgWeight',
                'persistence': {
                  'localColumn': 'avgWeight',
                  'remoteColumn': 'avg_weight',
                },
              },
              {
                'fieldKey': 'sampleSize',
                'persistence': {
                  'localColumn': 'sampleSize',
                  'remoteColumn': 'sample_size',
                },
              },
            ],
          },
        ],
      }),
    );
    await fixture.evidenceFile.parent.create(recursive: true);
    await fixture.evidenceFile.writeAsString(
      jsonEncode({
        'runtimeReaderInventoryComplete': {
          'proven': runtimeInventoryComplete,
          'reason': 'fixture reader-inventory evidence',
        },
        'persistedReplacementCoverage': {
          'proven': replacementProven,
          'reason': 'fixture replacement evidence',
        },
        'backwardCompatibilityReleased': {
          'proven': compatibilityReleased,
          'reason': 'fixture compatibility evidence',
        },
        'losslessMigrationReady': {
          'proven': migrationSafe,
          'reason': 'fixture migration evidence',
        },
      }),
    );
    await _write(root, 'lib/runtime_reader.dart', runtimeSource);
    for (final entry in extraSources.entries) {
      await _write(root, entry.key, entry.value);
    }
    return fixture;
  }

  Future<LegacyCleanupAuditResult> audit() => auditLegacyCleanup(
    repositoryRoot: root,
    registryFile: registryFile,
    evidenceFile: evidenceFile,
  );

  Future<void> dispose() => root.delete(recursive: true);

  static Future<void> _write(
    Directory root,
    String relativePath,
    String contents,
  ) async {
    final file = File('${root.path}/$relativePath');
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
  }
}
