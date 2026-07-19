# Research: Dashboard Intelligence and Actionability

## Decision 1: Operational scope requires a concrete customer and hatchery

**Decision**: Treat a null customer or hatchery as portfolio mode. Portfolio mode may show counts and freshness by organization but cannot run detailed station triage. Operational comparison queries include both customer and hatchery; flock remains optional.

**Rationale**: Existing house/machine labels are only unique inside operational context. A hatchery column already exists on sessions, panel rows, Govee captures, and BMK overrides.

**Alternatives considered**: Prefix every group label with customer/hatchery while retaining mixed triage. Rejected because corrective advice across organizations is still misleading and hard to scan.

## Decision 2: Derive the analytics read model instead of persisting it

**Decision**: Batch-load each unique panel table once and map rows into normalized `MetricObservation` and sector leaf structures in memory. Cache by dashboard scope. Derive periods and historical pairs from that cache.

**Rationale**: Panel rows remain authoritative, offline-safe, and already synchronized. A persisted observation table would duplicate calculated state and require additional conflict handling.

**Alternatives considered**: SQLite materialized table or SQL UNION view. A table duplicates truth; a wide UNION view is brittle across panel-specific schema changes and does not simplify metric-specific derivation.

## Decision 3: Aggregation is declarative per metric

**Decision**: Add `ratioOfSums`, `sampleWeightedMean`, `equalGroupMean`, `sum`, and `latest` policies plus optional numerator/denominator columns. Keep `traySize` compatibility for breakout metrics. Keep equal-age aggregation as a distinct approved longitudinal rule.

**Rationale**: Different poultry metrics have different valid denominators. Implicit fallback to simple means hides important analytical assumptions.

**Alternatives considered**: Infer policy from format or column names. Rejected because names cannot reliably express business calculation rules.

## Decision 4: Raw inputs are authoritative and caches are canonicalized on write

**Decision**: Introduce a pure panel aggregate deriver invoked before local panel-row writes. It recalculates supported summaries from raw JSON/count inputs and emits quality flags for incomplete or inconsistent inputs. Remote rows are checked but not silently rewritten when the remote row wins; quality is surfaced until the next authorized edit.

**Rationale**: This closes independent-writability for local writers without manufacturing local conflicts during pull.

**Alternatives considered**: Drop aggregate columns. Rejected because current dashboards, sync payloads, and compatibility paths depend on them.

## Decision 5: Govee freshness uses recording timestamps and governed targets

**Decision**: Choose latest capture by `endedAt`, then `startedAt`, then `updatedAt`, then capture date. Default freshness is current through 48 hours, aging through 7 days, and stale afterward unless a configured operational standard overrides it. Stale/invalid readings remain visible as history but do not emit active triage.

**Rationale**: A calendar date cannot order multiple same-day captures and "latest" does not mean operationally current.

**Alternatives considered**: Hide old captures entirely. Rejected because historical evidence is still useful.

## Decision 6: Findings are derived; actions are synchronized records

**Decision**: Consolidated findings are deterministic outputs keyed by scope and source metrics. `dashboard_actions` persists ownership/status/due date/notes/recurrence/resolution evidence and sync metadata. Actions reference a stable finding key and optional source session/panel/row/field.

**Rationale**: Derived findings can be recomputed; human decisions and resolution history cannot.

**Alternatives considered**: Persist every generated alert. Rejected because benchmark/config changes would leave stale duplicated alerts.

## Decision 7: Partial failures stay sectional

**Decision**: Providers retain last successful data and expose per-section errors with retry. Full-screen loading is reserved for first entry with no cached content.

**Rationale**: A single repository failure should not make healthy stations appear empty or in target.

## Decision 8: Accessibility and Arabic are implementation requirements

**Decision**: Add semantics to icon-only toggles, collapse headers, attention cards, and action controls; provide non-color text/icon severity; localize all static dashboard strings through the existing custom catalog; test phone/desktop and Arabic/English.

**Rationale**: The current Flutter web DOM cannot be used as proof of assistive-technology support, and mixed-language metric labels reduce comprehension.
