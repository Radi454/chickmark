# Chick cloud rollout requiring explicit approval

Project: kgucchapksiiqxmiutsz (current ChickMark Supabase mirror).

The live 39d2560 client synchronizes the QA Egg, Setter, Hatcher and Hatch
stations. Chicks remains Failed because both chick_quality and chick_weights
request 13 missing columns; raw observations request an absent relation.
Cloud SQL and API logs confirm all three V2 migration versions are absent.
This is not a missing QA session or parent reference: they already exist.

## Exact proposed release

Apply these existing repository migrations in order, after checking their
preconditions and taking a recoverable snapshot of the affected rows:

1. `20260824033958_chick_quality_v2_phase2_identity.sql`: 11 additive identity/
   provenance columns on each main table, deterministic identity backfill,
   uniqueness indexes and identity guards. Existing sample IDs stay unchanged.
2. `20260824045930_chick_quality_v2_phase3_quality_classification.sql`: two
   quality classification fields, conservative cache backfill and validation.
3. `20260824061534_chick_quality_v2_phase4_raw_observations.sql`: normalized
   observations table, owner validation, existing customer-scoped read/write
   policies, observation-linked photo validation and transactional agent
   approval wrapper. Authenticated clients get table access restricted by RLS.

The current cloud has 8 chick_quality rows and 5 chick_weights rows. This
rollout updates their identity/classification metadata; it is not limited to
the QA visit. It does not delete or merge existing samples. It adds tables,
columns, indexes, triggers and constrained API access. Inspect legacy identity
collisions and all referenced tables/functions before applying; abort on an
unmet precondition. The Phase 2 migration has non-idempotent constraint adds,
so use migration history and do not blindly rerun it.

## Approval and execution history

Phase 3 explicitly says: “This migration is intentionally a repository file
only; it is not applied to a live project by the implementation workflow.”
Phase 4 says: “Migration file only; do not apply to a live project from the
development workflow.” This release is wider than the authorized QA deletion
workflow and affects existing cloud records. The human subsequently explicitly approved this rollout. It was applied and
verified; the final results are recorded in report.md.

## Required verification after approval

- Check all 13 existing rows retain their original IDs and measurements.
- Verify both main tables contain every expected client column, identity
  constraints, and their customer-scoped RLS policies.
- Verify raw observations table ownership rules, photo linkage and grants.
- Run security advisors and review new findings against the prior baseline.
- Retry QA Chicks through the live app; require both cloud parent rows and
  observations to exist and the visit to display Synced at 5/5 stations.
- Reopen the QA record and confirm PASGAR sample size 50, the full 80-leaf
  hierarchy, deletion isolation and sibling measurements still agree.

The approved release is now verified: the QA visit displays 5/5 stations and
Synced, with live Chick parents and the sample-size observation present. Native
camera and second-device UI testing remain outside the verified coverage.
