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

  test('native launcher metadata uses the ChickMark app name', () {
    final androidManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final iosInfoPlist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(
      RegExp(
        r'android:label="([^"]+)"',
      ).firstMatch(androidManifest)?.group(1),
      'ChickMark',
    );
    expect(_plistString(iosInfoPlist, 'CFBundleDisplayName'), 'ChickMark');
    expect(_plistString(iosInfoPlist, 'CFBundleName'), 'ChickMark');
  });
}

String? _plistString(String plist, String key) {
  return RegExp(
    '<key>${RegExp.escape(key)}</key>\\s*<string>([^<]+)</string>',
    multiLine: true,
  ).firstMatch(plist)?.group(1);
}
