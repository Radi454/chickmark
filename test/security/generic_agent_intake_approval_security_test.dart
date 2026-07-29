import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;
  late String functionSource;

  setUpAll(() {
    migration = File(
      'supabase/migrations/20260728133000_generic_agent_intake_approval.sql',
    ).readAsStringSync().toLowerCase();
    functionSource = File(
      'supabase/functions/approve-agent-intake/index.ts',
    ).readAsStringSync().toLowerCase();
  });

  test('approval RPC is service-role only and table names are allowlisted', () {
    expect(migration, contains("current_user <> 'service_role'"));
    expect(migration, isNot(contains('auth.role()')));
    expect(
      migration,
      contains('revoke all on function public.approve_agent_intake'),
    );
    expect(migration, contains('from public, anon, authenticated'));
    expect(migration, contains('to service_role'));
    expect(migration, contains("p_remote_table not in ("));
    expect(migration, contains("'chick_weights'"));
  });

  test('Edge approval verifies the caller and approved admin profile', () {
    expect(functionSource, contains('auth.getuser()'));
    expect(functionSource, contains("profile?.role !== 'admin'"));
    expect(functionSource, contains("profile.status !== 'approved'"));
    expect(functionSource, contains('expectedsummaryversion'));
    expect(functionSource, contains('prepareagentintakeapproval'));
  });

  test('scope constraint supports every registered collection layer', () {
    for (final layer in const [
      'pool',
      'house',
      'setter',
      'hatcher',
      'setter_hatcher',
      'trolley',
      'tray',
    ]) {
      expect(migration, contains("'$layer'"), reason: layer);
    }
  });
}
