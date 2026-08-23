import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String? _postgresBin() {
  final configured = Platform.environment['CHICKMARK_POSTGRES_BIN'];
  if (configured != null && File('$configured/initdb').existsSync()) {
    return configured;
  }

  final systemInitdb = Process.runSync('sh', ['-c', 'command -v initdb']);
  if (systemInitdb.exitCode == 0) {
    return File(systemInitdb.stdout.toString().trim()).parent.path;
  }

  final libraryRoot = Directory('/Library/PostgreSQL');
  if (libraryRoot.existsSync()) {
    final versions =
        libraryRoot
            .listSync()
            .whereType<Directory>()
            .map((directory) => '${directory.path}/bin')
            .where((path) => File('$path/initdb').existsSync())
            .toList()
          ..sort();
    if (versions.isNotEmpty) return versions.last;
  }

  return null;
}

void main() {
  final postgresBin = _postgresBin();

  test(
    'Realtime persistence enforces ordering, evidence and claim invariants',
    () async {
      final result = await Process.run(
        'bash',
        ['scripts/test_pip_realtime_persistence.sh'],
        environment: {
          ...Platform.environment,
          'CHICKMARK_POSTGRES_BIN': postgresBin!,
        },
      );

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stdout,
        contains('Pip Realtime V1 persistence integration checks passed.'),
      );
    },
    skip: postgresBin == null
        ? 'PostgreSQL tools are not installed in this environment.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
