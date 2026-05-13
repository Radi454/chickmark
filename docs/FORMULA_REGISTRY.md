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

## Validation Boundaries

- Shared percent formulas reject null/invalid denominators and impossible
  count totals rather than emitting misleading percentages.
- UI entry constraints still handle field-level input rules; calculation
  utilities protect model, provider, repository, and dashboard paths.
- Legacy compatibility fields may use `0.0` as a display fallback when a model
  API cannot return `null`, but source percentage helpers treat invalid values
  as absent.
