import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory tempDirectory;
  late File capturedArguments;
  late File generatedIndex;
  late Map<String, String> environment;

  setUp(() {
    tempDirectory = Directory.systemTemp.createTempSync(
      'chickmark_pages_build_test_',
    );
    capturedArguments = File('${tempDirectory.path}/flutter-arguments.txt');
    final stagedScripts = Directory('${tempDirectory.path}/scripts')
      ..createSync();
    final repositoryScripts = Directory('${Directory.current.path}/scripts');
    File(
      '${repositoryScripts.path}/build_github_pages.sh',
    ).copySync('${stagedScripts.path}/build_github_pages.sh');
    File(
      '${repositoryScripts.path}/fingerprint_pages_assets.py',
    ).copySync('${stagedScripts.path}/fingerprint_pages_assets.py');

    final buildWeb = Directory('${tempDirectory.path}/build/web')
      ..createSync(recursive: true);
    generatedIndex = File('${buildWeb.path}/index.html')
      ..writeAsStringSync('<script src="flutter_bootstrap.js" async></script>');
    File(
      '${buildWeb.path}/main.dart.js',
    ).writeAsStringSync('console.log("fixture app");');
    File('${buildWeb.path}/flutter_bootstrap.js').writeAsStringSync(
      '_flutter.buildConfig = {"builds":[{"mainJsPath":"main.dart.js"}]};',
    );
    File(
      '${buildWeb.path}/flutter_service_worker.js',
    ).writeAsStringSync('const RESOURCES = {};\nconst CORE = [];\n');

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
      workingDirectory: tempDirectory.path,
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
      workingDirectory: tempDirectory.path,
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
    expect(
      generatedIndex.readAsStringSync(),
      matches(RegExp(r'<script src="flutter_bootstrap\.[a-f0-9]+\.js"')),
    );
  });
}
