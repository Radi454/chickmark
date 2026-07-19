# Quickstart: Dashboard Intelligence Acceptance

## 1. Scope isolation

1. Create two customers and hatcheries with `H1`, `S1`, and `H1` machine labels.
2. Record different values for each.
3. Open portfolio mode and confirm no pooled station corrective triage appears.
4. Select one customer/hatchery and confirm all comparisons and alerts belong only to it.

## 2. Freshness and coverage

1. Seed current, aging, stale, and same-day Govee captures.
2. Confirm timestamp ordering selects the latest recording.
3. Confirm stale captures remain visible as history but do not count as active alerts.
4. Open a partial station and confirm sample, missing-data, photo, station-completion, and sync coverage.

## 3. Aggregation and canonical derivation

1. Save unequal sample-size Pasgar/weight/breakout rows.
2. Confirm each metric follows its declared policy and shows its basis.
3. Inject a raw/aggregate mismatch and confirm the quality flag detects it.
4. Edit/save locally and confirm the canonical write path repairs the cache.
5. Confirm all-age results remain equal-age averages.

## 4. Findings, history, and actions

1. Record two comparable visits with one persistent and one improving breach.
2. Confirm the attention section classifies and consolidates them correctly.
3. Open a finding and navigate to available source context.
4. Create an action offline, assign it, set a due date, add notes, and resolve it.
5. Synchronize to another device and confirm lifecycle/history survives.

## 5. Performance, responsive layout, Arabic, and accessibility

1. Run the dashboard repository query-count test for a representative dataset.
2. Verify no per-age or per-capture loop remains.
3. Render phone and 1280px desktop layouts in English and Arabic.
4. Verify no overflow, no large unused comparison region, and no untranslated static dashboard text.
5. Traverse filters, stations, chart/table toggles, findings, and actions by keyboard and semantics tests.
