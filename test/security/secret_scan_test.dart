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
  });
}
