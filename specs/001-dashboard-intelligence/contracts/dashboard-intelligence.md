# Dashboard Intelligence Contracts

## Repository contract

`DashboardFilter` carries customer, hatchery, flock, age, and optional session. `isOperational` is true only with customer and hatchery.

`ScopeComparisonRepository.loadBundle(filter, sectors)`:

- Reads each unique panel source table at most once.
- Returns normalized observations, leaves by sector, periods by sector, quality by sector, and latest/previous comparable snapshots.
- Never returns data outside the requested customer/hatchery scope.
- Preserves null as missing; never converts missing to zero.

`GoveeCaptureRepository.getSummariesForDashboard(...)`:

- Returns capture models and inline chart readings without a per-capture query.
- Orders by best available recording timestamp.

`DashboardActionRepository`:

- Create/update/resolve/reopen/delete actions offline.
- Query actions by operational scope/finding.
- Expose dirty rows and synced/failed marking for startup sync.
- Apply remote rows using existing conflict policy.

## Provider contract

`DashboardProvider` owns cascade pick lists, portfolio/operational mode, Govee summaries, action lifecycle, section errors, and global freshness/sync summary.

`ScopeComparisonProvider` owns per-sector age/layer/table/chart state plus batch observations, quality, historical comparisons, and derived findings. Existing local sector-selection state remains independent.

Changing customer clears hatchery and flock. Changing hatchery clears incompatible flock/session state. Changing flock preserves hatchery.

## UI contract

- Portfolio mode shows organization-level summary and a clear prompt to choose customer/hatchery for operational analysis.
- Operational mode renders a quality strip followed by "What needs attention", Govee, and station sections.
- Findings display severity, freshness/confidence, latest/previous context, action state, and source navigation.
- Icon-only controls have tooltip and semantic label/state.
- Static strings use localization keys; user-entered names remain unchanged.

## Sync contract

- `dashboard_actions` pushes after parent scope/session data and before tombstones.
- Pull occurs after customers, hatcheries, flocks, and sessions.
- Remote deletes apply before local action push.
- Remote-table absence is surfaced as an action sync failure without breaking other synchronization.
