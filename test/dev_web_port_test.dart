import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dev shortcuts use stable local settings', () {
    final makefile = File('Makefile').readAsStringSync();
    final runScript = File('scripts/run_flutter_web.sh').readAsStringSync();
    final commandScript = File(
      'scripts/run_flutter_web.command',
    ).readAsStringSync();
    final readme = File('README.md').readAsStringSync();
    final launchConfig = File('.vscode/launch.json').readAsStringSync();
    final macosProject = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    expect(makefile, contains('WEB_PORT ?= 57863'));
    expect(makefile, contains('run: restart-web'));
    expect(makefile, contains('run-macos:'));
    expect(makefile, contains(r'flutter run $(DEV_DART_DEFINES) -d macos'));
    expect(makefile, contains('build-macos:'));
    expect(makefile, contains(r'flutter build macos $(DART_DEFINES)'));
    expect(runScript, contains('WEB_PORT="\${WEB_PORT:-57863}"'));
    expect(runScript, contains('WEB_BUILD_MODE="\${WEB_BUILD_MODE:-profile}"'));
    expect(runScript, contains('--"\${WEB_BUILD_MODE}"'));
    expect(runScript, contains('--no-web-resources-cdn'));
    expect(commandScript, contains('RESTART=1 scripts/run_flutter_web.sh'));
    expect(readme, contains('http://127.0.0.1:57863'));
    expect(readme, contains('profile web-server build'));
    expect(readme, contains('make run'));
    expect(readme, contains('make run-macos'));
    expect(launchConfig, contains('--dart-define-from-file=.env'));
    expect(launchConfig, isNot(contains('--dart-define-from-file=.env.json')));
    expect(macosProject, contains('Copy Local Supabase Env'));
    expect(macosProject, contains(r'$PROJECT_DIR/../.env'));
    expect(macosProject, contains(r'$CONFIGURATION\" = \"Release'));
  });
}
