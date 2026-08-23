/// Pure helper that derives a short conversation title from a user message.
///
/// Mirrors `supabase/functions/app-hatchery-agent/conversation_title.ts` (the
/// server-side title deriver used for the Pip conversations list) so the
/// client-side "fresh conversation, no server title yet" header shows the
/// same title a reload from the server would later confirm. Keep the two in
/// sync if the trimming/truncation rules ever change.
library;

const int _maxTitleChars = 48;
const int _minWordBoundary = 12;

/// Trailing punctuation stripped after truncation, Latin and Arabic alike.
final RegExp _trailingPunctuation = RegExp(r'[.,;:!?،؛\s]+$');

final RegExp _whitespace = RegExp(r'\s+');

/// Derives a short title from a user message.
///
/// - Collapses internal whitespace and trims the ends.
/// - Empty (or whitespace-only) input yields `null`.
/// - Keeps at most 48 characters, cutting at the last word boundary at or
///   after character 12 when one exists in that range; otherwise hard-cuts at
///   48.
/// - Strips trailing punctuation (Latin and Arabic) left over from the cut.
///
/// Cutting by UTF-16 code unit index (`String.substring`, same units
/// `String.length` counts) is safe here because Arabic letters — and the
/// punctuation this strips — are all in the Basic Multilingual Plane, so no
/// surrogate pair is ever split.
String? deriveConversationTitle(String text) {
  final collapsed = text.replaceAll(_whitespace, ' ').trim();
  if (collapsed.isEmpty) return null;

  var truncated = collapsed;
  if (collapsed.length > _maxTitleChars) {
    final window = collapsed.substring(0, _maxTitleChars);
    final lastSpace = window.lastIndexOf(' ');
    truncated = lastSpace >= _minWordBoundary
        ? window.substring(0, lastSpace)
        : window;
  }

  final stripped = truncated.replaceAll(_trailingPunctuation, '').trim();
  return stripped.isEmpty ? null : stripped;
}
