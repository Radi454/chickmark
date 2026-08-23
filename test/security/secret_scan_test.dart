import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('secret scanner catches legacy Supabase anon and service-role JWTs', () {
    final script = File('scripts/check_supabase_secrets.sh');
    expect(script.existsSync(), isTrue);

    final body = script.readAsStringSync();
    expect(
      body,
      contains(
        'sb_'
        'secret_',
      ),
    );
    expect(
      body,
      contains(
        'cm9sZSI6Im'
        'Fub24i',
      ),
    );
    expect(
      body,
      contains(
        'cm9sZSI6InNlcnZp'
        'Y2Vfcm9sZSI',
      ),
    );
    expect(
      body,
      contains(
        r'[0-9]{8,12}:AA'
        r'[A-Za-z0-9_-]{30,}',
      ),
    );
  });

  test('secret scanner catches provider API keys', () {
    // Realtime authenticates to OpenAI with OPENAI_API_KEY. A key pasted into
    // a markdown file is as leaked as one pasted into source, and `git grep`
    // only sees tracked files — so this pattern is what stops such a file the
    // moment it is staged.
    final body = File('scripts/check_supabase_secrets.sh').readAsStringSync();
    for (final pattern in const [
      r'sk-proj-[A-Za-z0-9_-]{20,}',
      r'sk-svcacct-[A-Za-z0-9_-]{20,}',
      r'sk-or-v1-[A-Za-z0-9]{20,}',
    ]) {
      expect(
        body,
        contains(pattern),
        reason: 'the scanner must reject $pattern before it can be committed',
      );
    }
  });
}
