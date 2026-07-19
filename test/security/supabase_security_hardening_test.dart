import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;

  setUpAll(() {
    migration = [
      'supabase/migrations/0007_security_hardening.sql',
      'supabase/migrations/0008_explicit_function_revokes.sql',
    ].map((path) => File(path).readAsStringSync()).join('\n');
  });

  test('authorization helpers are private and require approved admins', () {
    expect(
      migration,
      contains('create schema if not exists chickmark_private'),
    );
    expect(
      migration,
      contains(
        "p.role = 'admin'\n"
        "      and p.status = 'approved'",
      ),
    );
    expect(
      migration,
      contains('drop function if exists public.app_is_admin()'),
    );
    expect(
      migration,
      contains(
        'grant execute on all functions in schema chickmark_private\n'
        '  to authenticated, service_role',
      ),
    );
  });

  test(
    'tombstones derive immutable tenant scope and snapshot their audience',
    () {
      expect(migration, contains('add column if not exists customer_id text'));
      expect(migration, contains('add column if not exists created_by uuid'));
      expect(
        migration,
        contains('add column if not exists audience_user_ids uuid[]'),
      );
      expect(migration, contains('new.customer_id := resolved_customer_id'));
      expect(
        migration,
        contains('new.audience_user_ids := old.audience_user_ids'),
      );
      expect(migration, contains('create policy tombstones_select'));
      expect(
        migration,
        contains('(select auth.uid()) = any (audience_user_ids)'),
      );
      expect(
        migration,
        isNot(contains('tombstones_staff on public.sync_tombstones for all')),
      );
    },
  );

  test(
    'anonymous database and public trigger execution grants are revoked',
    () {
      expect(
        migration,
        contains(
          'revoke all privileges on all tables in schema public from anon',
        ),
      );
      expect(
        migration,
        contains(
          'revoke execute on function public.handle_new_auth_user() '
          'from public, anon, authenticated',
        ),
      );
      expect(
        migration,
        contains(
          'revoke execute on function public.handle_new_customer() '
          'from public, anon, authenticated',
        ),
      );
      expect(
        migration,
        contains(
          'revoke execute on function public.touch_updated_at() '
          'from public, anon, authenticated',
        ),
      );
      expect(
        migration,
        contains(
          'alter default privileges for role postgres in schema public\n'
          '  revoke execute on functions from public, anon, authenticated',
        ),
      );
    },
  );
}
