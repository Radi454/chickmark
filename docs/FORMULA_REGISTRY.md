# Formula Registry

Current formula source of truth for ChickMark calculations. Code remains the
primary source of truth; this registry records the intended shared behavior so
screens, providers, persistence, dashboards, and tests do not drift.

## Shared Utilities

- `CalculationUtils.roundTo`: decimal rounding uses Dart `toStringAsFixed`
  semantics and returns a parsed `double`.
- `CalculationUtils.percentOf`: returns `(count / total) * 100`, rounded to the
  requested decimal places. It returns `null` for null values, zero or negative
  totals, negative counts, or counts greater than totals unless
  `allowAbove100` is explicitly set.
- `CalculationUtils.stdDev`: sample standard deviation by default (`n - 1`
  denominator). Returns `0.0` for fewer than two values.
- `CalculationUtils.populationStdDev`: population standard deviation (`n`
  denominator) for explicit population-only use.
- `CalculationUtils.cvPercent`: `sample standard deviation / mean * 100` by
  default. Returns `0.0` when the mean is zero or no values are present.

## BMK Age

- Current flock age days comes from either `flockAgeWeeks * 7` or the day
  difference between the audit date and flock entry date.
- Calculated breakout/storage BMK days:
  `current flock age days - storage days - incubation offset days`.
- Incubation offsets:
  - Egg storage: 21 days.
  - Fresh Egg breakout: 0 days.
  - Candled Egg breakout: entered candled age, defaulting to 10 days.
  - Residue / Hatch Day breakout: 21 days.
- BMK benchmark lookup uses `BmkAgeCalculator.benchmarkWeekForDays`, which
  rounds to the nearest week.
- Legacy/display week fields use `BmkAgeCalculator.displayWeekForDays`, which
  ceilings partial weeks and returns `0` for non-positive day values.

## Pasgar

- The UI tracks six defect categories.
- The final Pasgar score uses the first five scored defect categories.
- Feather development is retained as a tracked/displayed category but does not
  reduce the score.
- Score formula:
  `((sample size * 10) - scored defect total) / sample size`.
- Each scored defect count is clamped to the sample size before scoring.
- The displayed score is rounded to one decimal and clamped from `5.0` to
  `10.0`. A non-positive sample size returns `0.0`.
- Pasgar defect percentages use `defect count / sample size * 100` and reject
  negative counts or counts greater than the sample size.

## CV and Standard Deviation

- Egg weights, chick weights, EST/CVT, and Govee Temp/RH all use sample
  standard deviation by default.
- CV is `sample SD / average * 100`.
- Station-facing CV values generally round to one decimal place.
- Govee saved summary SD and CV values round to two decimal places.

## Breeder Weighing and Uniformity

`BreederWeighingService` (`lib/services/breeder/breeder_weighing_service.dart`,
breeder-flock-performance ticket 13) derives a weighing session's mean
weight, uniformity, and coefficient of variation from its individual sample
weights, and compares the mean against the Ross 308 body-weight benchmark.

- Mean weight: `CalculationUtils.average`, rounded via `roundTo`. `null`
  (not `0`) for zero samples.
- Uniformity: percentage of samples within
  `+/- BreederWeighingService.weightUniformityWindow` (`0.10`, a named
  constant — not a magic number) of the *sample* mean, via
  `CalculationUtils.uniformityPercent(values, mean * 0.9, mean * 1.1)`.
  This is the same +/-10%-of-mean weight-uniformity window
  `panel_aggregate_deriver.dart` and `station_adapter.dart`'s
  `_uniformity10` already use for chick/egg weight uniformity elsewhere in
  the app — the design doc does not fix a uniformity definition (section
  9), so this convention was chosen specifically to match those existing
  call sites rather than invent a new one. `null` for zero samples; a
  single sample is 100% uniform (trivially within any window of its own
  value).
- Coefficient of variation: `sample stdDev / mean * 100` via
  `CalculationUtils.stdDev(values, sample: true)`, matching this
  registry's general CV convention above. **Deliberate, documented
  deviation from `CalculationUtils.cvPercent`:** `cvPercent` returns `0.0`
  for fewer than two values or a zero mean; `BreederWeighingService`
  instead returns `null` in those cases (this feature's blank-not-zero
  convention, design section 7.2) by computing the same formula directly
  from `stdDev`/`average` rather than calling `cvPercent`. `cvPercent`
  itself is unchanged — other features that call it keep its `0.0`
  fallback exactly as before.
- Benchmark comparison: the Ross 308 `body_weight_g` metric (ticket 03) is
  looked up for the flock's breed, the session's sex, and the flock's age
  at the session date, on the official (age-based) comparison axis only
  (`BreederFlockLifecycleService`, ticket 06). The profile id, its
  `guideVersion` (a denormalized snapshot, since a profile can later be
  archived), the axis kind, and any axis offset are all persisted on the
  session row. Ross 308 publishes no uniformity or CV target at all
  (ticket 03), so the UI always shows uniformity/CV without a target,
  never inventing one or comparing against nothing.

## Hatchability, Fertility, and HOF

- Hatchability: `hatched chicks / total eggs set * 100`.
- Culled and dead percentages use `total eggs set` as the denominator.
- Tray fertility: `(tray sample size - infertile count) / tray sample size *
  100`.
- Residue batch fertility is the simple unweighted average of valid tray
  fertility percentages.
- HOF: `hatchability / fertility * 100`.
- HOF intentionally allows values above 100. Other percent-of-total formulas do
  not unless explicitly allowed.

## Breakout Percentages

- Breakout tray percentages use `count / tray size * 100`.
- Counts below zero, zero or negative tray sizes, and counts greater than tray
  size are invalid for percentage output.
- Dashboard egg-breakout SQL applies the same tray-count guard before averaging
  percentages, preventing impossible category percentages from entering trend
  and average cards.

## Dashboard Aggregation Policies

- `ratioOfSums`: `sum(numerator) / sum(denominator) * 100`. Used when raw
  counts and their true denominators are available, including breakout and
  Shell UV ratios.
- `sampleWeightedMean`: `sum(value * sampleSize) / sum(sampleSize)`. Used for
  sample-size-sensitive averages such as weights, Pasgar, EST, and CVT.
- `equalGroupMean`: arithmetic mean of the displayed groups. This is explicit;
  it must not be substituted for a sample-weighted mean.
- `sum`: total of the available values.
- `latest`: last non-null value in date-ordered source rows.
- All-age cumulative summaries preserve equal-age weighting: calculate each
  age independently, then average the available age results so an age with more
  recorded samples does not dominate another age.

## Canonical Derived Caches

Raw arrays/counts remain authoritative. Before a local panel row is persisted,
`PanelAggregateDeriver` recalculates EST/CVT average and CV, egg/chick weight
sample size/average/uniformity/CV, Pasgar percentages/final score, Shell UV
ratios, and breakout percentages plus hatchability/fertility/HOF. Corresponding
summary columns are caches, not independent inputs. Analytics reads compare the
stored cache with a fresh derivation and attach `aggregate_drift` when values
materially differ.

## Validation Boundaries

- Shared percent formulas reject null/invalid denominators and impossible
  count totals rather than emitting misleading percentages.
- UI entry constraints still handle field-level input rules; calculation
  utilities protect model, provider, repository, and dashboard paths.
- Legacy compatibility fields may use `0.0` as a display fallback when a model
  API cannot return `null`, but source percentage helpers treat invalid values
  as absent.
