import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/utils/text_direction_detector.dart';

void main() {
  group('TextDirectionDetector.detect', () {
    test('plain English text is ltr', () {
      expect(
        TextDirectionDetector.detect('Hatchability of Ross at week 35 is 92%'),
        TextDirection.ltr,
      );
    });

    test('plain Arabic text is rtl', () {
      expect(
        TextDirectionDetector.detect('نسبة الفقس لسلالة روس في الأسبوع 35'),
        TextDirection.rtl,
      );
    });

    test('Arabic text starting with digits is still rtl', () {
      expect(
        TextDirectionDetector.detect('92% نسبة الفقس'),
        TextDirection.rtl,
      );
    });

    test('English text starting with digits is still ltr', () {
      expect(
        TextDirectionDetector.detect('92% hatchability'),
        TextDirection.ltr,
      );
    });

    test('mixed text follows the first strong-direction character', () {
      expect(
        TextDirectionDetector.detect('Ross308 نسبة الفقس هي 92%'),
        TextDirection.ltr,
      );
      expect(
        TextDirectionDetector.detect('نسبة Ross308 الفقس هي 92%'),
        TextDirection.rtl,
      );
    });

    test('text with no strong-direction character defaults to ltr', () {
      expect(TextDirectionDetector.detect('123 %  456'), TextDirection.ltr);
      expect(TextDirectionDetector.detect(''), TextDirection.ltr);
    });
  });
}
