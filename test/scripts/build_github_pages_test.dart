import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory tempDirectory;
  late File capturedArguments;
  late Map<String, String> environment;

  setUp(() {
    tempDirectory = Directory.systemTemp.createTempSync(
      'chickmark_pages_build_test_',
    );
    capturedArguments = File('${tempDirectory.path}/flutter-arguments.txt');

    final fakeFlutter = File('${tempDirectory.path}/flutter')
      ..writeAsStringSync('''#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "\$@" > "\$CAPTURED_ARGUMENTS"
''')
      ..setLastModifiedSync(DateTime.now());
    Process.runSync('chmod', ['+x', fakeFlutter.path]);

    environment = {
      ...Platform.environment,
      'PATH': '${tempDirectory.path}:${Platform.environment['PATH']}',
      'CAPTURED_ARGUMENTS': capturedArguments.path,
    };
  });

  tearDown(() {
    tempDirectory.deleteSync(recursive: true);
  });

  test('rejects a Pages build without Supabase client configuration', () {
    final result = Process.runSync(
      'bash',
      ['scripts/build_github_pages.sh'],
      environment: {
        ...environment,
        'SUPABASE_URL': '',
        'SUPABASE_ANON_KEY': '',
      },
    );

    expect(result.exitCode, isNot(0));
    expect(
      '${result.stdout}${result.stderr}',
      contains('SUPABASE_URL and SUPABASE_ANON_KEY are required'),
    );
    expect(capturedArguments.existsSync(), isFalse);
  });

  test('builds the release app for the ChickMark project path', () {
    final result = Process.runSync(
      'bash',
      ['scripts/build_github_pages.sh'],
      environment: {
        ...environment,
        'SUPABASE_URL': 'https://example.supabase.co',
        'SUPABASE_ANON_KEY': 'public-anon-key',
      },
    );

    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(capturedArguments.readAsLinesSync(), [
      'build',
      'web',
      '--release',
      '--base-href=/chickmark/',
      '--dart-define=SUPABASE_URL=https://example.supabase.co',
      '--dart-define=SUPABASE_ANON_KEY=public-anon-key',
    ]);
  });
}
