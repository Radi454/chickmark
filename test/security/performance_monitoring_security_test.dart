import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;

  setUpAll(() {
    migration = File(
      'supabase/migrations_unapplied/0017_performance_monitoring.sql',
    ).readAsStringSync();
  });

  test('creates and exposes the complete monitoring graph with RLS', () {
    const tables = [
      'customer_sectors',
      'farms',
      'houses',
      'flock_placements',
      'broiler_daily_records',
      'broiler_daily_record_revisions',
      'daily_record_sources',
      'broiler_daily_events',
      'broiler_target_profiles',
      'broiler_target_rows',
      'performance_alert_rules',
      'performance_concerns',
      'farm_visit_sessions',
      'farm_visit_houses',
      'visit_investigations',
      'visit_findings',
      'cause_assessments',
      'corrective_actions',
      'action_kpi_evaluations',
    ];

    for (final table in tables) {
      expect(migration, contains('create table public.$table'), reason: table);
      expect(
        migration,
        contains('alter table public.$table enable row level security'),
        reason: table,
      );
    }
    expect(migration, contains('grant select, insert, update, delete on'));
  });

  test('tenant policies isolate customer rows and staff writes', () {
    expect(migration, contains('chickmark_private.app_can_read_customer'));
    expect(migration, contains('chickmark_private.app_can_write_customer'));
    expect(migration, contains('to authenticated'));
    expect(migration, contains('using (customer_id'));
    expect(migration, contains('with check (customer_id'));
    expect(migration, isNot(contains('using (true) with check (true)')));
  });

  test('daily revisions are immutable and source storage is tenant scoped', () {
    expect(
      migration,
      contains('chickmark_private.reject_daily_revision_mutation()'),
    );
    expect(
      migration,
      contains(
        'before update or delete on '
        'public.broiler_daily_record_revisions',
      ),
    );
    expect(
      migration,
      contains("split_part(name, '/', 1) = 'performance_sources'"),
    );
    expect(
      migration,
      contains(
        'chickmark_private.app_can_read_customer(\n'
        "          split_part(name, '/', 2)",
      ),
    );
  });
}
