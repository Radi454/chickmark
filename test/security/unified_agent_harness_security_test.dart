import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;

  setUpAll(() {
    final files = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('_unified_agent_harness.sql'))
        .toList(growable: false);
    expect(files, hasLength(1));
    migration = files.single.readAsStringSync().toLowerCase();
  });

  test('Telegram access scope is structurally constrained', () {
    expect(migration, contains('access_role'));
    expect(migration, contains('customer_id'));
    expect(migration, contains("access_role in ('customer', 'admin')"));
    expect(migration, contains("status <> 'allowed'"));
    expect(
      migration,
      contains("access_role = 'customer' and customer_id is not null"),
    );
    expect(
      migration,
      contains("access_role = 'admin' and customer_id is null"),
    );
  });

  test('agent evidence tables are RLS protected and admin scoped', () {
    for (final table in const [
      'agent_conversations',
      'agent_conversation_turns',
      'agent_tool_events',
      'agent_intake_visits',
    ]) {
      expect(
        migration,
        contains('alter table public.$table enable row level security'),
        reason: table,
      );
      expect(
        RegExp(
          'revoke all on table public\\.$table\\s+'
          'from public, anon(?:, authenticated)?',
        ).hasMatch(migration),
        isTrue,
        reason: table,
      );
      expect(
        migration,
        contains('grant select on table public.$table to authenticated'),
        reason: table,
      );
      expect(
        migration,
        isNot(
          contains(
            'grant select, insert, update on table public.$table '
            'to authenticated',
          ),
        ),
        reason: '$table is pulled read-only by the admin app',
      );
      expect(
        migration,
        contains('chickmark_private.app_is_admin()'),
        reason: table,
      );
      expect(
        migration,
        contains('grant all on table public.$table to service_role'),
        reason: table,
      );
    }
  });

  test('visit scope and confirmed evidence are guarded in the database', () {
    expect(migration, contains('validate_agent_intake_visit_scope'));
    expect(migration, contains('flock does not belong to visit customer'));
    expect(migration, contains('hatchery does not belong to visit customer'));
    expect(migration, contains('agent_intake_summary_immutable'));
    expect(
      migration,
      contains('confirmed intake summary evidence is immutable'),
    );
    expect(migration, contains('agent_tool_events_immutable'));
    expect(migration, contains('tool-call evidence is immutable'));
  });

  test('legacy sessions are backfilled without deletion', () {
    expect(migration, contains('legacy-conversation-'));
    expect(migration, contains('legacy-visit-'));
    expect(migration, contains('row_version = 1'));
    expect(
      migration,
      isNot(contains('delete from public.agent_intake_sessions')),
    );
    expect(
      migration,
      isNot(contains('drop table public.agent_intake_sessions')),
    );
  });
}
