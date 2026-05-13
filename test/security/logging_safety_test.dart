import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production code does not use raw print or debug stack logging', () {
    final dartFiles = _dartFiles(Directory('lib'));
    final violations = <String>[];

    for (final file in dartFiles) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.contains('print(') || line.contains('debugPrintStack')) {
          violations.add('${file.path}:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(violations, isEmpty);
  });

  test('BLE logs do not include raw payload or advertisement bytes', () {
    final service = File('lib/services/govee/govee_service.dart');
    expect(service.existsSync(), isTrue);

    final lines = service.readAsLinesSync();
    final violations = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.contains('debugPrint') &&
          (line.contains('_hex(') ||
              line.contains('payload') ||
              line.contains('serviceData') ||
              line.contains('manufacturerData'))) {
        violations.add('${service.path}:${i + 1}: ${line.trim()}');
      }
    }

    expect(violations, isEmpty);
  });
}

Iterable<File> _dartFiles(Directory root) {
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));
}
