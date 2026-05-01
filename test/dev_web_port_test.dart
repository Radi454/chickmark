import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web dev shortcuts use the stable ChickMark port', () {
    final makefile = File('Makefile').readAsStringSync();
    final runScript = File('scripts/run_flutter_web.sh').readAsStringSync();
    final readme = File('README.md').readAsStringSync();

    expect(makefile, contains('WEB_PORT ?= 57863'));
    expect(runScript, contains('WEB_PORT="\${WEB_PORT:-57863}"'));
    expect(readme, contains('http://127.0.0.1:57863'));
  });
}
