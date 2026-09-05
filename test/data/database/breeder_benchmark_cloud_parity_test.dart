import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards cloud/local drift for the benchmark reference data: every profile
/// the app imports from `assets/benchmarks/` must also be seeded by an
/// unapplied Supabase migration, with the same number of value rows, and
/// every metric definition must be declared in both places.
///
/// 0011 seeds Ross 308; 0016 is generated from the remaining asset files by
/// `tool/gen_breeder_benchmark_seed_sql.dart`. Regenerate 0016 rather than
/// hand-editing it when an asset file changes.
void main() {
  final seedSql = [
    'supabase/migrations_unapplied/0011_breeder_benchmark_foundation.sql',
    'supabase/migrations_unapplied/0016_breeder_benchmark_additional_profiles.sql',
  ].map((path) => File(path).readAsStringSync()).join('\n');

  final assetFiles =
      Directory('assets/benchmarks')
          .listSync()
          .whereType<File>()
          .where((f) => !f.path.endsWith('metric_definitions.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('every checked-in profile asset is declared to the local importer', () {
    final importer = File(
      'lib/data/database/seeds/breeder_benchmark_seeds.dart',
    ).readAsStringSync();
    for (final file in assetFiles) {
      final relative = file.path.replaceFirst(RegExp(r'^.*/(assets/)'), r'$1');
      expect(
        importer,
        contains("'$relative'"),
        reason:
            '$relative exists but is not in '
            '_kBreederBenchmarkProfileAssetPaths',
      );
    }
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final file in assetFiles) {
      final relative = file.path.replaceFirst(RegExp(r'^.*/(assets/)'), r'$1');
      expect(pubspec, contains('- $relative'), reason: '$relative not bundled');
    }
  });

  test(
    'every profile asset is seeded to the cloud with matching row counts',
    () {
      for (final file in assetFiles) {
        final profile =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final key = profile['profileKey'] as String;
        final expectedRows = (profile['values'] as List).length;

        expect(
          seedSql,
          contains("'profile-$key'"),
          reason: '$key has no cloud seed',
        );
        final seededRows = RegExp(
          "'profile-${RegExp.escape(key)}-v\\d+'",
        ).allMatches(seedSql).length;
        expect(
          seededRows,
          expectedRows,
          reason:
              '$key: asset has $expectedRows rows, seed SQL has $seededRows '
              '— regenerate with tool/gen_breeder_benchmark_seed_sql.dart',
        );
      }
    },
  );

  test('every metric definition is seeded to the cloud', () {
    final metrics =
        (jsonDecode(
                  File(
                    'assets/benchmarks/metric_definitions.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>)['metrics']
            as List;
    expect(metrics, hasLength(22));
    for (final metric in metrics.cast<Map<String, dynamic>>()) {
      expect(
        seedSql,
        contains("'metric-${metric['code']}'"),
        reason: '${metric['code']} is not seeded to the cloud',
      );
    }
  });

  test('no profile asset references an undefined metric code', () {
    final metrics =
        (jsonDecode(
                  File(
                    'assets/benchmarks/metric_definitions.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>)['metrics']
            as List;
    final known = {
      for (final m in metrics.cast<Map<String, dynamic>>()) m['code'] as String,
    };
    for (final file in assetFiles) {
      final profile =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final used = {
        for (final v
            in (profile['values'] as List).cast<Map<String, dynamic>>())
          v['metricCode'] as String,
      };
      expect(
        used.difference(known),
        isEmpty,
        reason: '${profile['profileKey']} uses undeclared metric codes',
      );
    }
  });
}
