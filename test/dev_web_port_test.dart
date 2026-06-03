import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web dev shortcuts use the stable ChickMark port', () {
    final makefile = File('Makefile').readAsStringSync();
    final runScript = File('scripts/run_flutter_web.sh').readAsStringSync();
    final commandScript =
        File('scripts/run_flutter_web.command').readAsStringSync();
    final readme = File('README.md').readAsStringSync();

    expect(makefile, contains('WEB_PORT ?= 57863'));
    expect(makefile, contains('run: restart-web'));
    expect(runScript, contains('WEB_PORT="\${WEB_PORT:-57863}"'));
    expect(runScript, contains('WEB_BUILD_MODE="\${WEB_BUILD_MODE:-profile}"'));
    expect(runScript, contains('--"\${WEB_BUILD_MODE}"'));
    expect(runScript, contains('--no-web-resources-cdn'));
    expect(commandScript, contains('RESTART=1 scripts/run_flutter_web.sh'));
    expect(readme, contains('http://127.0.0.1:57863'));
    expect(readme, contains('profile web-server build'));
    expect(readme, contains('make run'));
  });
}
