import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;

  setUpAll(() {
    final files = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('_agent_hardening.sql'))
        .toList(growable: false);
    expect(files, hasLength(1));
    migration = files.single.readAsStringSync().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
  });

  test('conversation context and ordered diagnostics are additive', () {
    for (final field in const [
      'context_epoch',
      'selected_customer_id',
      'selected_flock_id',
      'selected_audit_id',
      'context_updated_at',
      'turn_index',
      'provider',
      'provider_response_id',
      'reply_to_turn_id',
      'tool_sequence',
    ]) {
      expect(migration, contains(field), reason: field);
    }
    expect(
      migration,
      matches(
        RegExp(
          r'\(\s*conversation_id,\s*context_epoch,\s*direction,\s*turn_index\s*\)',
        ),
      ),
    );
    expect(migration, contains('(conversation_turn_id, tool_sequence)'));
  });

  test('legacy flock sectors are backfilled only from reviewed evidence', () {
    expect(migration, contains('farm.sector_key'));
    expect(migration, contains("set sector_key = 'breeder'"));
    expect(migration, contains('count(distinct sector.sector_key) = 1'));
    expect(migration, contains('where flock.sector_key is null'));
    expect(migration, isNot(contains('delete from public.flocks')));
    expect(migration, isNot(contains('drop table public.flocks')));
  });

  test('migration preserves evidence rows and remains service controlled', () {
    for (final table in const [
      'agent_conversations',
      'agent_conversation_turns',
      'agent_tool_events',
    ]) {
      expect(migration, isNot(contains('delete from public.$table')));
      expect(migration, isNot(contains('drop table public.$table')));
    }
    expect(
      migration,
      contains('grant all on table public.agent_conversations to service_role'),
    );
  });
}
