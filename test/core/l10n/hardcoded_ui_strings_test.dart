import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/l10n/app_localizations.dart';

void main() {
  test('Agent Monitor status copy has direct Arabic translations', () {
    final arabic = AppLocalizations(const Locale('ar'));

    expect(arabic.translate('Agent'), 'الوكيل');
    expect(arabic.translate('Agent Monitor'), 'مراقبة الوكيل');
    expect(arabic.translate('Draft ready'), 'المسودة جاهزة');
    expect(arabic.translate('Waiting for staff answer'), 'بانتظار رد الموظف');
    expect(arabic.translate('Needs admin review'), 'تحتاج مراجعة المدير');
    expect(arabic.translate('Telegram running'), 'تيليجرام يعمل');
    expect(arabic.translate('Telegram paused'), 'تم إيقاف تيليجرام مؤقتًا');
    expect(arabic.translate('Confidence'), 'الثقة');
    expect(arabic.translate('Warnings'), 'تنبيهات');
    expect(arabic.translate('Hatchability'), 'نسبة الفقس');
  });

  test('static user-facing strings have Arabic translations', () {
    final arabic = AppLocalizations(const Locale('ar'));
    final patterns = <RegExp>[
      RegExp(
        r'''(?:Text|TextSpan)\(\s*(?:text:\s*)?['"]([^'"\n]*[A-Za-z][^'"\n]*)['"]''',
      ),
      RegExp(
        r'''(?:labelText|hintText|helperText|errorText|tooltip|message):\s*['"]([^'"\n]*[A-Za-z][^'"\n]*)['"]''',
      ),
      RegExp(
        r'''(?:label|title|subtitle|description|placeholder|missingHint|emptyText|buttonText|actionLabel|value):\s*['"]([^'"\n]*[A-Za-z][^'"\n]*)['"]''',
      ),
      RegExp(r'''Tab\s*\(\s*text:\s*['"]([^'"\n]*[A-Za-z][^'"\n]*)['"]'''),
    ];
    const allowedProductTerms = <String>{
      'ChickMark',
      'Govee',
      'BMK',
      'HOF',
      'CV',
      'C.V',
      'EST',
      'CVT',
      'YFBM',
      'PM',
      'RH',
      'RSSI',
      'ID',
      'STD',
      'PASGAR',
      'Pasgar',
      'PDF',
      'Ross308',
      'S',
      'H',
      'T',
      '°F',
      '°C',
    };
    final misses = <String>{};

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      final filePatterns = <RegExp>[
        ...patterns,
        if (entity.path.contains('/screens/') ||
            entity.path.contains('/widgets/'))
          RegExp(r'''['"][^'"\n]+['"]:\s*['"]([^'"\n]*[A-Za-z][^'"\n]*)['"]'''),
        if (entity.path.contains('/screens/') ||
            entity.path.contains('/widgets/'))
          RegExp(r'''(?:return|=>)\s*['"]([^'"\n]*[A-Za-z][^'"\n]*)['"]'''),
      ];
      for (final pattern in filePatterns) {
        for (final match in pattern.allMatches(source)) {
          final value = match.group(1)!;
          if (allowedProductTerms.contains(value) || value.contains(r'$')) {
            continue;
          }
          if (RegExp(r'^[a-z][a-zA-Z0-9_]*$').hasMatch(value)) continue;
          // Adjacent/escaped Dart string fragments are validated through the
          // catalog behavior tests using their complete runtime value.
          if (RegExp(r'''[\\\s]$''').hasMatch(value) ||
              value.contains(r'\n') ||
              value == 'don') {
            continue;
          }
          if (arabic.translate(value) != value) continue;
          final line =
              '\n'.allMatches(source.substring(0, match.start)).length + 1;
          misses.add('${entity.path}:$line  $value');
        }
      }
    }

    expect(
      misses,
      isEmpty,
      reason:
          'Untranslated static UI copy:\n${(misses.toList()..sort()).join('\n')}',
    );
  });
}
