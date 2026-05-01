import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web metadata uses the ChickMark app name', () {
    final indexHtml = File('web/index.html').readAsStringSync();
    final manifest = jsonDecode(
      File('web/manifest.json').readAsStringSync(),
    ) as Map<String, Object?>;

    expect(indexHtml, contains('<title>ChickMark</title>'));
    expect(
      indexHtml,
      contains('<meta name="apple-mobile-web-app-title" content="ChickMark">'),
    );
    expect(manifest['name'], 'ChickMark');
    expect(manifest['short_name'], 'ChickMark');
  });
}
