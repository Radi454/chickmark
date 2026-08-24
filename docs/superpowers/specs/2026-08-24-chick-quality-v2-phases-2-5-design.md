# Chick Quality V2 Phases 2–5 Design

## Goal

Complete the approved Chick Quality V2 architecture without losing historical
data, silently merging concurrent samples, or breaking offline-first clients.
Each phase is independently revertible and verified before the next phase
starts. No migration is applied to the live Supabase project as part of this
work.

## Existing Baseline

Phase 0 and Phase 1 are committed at `d356eb9`. SQLite is the working store and
Supabase is a dirty-tracked mirror. Chick data currently lives in the
`chick_quality` and `chick_weights` panel tables. `chick_quality` contains
several biological domains in one wide row and stores raw series/tallies in
JSON alongside cached summaries. Existing hierarchy columns and dashboard
queries remain active compatibility surfaces.

`tool/agent_schema/station_registry.json` is the metadata and validation source
used to generate Dart and TypeScript registry artifacts. Phase 1 added
warning-only registry checks, but normal UI persistence and agent intake do not
yet share one complete validation/quality pipeline.

## Phase Boundaries

### Phase 2 — Identity, Scope, Domain, and Provenance

Phase 2 adds a shared V2 identity envelope to `chick_quality` and
`chick_weights` locally and remotely:

- `domain`: exact registry schema key. New weight samples use
  `chicks.weights`; existing combined quality rows use
  `chicks.legacy_combined`.
- `schemaVersion`: registry schema version used to interpret the sample.
- `scopeType` and `scopeKey`: normalized scope identity while existing
  hierarchy columns remain populated for compatibility.
- `replicate`: positive, deterministic ordinal among samples sharing domain,
  session, and scope.
- `sampleKey`: immutable logical identity key derived once from domain,
  session, scope, and replicate. It is unique within a customer and is never
  derived from a transient draft id.
- provenance: `source`, `captureMethod`, `createdBy`, `deviceId`,
  `sourceRefId`, and `observedAt`.

The persisted row `id` is minted once and reused after reload. Save paths must
look up an already persisted sample by `sampleKey`, not by draft id or mutable
hierarchy. A different id with the same scope is preserved by allocating the
next replicate and receives a duplicate-scope resolution flag; it is never
absorbed, overwritten, or tombstoned. Agent and human samples therefore
coexist.

Backfill is additive and deterministic. Existing ids are retained. Existing
rows are ordered by stable creation/id data within each customer/session/domain
and normalized scope, then assigned distinct replicate/sample keys. Blank
legacy hierarchy is represented explicitly in the normalized scope key rather
than guessed. The interim Phase 1 hierarchy uniqueness constraint is replaced
only after every row has a non-null unique sample key.

The registry generator emits one bidirectional persistence mapping used by
normal save/load and agent intake. Generated artifacts include field-to-column
and column-to-field mappings plus the existing schema metadata. The Phase 0
round-trip test protects the generated mapping.

### Phase 3 — Registry Validation and Data Quality

Phase 3 makes the generated registry the single authority for Chick validation
and quality classification. Dart and TypeScript adapters expose equivalent
validation results and share registry-defined types, ranges, choices,
dependencies, and completeness rules.

Results have three tiers:

- `BLOCK`: structural failures that prevent correct identity or storage, such
  as a missing domain, invalid schema version, impossible scope, blank required
  non-pool scope key, or malformed stable identity.
- `WARN`: biologically or operationally invalid/suspicious measurements.
  Persistence remains allowed.
- `FLAG`: completeness gaps, missing raw evidence, outliers, derived-cache
  mismatches, scope mismatch, and conversions. Persistence remains allowed.

Every write recomputes and persists `qualityStatus` and `qualityFlags`. Flags
are stable machine-readable codes stored as JSON. Explicit zero remains
different from missing. Incomplete samples remain saveable and usable offline.
The UI surfaces warnings without creating new field-work blockers. Agent intake
uses the same classification before approval/persistence.

### Phase 4 — Raw Observations and Domain Samples

Phase 4 creates `chick_quality_observation` locally and remotely. Each row has
a stable id, owning sample id/customer/session/domain, observation kind
(`series`, `tally`, or `ordinal`), key and optional ordinal, canonical numeric
or text value, unit, quality flags, optional source override, observed time,
and the standard dirty-sync metadata.

Observations become the raw source of truth for:

- chick weights;
- YFBM chick/egg weight pairs;
- CVT position temperatures;
- Pasgar defect tallies;
- PM lesion tallies and severity;
- culled-chick defect counts.

Writes are transactional: replace the domain's observation set, derive cached
wide/JSON columns from those persisted observations, and mark parent and child
rows dirty together. Reads prefer observations when present and fall back to
legacy JSON/wide values when no observation set exists. During transition the
app dual-writes both representations so existing dashboards and older clients
continue to work.

Touching an existing `chicks.legacy_combined` sample lazily creates per-domain
samples only for domains actually present/touched. The legacy parent remains
readable and is not bulk rewritten. Deterministic source references make the
lazy operation idempotent and prevent repeated splitting. Photos continue to
attach to the real domain sample and may also reference an observation where
the evidence is observation-specific.

Sync orders parents before observations on push and observations before parents
on delete. Pull-only clients continue to pull both. Dirty cutoffs protect edits
that land during a sync acknowledgement. Cloud RLS matches the owning parent
customer authorization and rejects cross-tenant parent/customer combinations.

### Phase 5 — Evidence-Based Cleanup

Phase 5 starts with a repository-wide reader/writer inventory and migration
safety proof. A compatibility field is removed only when all of these are true:

1. code search and tests prove zero runtime readers;
2. every persisted row has a safe V2 replacement;
3. old-client/backward-compatibility requirements no longer need the field;
4. local and cloud migrations can remove it without discarding the only copy of
   user evidence.

If any condition is false, the field and its schema support stay in place and
the final report explains why. Likely retained items include
`chicks.legacy_combined` support and raw JSON/wide caches while mixed-version
clients and untouched legacy rows exist. Cleanup may still remove genuinely
dead hand-written mapping or validation code after generated replacements have
complete coverage.

## Data Integrity and Conflict Rules

- Row ids and sample keys are immutable after first persistence.
- A scope collision creates or preserves a replicate; it never overwrites a
  differently identified row.
- Backfills never infer biological measurements, provenance, or missing
  hierarchy.
- Deletes continue through tombstones, child before parent.
- Remote pull conflict handling never replaces a newer local dirty row.
- Additive migrations tolerate old and divergent schemas through existence and
  column checks.
- Existing hierarchy columns remain populated for current consumers.
- There is no individual Chick entity.

## Verification and Review

Each phase follows red-green-refactor cycles for risky behavior, updates
`docs/LIVING_SPEC.md`, adds a dated top entry to `docs/CHANGELOG.md`, and is
committed separately. Verification includes the narrow Flutter model,
repository, migration, UI, dashboard, sync, security/RLS, and agent tests plus
`flutter analyze`. Supabase SQL is exercised only in the repository's
ephemeral PostgreSQL harness.

After each phase, an independent reviewer evaluates correctness, data
integrity, migration safety, offline sync, backward compatibility, and test
adequacy. Critical and Important findings are fixed and reverified before the
next phase begins. Existing unrelated failures are reported separately and are
not hidden by weakening tests.
