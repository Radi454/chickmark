import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static checks on `scripts/verify_pip_openai_models.sh`: the OpenAI model
/// preflight run before any account switch. No network access — this only
/// reads the script's own text, the same discipline as
/// `secret_scan_test.dart` for `scripts/check_supabase_secrets.sh`.
void main() {
  final script = File('scripts/verify_pip_openai_models.sh');

  test('the preflight script exists', () {
    expect(script.existsSync(), isTrue);
  });

  final body = script.readAsStringSync();

  test('checks every model alias Pip Live depends on', () {
    for (final alias in const [
      'gpt-5-nano',
      'gpt-realtime-2.1-mini',
      'gpt-4o-mini-transcribe',
      'gpt-4o-mini-tts',
    ]) {
      expect(
        body,
        contains(alias),
        reason: 'the preflight must check the exact alias "$alias"',
      );
    }
  });

  test('OPENAI_API_KEY is only ever referenced as an environment variable', () {
    // A shell expansion — `${OPENAI_API_KEY...}` — appears at least once...
    expect(body, contains(r'${OPENAI_API_KEY'));

    // ...and no line the shell actually executes assigns it directly (e.g.
    // `OPENAI_API_KEY=<value>`), which would hardcode a key instead of
    // reading it from the environment. Comments and the `echo` line that
    // tells the *user* how to export it are not executed assignments, so
    // they are excluded rather than misread as one.
    for (final line in body.split('\n')) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('#') || trimmed.startsWith('echo')) continue;
      if (!line.contains('OPENAI_API_KEY') || !line.contains('=')) continue;
      expect(
        line,
        contains(r'${OPENAI_API_KEY'),
        reason:
            'line "$line" assigns OPENAI_API_KEY directly instead of '
            'reading it from the environment',
      );
    }
  });

  test('never embeds an OpenAI-key-shaped literal', () {
    expect(
      body.contains('sk-'),
      isFalse,
      reason: 'the script must never contain a hardcoded OpenAI API key',
    );
  });
}
