# Data Model: Dashboard Intelligence and Actionability

## DashboardScope

- `customerId`: nullable only in portfolio mode.
- `hatcheryId`: nullable only in portfolio/customer-summary mode.
- `flockId`: optional operational narrowing.
- `bmkAge`: optional legacy/global compatibility value.
- `sessionId`: optional exact-visit narrowing.
- `mode`: `portfolio` or `operational`.

Validation:

- Detailed comparison, triage, historical pairing, and actions require operational mode.
- Customer-role users cannot change `customerId` outside their assignment.
- A selected hatchery must belong to the selected customer.

## MetricObservation (derived)

- Source: `tableName`, `rowId`, `sessionId`, optional `fieldKey`.
- Scope: customer, hatchery, flock, station, sector, hierarchy segments.
- Metric: stable key, localized label key, value, display unit.
- Basis: optional numerator, denominator, sample count, aggregation policy.
- Context: observation time, flock/BMK age, benchmark value/source.
- Quality: missing raw input, inconsistent cache, invalid denominator, stale, sync failed, incomplete evidence.

Relationships:

- Many observations derive from one panel row.
- Observations are grouped into sector leaves and historical series.
- No observation is independently persisted or synchronized.

## DataQualitySummary (derived)

- Latest observation time and freshness state.
- Contributing row/sample/age counts.
- Completed/selected station counts when a latest session exists.
- Present/expected evidence count.
- Missing metric count and quality flags.
- Worst sync state and section error.

## HistoricalComparison (derived)

- Metric/scope identity.
- Latest and previous observation/session/date.
- Signed delta and trend classification.
- Condition lifecycle: new, persistent, improving, worsening, resolved, insufficient.
- Compatibility rule: same customer, hatchery, flock when selected, station, sector, metric, and stable hierarchy scope.

## ConsolidatedFinding (derived)

- Stable `findingKey` from operational scope and correlated source metric keys.
- Severity, rank score, confidence, freshness, persistence.
- Probable-cause label and advice.
- Source observations and available navigation target.
- Related persisted action, if any.

## DashboardAction (persisted and synchronized)

- Identity: `id`, `findingKey`.
- Scope: `customerId`, `hatcheryId`, optional `flockId`.
- Source: optional `sessionId`, `panelName`, `panelRowId`, `fieldKey`, `metricKey`.
- Workflow: `title`, `description`, `priority`, `status`, `ownerId`, `ownerName`, `dueAt`.
- History: `firstObservedAt`, `lastObservedAt`, `resolvedAt`, `resolutionNotes`, optional `resolutionPhotoId`, `recurrenceOfId`.
- Audit/sync: `createdBy`, `createdAt`, `updatedAt`, `syncStatus`, `dirtyAt`, `lastSyncedAt`, `syncError`.

State transitions:

- `open -> in_progress -> resolved`
- `open <-> in_progress`
- `resolved -> reopened`
- Reappearance after a resolved action may create a new action with `recurrenceOfId`.

Deletion:

- User deletion queues a sync tombstone.
- Customer deletion removes actions before the customer.
- Source-row deletion does not erase the action; source links become unavailable while history remains.

## BenchmarkTarget (existing, extended usage)

- Existing operational standard fields remain authoritative for global and hatchery overrides.
- Dashboard target resolution carries target source and timestamp context.
- Govee target metric keys join this same registry with hardcoded poultry defaults used only as transparent fallback.
