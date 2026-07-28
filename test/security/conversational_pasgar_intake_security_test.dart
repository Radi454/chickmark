import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;

  setUpAll(() {
    final files = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .where(
          (file) => file.path.endsWith('_conversational_pasgar_intake.sql'),
        )
        .toList(growable: false);
    expect(files, hasLength(1));
    migration = files.single.readAsStringSync().toLowerCase();
  });

  test('intake tables require RLS and expose no anonymous access', () {
    for (final table in const [
      'agent_intake_sessions',
      'agent_intake_turns',
      'agent_intake_values',
    ]) {
      expect(
        migration,
        contains('alter table public.$table enable row level security'),
        reason: table,
      );
      expect(migration, contains("'$table'"), reason: table);
    }
    expect(migration, contains("'revoke all on public.%i from public, anon'"));
  });

  test('approval is invoker-scoped and restricted to approved admins', () {
    expect(migration, contains('security invoker'));
    expect(migration, contains('chickmark_private.app_is_admin()'));
    expect(
      RegExp(
        r'revoke execute on function public\.approve_pasgar_intake'
        r'\(text, text\)\s+from public, anon',
      ).hasMatch(migration),
      isTrue,
    );
    expect(
      RegExp(
        r'grant execute on function public\.approve_pasgar_intake'
        r'\(text, text\)\s+to authenticated',
      ).hasMatch(migration),
      isTrue,
    );
  });

  test('approval locks and revalidates the confirmed schema snapshot', () {
    expect(migration, contains('for update'));
    expect(migration, contains("schema_key <> 'chicks.pasgar'"));
    expect(migration, contains('schema_version <> 1'));
    expect(migration, contains("state <> 'awaiting_admin_review'"));
    expect(migration, contains('pasgar_feather_dev_pct'));
    expect(migration, contains('pasgar_final_score'));
    expect(migration, contains('approved_panel_row_id'));
    expect(migration, contains('if intake.approved_panel_row_id is not null'));
    expect(migration, contains("'[\"chicks\"]'"));
    expect(migration, contains('jsonb_array_elements_text'));
  });
}
