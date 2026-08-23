import 'package:flutter/widgets.dart';

/// Detects the paragraph direction from the first strong-direction
/// character, the same rule the Unicode Bidi algorithm's P2/P3 rules use for
/// a paragraph with no explicit direction marker. Chat replies frequently
/// mix Arabic and Latin script, so direction is decided per message rather
/// than following the app's ambient locale.
class TextDirectionDetector {
  const TextDirectionDetector._();

  // Codepoint ranges for scripts that are strongly right-to-left: Hebrew,
  // Arabic, Arabic Supplement, Arabic Extended-A, Hebrew presentation
  // forms, Arabic presentation forms A and B.
  static const List<(int, int)> _rtlRanges = [
    (0x0590, 0x05FF),
    (0x0600, 0x06FF),
    (0x0750, 0x077F),
    (0x08A0, 0x08FF),
    (0xFB1D, 0xFB4F),
    (0xFB50, 0xFDFF),
    (0xFE70, 0xFEFF),
  ];

  static bool _isRtl(int codePoint) {
    for (final (start, end) in _rtlRanges) {
      if (codePoint >= start && codePoint <= end) return true;
    }
    return false;
  }

  static bool _isLtrLetter(int codePoint) {
    return (codePoint >= 0x0041 && codePoint <= 0x005A) ||
        (codePoint >= 0x0061 && codePoint <= 0x007A);
  }

  /// Returns [TextDirection.rtl] when the first strong-direction character
  /// in [text] is Hebrew/Arabic script, [TextDirection.ltr] otherwise
  /// (including when no strong-direction character is found).
  static TextDirection detect(String text) {
    for (final rune in text.runes) {
      if (_isRtl(rune)) return TextDirection.rtl;
      if (_isLtrLetter(rune)) return TextDirection.ltr;
    }
    return TextDirection.ltr;
  }
}
