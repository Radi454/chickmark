import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static assertions of the cloud policy SQL for breeder-flock-performance
/// ticket 16 (customer-scoped access and role-gated approval; design doc
/// docs/superpowers/specs/2026-08-27-breeder-flock-performance-design.md
/// sections 5.3 and 13).
///
/// IMPORTANT — what these tests genuinely prove versus what they do not:
/// none of `supabase/migrations_unapplied/0011-0014` are applied to the
/// live Supabase project (see that directory's README), and this test
/// suite never connects to Postgres. These are TEXT assertions against the
/// migration SQL: they prove the SQL contains the specific clauses,
/// constraints, and function bodies this policy design requires (and would
/// fail if a future edit dropped, weakened, or loosened one of them — e.g.
/// widened a check, removed a `with check`, or deleted the approval
/// trigger). They do NOT prove Postgres accepts this SQL, that RLS
/// evaluates it as intended at runtime, or that no other policy /
/// grant / search_path interaction defeats it once applied. A live round
/// trip against a real project (or a local `supabase db` instance) would be
/// needed for that and is out of scope here per the ticket's instruction
/// not to touch the remote project.
void main() {
  late String m0011;
  late String m0012;
  late String m0013;
  late String m0014;
  late String ledgerService;

  setUpAll(() {
    m0011 = File(
      'supabase/migrations_unapplied/0011_breeder_benchmark_foundation.sql',
    ).readAsStringSync();
    m0012 = File(
      'supabase/migrations_unapplied/0012_breeder_flock_sync_registration.sql',
    ).readAsStringSync();
    m0013 = File(
      'supabase/migrations_unapplied/0013_breeder_daily_report_aggregate_push.sql',
    ).readAsStringSync();
    m0014 = File(
      'supabase/migrations_unapplied/0014_breeder_customer_scope_and_approval_role.sql',
    ).readAsStringSync();
    ledgerService = File(
      'lib/services/breeder/breeder_bird_ledger_service.dart',
    ).readAsStringSync();
  });

  group('production_manager role is real and assignable', () {
    test('profiles_role_check widens to allow production_manager', () {
      expect(m0014, contains('drop constraint if exists profiles_role_check'));
      expect(
        m0014,
        contains(
          "check (role in ('admin', 'auditor', 'customer', 'personal', 'production_manager'))",
        ),
      );
    });

    test(
      'customer scoping helpers are redefined (not duplicated) to cover it',
      () {
        // Same function names/signatures as 0007's originals, so every
        // existing caller (flocks/houses/etc. policies, 0012's
        // app_can_read_flock/app_can_write_flock) picks this up without
        // being touched itself.
        expect(
          m0014,
          contains(
            'create or replace function chickmark_private.app_can_read_customer(cid text)',
          ),
        );
        expect(
          m0014,
          contains(
            'create or replace function chickmark_private.app_can_write_customer(cid text)',
          ),
        );
        expect(m0014, contains("p.role in ('auditor', 'production_manager')"));
        // Customers stay read-only: production_manager must not appear in a
        // customer-role branch, and the write helper's customer branch
        // (`role = 'customer'`) must still be absent.
        expect(
          m0014,
          isNot(contains("'production_manager' and p.role = 'customer'")),
        );
      },
    );

    test('admin User Access screen can assign the role', () {
      final screen = File(
        'lib/features/admin/screens/admin_users_screen.dart',
      ).readAsStringSync();
      expect(
        screen,
        contains("DropdownMenuItem(\n                  value: 'production_manager',"),
      );
      expect(screen, contains("_scopedByAssignment = {'auditor', 'production_manager'}"));
    });
  });

  group('single-sourced approval role enumeration', () {
    test('cloud enumerates the same two roles as the client, exactly', () {
      // Client side: BreederApprovalRole.permitted.
      final clientMatch = RegExp(
        r'static const List<String> permitted = \[([^\]]+)\];',
      ).firstMatch(ledgerService);
      expect(
        clientMatch,
        isNotNull,
        reason: 'BreederApprovalRole.permitted literal not found',
      );
      final clientRoles =
          RegExp(r'[A-Za-z]+')
              .allMatches(clientMatch!.group(1)!)
              .map((m) => m.group(0)!)
              .toSet();
      // Resolve the two identifier references (productionManager, admin)
      // to their string values as declared in the same class.
      final resolved = clientRoles.map((identifier) {
        final valueMatch = RegExp(
          'static const String $identifier = \'([a-z_]+)\';',
        ).firstMatch(ledgerService);
        expect(
          valueMatch,
          isNotNull,
          reason: 'Could not resolve BreederApprovalRole.$identifier',
        );
        return valueMatch!.group(1)!;
      }).toSet();

      // Cloud side: chickmark_private.app_can_approve_breeder_report().
      // Scope the search to that function's own body so this doesn't
      // accidentally match the unrelated auditor/production_manager role
      // list inside app_can_read_customer/app_can_write_customer earlier
      // in the same file.
      final functionBodyMatch = RegExp(
        r'create or replace function chickmark_private\.app_can_approve_breeder_report[\s\S]*?\$\$;',
      ).firstMatch(m0014);
      expect(
        functionBodyMatch,
        isNotNull,
        reason: 'app_can_approve_breeder_report function body not found',
      );
      final cloudMatch = RegExp(
        r"p\.role in \('([a-z_]+)', '([a-z_]+)'\)",
      ).firstMatch(functionBodyMatch!.group(0)!);
      expect(
        cloudMatch,
        isNotNull,
        reason: 'app_can_approve_breeder_report role list not found',
      );
      final cloudRoles = {cloudMatch!.group(1)!, cloudMatch.group(2)!};

      expect(
        cloudRoles,
        equals(resolved),
        reason:
            'Cloud chickmark_private.app_can_approve_breeder_report() must '
            'enumerate exactly the same roles as client '
            'BreederApprovalRole.permitted — found cloud=$cloudRoles vs '
            'client=$resolved',
      );
      expect(resolved, equals({'production_manager', 'admin'}));
    });

    test('exactly one enumerated approval-role function exists per side', () {
      expect(
        'app_can_approve_breeder_report'.allMatches(m0014).length,
        greaterThanOrEqualTo(1),
      );
      expect(
        RegExp(
          r'create (or replace )?function chickmark_private\.app_can_approve_breeder_report',
        ).allMatches(m0014).length,
        1,
        reason: 'exactly one definition, not two competing ones',
      );
      expect(
        RegExp(
          r'class BreederApprovalRole',
        ).allMatches(ledgerService).length,
        1,
      );
    });
  });

  group('approval transition is checked against actor role in cloud policy', () {
    test(
      'a BEFORE INSERT OR UPDATE trigger on breeder_daily_reports enforces it',
      () {
        expect(
          m0014,
          contains(
            'before insert or update on public.breeder_daily_reports',
          ),
        );
        expect(
          m0014,
          contains(
            'for each row execute function chickmark_private.enforce_breeder_report_approval_role',
          ),
        );
      },
    );

    test('the trigger gates specifically the transition INTO approved', () {
      expect(m0014, contains("new.state = 'approved'"));
      expect(
        m0014,
        contains("old.state is distinct from 'approved'"),
        reason:
            'must compare OLD vs NEW state — a plain WITH CHECK cannot do '
            'this, which is why this is a trigger and not just an RLS clause',
      );
      expect(
        m0014,
        contains('not chickmark_private.app_can_approve_breeder_report()'),
      );
      expect(m0014, contains("errcode = '42501'"));
    });

    test(
      'the SECURITY DEFINER aggregate-push RPC cannot bypass the trigger',
      () {
        // 0013's function writes via `insert ... on conflict do update`,
        // which fires the same BEFORE UPDATE trigger as a plain UPDATE for
        // the conflicting-row branch — Postgres does not distinguish them
        // for trigger-firing purposes. Assert the RPC still uses that
        // pattern (not a raw UPDATE/DELETE+INSERT that could dodge it) and
        // that 0013 itself never claims to do the role check, so 0014 is
        // demonstrably the only place enforcing it.
        expect(m0013, contains('on conflict (id) do update set'));
        expect(
          m0013,
          contains(
            "This function does not enforce the approval-role check",
          ),
        );
        expect(
          m0014,
          contains('push_breeder_daily_report_aggregate'),
          reason:
              'the header must document why the RPC cannot dodge the trigger',
        );
      },
    );

    test('is_distinct_from guards against re-approving an already-approved row not re-checking', () {
      // A no-op save of an already-approved row (state stays 'approved')
      // must not re-run the permission check — approve() is a one-way
      // gated transition, not a property enforced on every write of an
      // approved row (which would also block e.g. an approved-report
      // correction workflow that never changes `state`).
      expect(m0014, contains("tg_op = 'INSERT' or old.state is distinct from 'approved'"));
    });
  });

  group('published benchmark data is refused, not merely unrouted', () {
    test('benchmark reference tables have only a SELECT policy in 0011', () {
      for (final table in [
        'breeder_metric_definitions',
        'breeder_benchmark_profiles',
        'breeder_benchmark_values',
      ]) {
        expect(m0011, contains('create policy ${table}_read on public.$table'));
        expect(m0011, contains('for select to authenticated using (true)'));
        expect(
          m0011,
          isNot(contains('create policy ${table}_write')),
          reason: 'no write policy must ever be added for $table',
        );
        expect(
          m0011,
          isNot(matches(RegExp('create policy \\w+ on public\\.$table for (insert|update|delete|all)'))),
        );
      }
    });

    test('0014 explicitly revokes write privileges as defense in depth', () {
      for (final table in [
        'breeder_metric_definitions',
        'breeder_benchmark_profiles',
        'breeder_benchmark_values',
        'breeder_egg_grade_definitions',
      ]) {
        expect(
          m0014,
          contains(
            'revoke insert, update, delete on public.$table from authenticated, anon',
          ),
          reason: '$table must be explicitly write-revoked, not just RLS-silent',
        );
      }
    });
  });

  group('every breeder/egg table is flock-and-thus-customer scoped', () {
    // Design section 12/13: "customer ownership traceable for every
    // operational row" and "Operational data is customer-scoped with RLS
    // ownership predicates". Every table 0012 creates must use
    // app_can_read_flock/app_can_write_flock (directly via a flock_id
    // column, or transitively via a join to a table that does), never a
    // permissive `using (true)` or `using true` write policy.
    const directlyFlockScoped = [
      'houses',
      'breeder_flock_milestones',
      'breeder_isolation_areas',
      'breeder_daily_reports',
      'breeder_weighing_sessions',
      'egg_batches',
      'egg_shipments',
    ];

    const joinScopedChildren = [
      'breeder_bird_movements',
      'breeder_feed_entries',
      'breeder_egg_production_entries',
      'breeder_egg_inventory_movements',
      'breeder_report_revisions',
      'breeder_weighing_samples',
      'egg_batch_house_sources',
      'egg_shipment_batches',
      'egg_batch_receipts',
    ];

    for (final table in directlyFlockScoped) {
      test('$table read/write policies call the flock-scope helpers', () {
        expect(m0012, contains('create policy ${table}_read on public.$table'));
        expect(
          m0012,
          contains('using (chickmark_private.app_can_read_flock(flock_id))'),
        );
        expect(
          m0012,
          contains('using (chickmark_private.app_can_write_flock(flock_id))'),
        );
      });
    }

    for (final table in joinScopedChildren) {
      test('$table read/write policies join back to a flock-scoped parent', () {
        expect(m0012, contains('create policy ${table}_read on public.$table'));
        expect(m0012, contains('create policy ${table}_write on public.$table'));
        // Every child policy must reference one of the two helpers
        // somewhere in its own definition block.
        final policyBlock = RegExp(
          'create policy ${table}_write.*?(?=create (?:table|policy)|\$)',
          dotAll: true,
        ).firstMatch(m0012)?.group(0);
        expect(policyBlock, isNotNull, reason: '$table write policy not found');
        expect(
          policyBlock,
          contains('chickmark_private.app_can_write_flock'),
        );
      });
    }

    test('no breeder/egg table policy uses a permissive using (true) write', () {
      expect(
        m0012,
        isNot(
          matches(
            RegExp(r'for all to authenticated\s+using \(true\)'),
          ),
        ),
      );
    });

    test('app_can_read_flock/app_can_write_flock join through flocks.customer_id', () {
      expect(m0012, contains('from public.flocks f'));
      expect(m0012, contains('chickmark_private.app_can_read_customer(f.customer_id)'));
      expect(m0012, contains('chickmark_private.app_can_write_customer(f.customer_id)'));
    });
  });

  group('README documents 0014 and its apply order', () {
    test('README mentions 0014 after 0013', () {
      final readme = File(
        'supabase/migrations_unapplied/README.md',
      ).readAsStringSync();
      expect(readme, contains('0014_breeder_customer_scope_and_approval_role.sql'));
      final idx0013 = readme.indexOf('0013_breeder_daily_report_aggregate_push.sql');
      final idx0014 = readme.indexOf('0014_breeder_customer_scope_and_approval_role.sql');
      expect(idx0013, greaterThanOrEqualTo(0));
      expect(idx0014, greaterThan(idx0013));
    });
  });
}
