import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;

  setUpAll(() {
    migration = File(
      'supabase/migrations/20260814130000_bmk_operational_standards.sql',
    ).readAsStringSync();
  });

  test('creates the table with every mirrored column', () {
    expect(
      migration,
      contains('create table if not exists public.bmk_operational_standards'),
    );
    const columns = [
      'id',
      'hatchery_id',
      'station_key',
      'sector_key',
      'metric_key',
      'metric_label',
      'unit',
      'min_value',
      'max_value',
      'target_value',
      'source',
      'source_url',
      'source_photo_path',
      'source_photo_remote_path',
      'notes',
      'sort_order',
      'updated_at',
    ];
    for (final column in columns) {
      expect(migration, contains(column), reason: column);
    }
  });

  test('enables RLS and revokes anon access', () {
    expect(
      migration,
      contains(
        'alter table public.bmk_operational_standards '
        'enable row level security',
      ),
    );
    expect(migration, contains('revoke all on public.bmk_operational_standards from anon'));
  });

  test('global rows are readable by all authenticated, writable by admin only',
      () {
    expect(migration, contains('bmk_operational_global_read'));
    expect(migration, contains('bmk_operational_global_write'));
    expect(migration, contains('chickmark_private.app_is_admin()'));
    expect(migration, contains('hatchery_id is null'));
  });

  test('hatchery rows are scoped through the owning customer', () {
    expect(migration, contains('bmk_operational_scoped_read'));
    expect(migration, contains('bmk_operational_scoped_write'));
    expect(
      migration,
      contains('chickmark_private.app_can_read_customer(h.customer_id)'),
    );
    expect(
      migration,
      contains('chickmark_private.app_can_write_customer(h.customer_id)'),
    );
    // The write policy must also constrain the inserted row, otherwise a row
    // can be re-pointed into a hatchery the caller cannot write.
    expect(migration, contains('with check'));
  });

  test('indexes the lookup scope', () {
    expect(migration, contains('idx_bmk_operational_scope'));
  });
}
