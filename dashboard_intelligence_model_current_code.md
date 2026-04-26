# Dashboard Intelligence Model From Current Code

This document is based only on the current codebase as of 2026-04-25.

Primary code sources used:
- `lib/data/models/audit_model.dart`
- `lib/data/models/audit_session_model.dart`
- `lib/core/utils/calculation_utils.dart`
- `lib/core/constants/app_thresholds.dart`
- `lib/features/audits/providers/audit_provider.dart`
- `lib/data/repositories/audit_repository.dart`
- `lib/features/dashboard/models/visit_session_summary.dart`
- `lib/features/dashboard/models/chick_quality_models.dart`
- `lib/features/dashboard/models/hatch_analysis_models.dart`
- `lib/features/dashboard/models/egg_storage_models.dart`
- `lib/features/dashboard/models/egg_breakout_models.dart`
- `lib/features/audits/screens/egg_storage_screen.dart`
- `lib/features/audits/screens/hatch_analysis_screen.dart`
- `lib/features/audits/screens/setter_optimizing_screen.dart`
- `lib/features/audits/screens/hatcher_optimizing_screen.dart`
- `lib/features/audits/widgets/tabs/cha_env_tab.dart`
- `lib/features/audits/widgets/tabs/pasgar_tab.dart`
- `lib/features/audits/widgets/tabs/weights_tab.dart`
- `lib/features/audits/widgets/tabs/yfbm_tab.dart`
- `lib/features/audits/widgets/tabs/cvt_tab.dart`
- `lib/features/audits/widgets/tabs/pm_necropsy_tab.dart`

## Scope Notes

- The app is already structured around visit sessions in `lib/data/models/audit_session_model.dart`, with stations completed inside one visit.
- The current dashboard and repository layer already support some richer outputs than the current input screens expose.
- Where that happens, this document distinguishes:
  - actively captured today
  - supported in schema or repository path but not fully surfaced in the current workflow
- The session diagnostic engine in `lib/services/diagnostics/diagnostic_engine.dart` is currently a placeholder and returns no computed findings. Current visit findings therefore come mainly from persisted session JSON or fallback heuristics in `lib/features/dashboard/models/visit_session_summary.dart`.

## Part 1: Current Analytics Outputs By Station

### 1. Egg Storage

Primary code:
- Capture: `lib/features/audits/screens/egg_storage_screen.dart`
- Data fields: `lib/data/models/audit_model.dart`
- Calculations: `lib/core/utils/calculation_utils.dart`
- Thresholds: `lib/core/constants/app_thresholds.dart`
- Trend aggregation: `lib/data/repositories/audit_repository.dart`
- Dashboard models: `lib/features/dashboard/models/egg_storage_models.dart`

#### Raw measurements collected

- Shell temperature.
- Shell temperature photo.
- Egg storage temperature grid across 9 positions.
- Per-cell temperature grid photos.
- Egg turning times.
- UV tray inspection counts by tray:
  - tray total eggs
  - affected eggs
- UV tray photos.
- UV egg inspection counts:
  - sample size
  - cuticle damage
  - washing evidence
  - fecal contamination
  - mottled eggs
  - other defects
- UV inspection photos.
- Egg quality percentages:
  - cracked
  - broken
  - misshaped
  - pale shell
  - rough texture
  - floor egg
- Egg weights sample list.
- Storage checklist observations:
  - egg orientation
  - tray spacing
  - cooler proximity
  - wall proximity
  - condensation

#### Calculated metrics

- Shell temperature status and zone via `shellTempStatus` and `shellTempZone` in `lib/core/utils/calculation_utils.dart`.
- Egg storage temperature average.
- Egg storage temperature CV%.
- UV affected percentage per tray.
- Average UV affected percentage across trays.
- Egg weight average.
- Egg weight uniformity%.
- Egg weight CV%.
- Egg weight low and high margins versus the average.

#### Derived KPIs

- Shell temperature compliance versus optimal storage window.
- Egg storage temperature grid stability.
- Egg weight uniformity quality.
- Egg weight variability risk.
- UV defect burden.
- Egg quality defect burden from the percentage fields.

#### BMK comparisons

- `AuditModel` supports `esEggBmkAge` and `esEggBmkWeight`.
- Current code stores benchmark context for egg weights, but current Egg Storage screen does not surface a full BMK delta workflow the way Chick Weights does.
- Dashboard models can carry benchmark references, but current repository outputs are stronger on trends than on BMK comparison for Egg Storage.

#### Warnings and threshold outputs

- Shell temperature optimal band is effectively 19-21 C from `lib/core/constants/app_thresholds.dart`.
- Shell temperature out-of-range alerts are generated on save in `lib/features/audits/providers/audit_provider.dart`.
- UV tray severity color logic exists in the screen:
  - low concern at lower affected%
  - elevated concern as affected% rises
- Egg weight CV warning logic uses the shared CV threshold.
- Egg weight uniformity warning logic uses shared uniformity thresholds.
- Visit fallback scorecard in `lib/features/dashboard/models/visit_session_summary.dart` flags:
  - shell temperature above 21 C as red
  - shell temperature below 19 C as amber

#### Findings and diagnostic outputs

- Storage checklist answers can support structured findings, but current code does not aggregate them into dashboard findings yet.
- UV observations and egg quality percentages are captured but not currently summarized into a visit-level diagnostic narrative.

#### Machine-level outputs

- None in the machine-comparison sense.
- Egg Storage is location-condition oriented, not machine-comparison oriented in current code.

#### Trend-capable outputs

- Egg weight average by date.
- Egg weight uniformity by date.
- Egg weight CV by date.
- Shell temperature by date.
- Egg storage temperature average by date.
- Egg storage temperature CV by date.
- CO2 trend is supported in repository/dashboard paths if data exists in records, but the current Egg Storage screen is not the main active source for that value today.

#### Analytics interpretation

- Egg Storage currently acts as the leading-condition station for:
  - temperature control quality
  - egg quality burden
  - shell quality exposure
  - weight uniformity readiness before incubation

### 2. Chick Quality

Primary code:
- Capture tabs: `lib/features/audits/widgets/tabs/cha_env_tab.dart`, `pasgar_tab.dart`, `weights_tab.dart`, `yfbm_tab.dart`, `cvt_tab.dart`, `pm_necropsy_tab.dart`
- Data fields: `lib/data/models/audit_model.dart`
- Calculations: `lib/core/utils/calculation_utils.dart`
- Thresholds: `lib/core/constants/app_thresholds.dart`
- Alerts: `lib/features/audits/providers/audit_provider.dart`
- Trend aggregation: `lib/data/repositories/audit_repository.dart`
- Dashboard models: `lib/features/dashboard/models/chick_quality_models.dart`

#### Raw measurements collected

- CHA environmental data:
  - CO2
  - PM10
  - PM2.5
  - air velocity at 3 spots
  - air inlet temperature
  - air outlet temperature
  - noise level
- Pasgar sample size.
- Pasgar defect counts:
  - low reflex
  - abnormal navel
  - red hocks
  - abnormal beak
  - dirty feathers
- Chick weights sample list.
- Storage days for chick weight benchmarking.
- YFBM rows:
  - chick weight
  - yolk weight
- CVT sample metadata:
  - sample size
  - basket IDs
  - top, middle, bottom temperatures
- PM and necropsy findings:
  - lesion counts and severities across multiple organs or conditions
  - gasping present or not
  - gasping type
  - deformity counts
  - other deformity text
  - suspected cause override field

#### Calculated metrics

- Pasgar final score via `pasgarScore` in `lib/core/utils/calculation_utils.dart`.
- Per-defect Pasgar percentages.
- Chick weight average.
- Chick weight uniformity%.
- Chick weight CV%.
- Chick weight low and high margins versus average.
- YFBM per-row percentage.
- YFBM average%.
- YFBM CV%.
- CVT average temperature.
- CVT CV%.
- CHA average air velocity in repository trend output.
- Visit PM summary in `lib/features/dashboard/models/visit_session_summary.dart`:
  - total lesions
  - total deformities
  - gasping cases
  - overall severity

#### Derived KPIs

- Chick vitality score proxy through Pasgar.
- Chick body weight quality.
- Chick weight uniformity quality.
- Residual yolk absorption quality through YFBM%.
- Pull temperature control quality through CVT average and CV.
- Hatchery environment quality through CHA readings.
- Necropsy burden and severity.

#### BMK comparisons

- Chick Weights uses BMK age and BMK chick weight references in `lib/features/audits/widgets/tabs/weights_tab.dart`.
- Current code shows benchmark reference but does not compute a full dashboard delta KPI from actual versus BMK chick weight.
- CVT, Pasgar, YFBM, and CHA currently rely more on threshold logic than on BMK tables.

#### Warnings and threshold outputs

- Pasgar defect-level warning when a defect percentage exceeds 20%.
- Pasgar color logic:
  - green for high scores
  - orange for marginal scores
  - red for lower scores
- CVT threshold band is 103-105 F from `lib/core/constants/app_thresholds.dart`.
- YFBM expected band is 8-10%.
- Shared CV threshold is used for both weight variability and YFBM variability.
- Audit provider generates CVT out-of-range alerts on save.
- Visit fallback scorecard flags:
  - Pasgar below 7 as amber
  - chick weight CV above 8 as red

#### Findings and diagnostic outputs

- PM and necropsy is the richest explicit diagnostic station in current code.
- Captured outputs support diagnostic findings around:
  - lesion burden
  - deformity burden
  - gasping pattern
  - severity concentration
- Suspected cause can be captured manually.
- Current auto-diagnostic engine does not yet populate inferred causes globally.

#### Machine-level outputs

- No machine comparison inside Chick Quality itself.
- Chick Quality is the biological outcome station most useful for evaluating upstream machine performance.

#### Trend-capable outputs

- Chick average weight by date.
- Chick uniformity by date.
- Chick CV by date.
- YFBM average and CV by date.
- CHA CO2 by date.
- CHA PM10 by date.
- CHA PM2.5 by date.
- CHA air velocity by date.
- CHA noise level by date.
- Pasgar aggregate metrics are available as averages.
- CVT aggregate metrics are available as averages.

#### Analytics interpretation

- Chick Quality is the strongest lagging biological-outcome station currently in the app.
- It closes the loop between upstream storage or incubation conditions and final chick condition.

### 3. Hatch Analysis

Primary code:
- Capture: `lib/features/audits/screens/hatch_analysis_screen.dart`
- Data fields: `lib/data/models/audit_model.dart`
- Calculations and reconciliation: `lib/features/audits/providers/audit_provider.dart`, `lib/core/utils/calculation_utils.dart`
- Trend aggregation: `lib/data/repositories/audit_repository.dart`
- Dashboard models: `lib/features/dashboard/models/hatch_analysis_models.dart`, `lib/features/dashboard/models/egg_breakout_models.dart`

#### Raw measurements collected

- Setter ID.
- Hatcher ID.
- Storage days.
- Total eggs set.
- Hatch budget counts:
  - healthy chicks
  - culled chicks
  - dead chicks
  - pipped
  - infertile or clear
  - early dead
  - mid dead
  - mid-late dead
  - late dead
  - contaminated or exploders
- Multiple hatch entries for one audit date.

#### Raw measurements supported in schema or repository path but not strongly surfaced in the current Hatch Analysis screen

- Egg breakout counts and metadata:
  - tray size
  - breakout type
  - breakout age
  - trays count
  - infertile
  - early dead
  - mid dead
  - late dead
  - internal pip
  - external pip
  - cracked
  - contaminated
  - malposition
  - exposed brain
  - crossed beak
  - culled or dead

#### Calculated metrics

- Hatch budget sum.
- Reconciliation status versus total eggs set.
- Hatchability%.
- Fertility%.
- HOF%.
- Dead%.
- Culled%.
- Per-category percentages after valid reconciliation.
- Average hatchability across multiple hatches.
- Average culled%.
- Average dead%.
- Average fertility%.
- Average HOF%.
- BMK age derived from flock age and storage days in `lib/features/audits/screens/hatch_analysis_screen.dart`.

#### Derived KPIs

- Core hatch outcome performance.
- Loss distribution across hatch budget categories.
- Fertility efficiency.
- Hatch of fertile efficiency.
- Culls burden.
- Dead-at-hatch burden.
- Reconciliation quality and data integrity.

#### BMK comparisons

- BMK age is derived and stored.
- Breed benchmark references exist in `lib/data/models/bmk_breed_model.dart`.
- Breakout benchmark references exist in `lib/data/models/bmk_egg_breakout_model.dart`.
- Dashboard code compares actual hatch metrics versus BMK references.
- `HatchBenchmarkStatus` logic supports:
  - OK
  - medium deviation
  - high deviation
- Hatch Analysis screen currently shows BMK age context more than full benchmark intelligence.

#### Warnings and threshold outputs

- Hatch budget under-allocation warning.
- Hatch budget over-allocation warning.
- Reconciled versus not reconciled state.
- Visit fallback scorecard flags hatchability below 75 as red.
- BMK deviation status is available for hatch outcome metrics and breakout metrics in dashboard models.

#### Findings and diagnostic outputs

- Hatch budget category distribution is itself a diagnostic output.
- Current code can support diagnosis of where losses are concentrated:
  - infertility
  - embryonic death timing
  - pips
  - contamination
  - culls
  - dead-at-hatch
- Breakout analytics infrastructure is richer than the current form workflow and is underused.

#### Machine-level outputs

- Setter ID and Hatcher ID are captured and link Hatch Analysis outcomes back to machine performance.
- This makes Hatch Analysis the key bridge between process stations and outcome stations.

#### Trend-capable outputs

- Hatchability by date.
- Fertility by date.
- HOF by date.
- Culled% by date.
- Dead% by date.
- Breakout percentages by date and by breakout type.

#### Analytics interpretation

- Hatch Analysis is the most important production-outcome station currently available.
- It should anchor visit-level lagging KPIs and machine outcome attribution.

### 4. Setter Optimizing

Primary code:
- Capture: `lib/features/audits/screens/setter_optimizing_screen.dart`
- Data fields: `lib/data/models/audit_model.dart`
- Calculations: `lib/core/utils/calculation_utils.dart`
- Machine aggregation: `lib/data/repositories/audit_repository.dart`
- Dashboard models: `lib/features/dashboard/models/egg_storage_models.dart`

#### Raw measurements collected

- Setter ID.
- Breed.
- Incubation age.
- Machine type.
- Turning angle.
- CO2.
- CO2 photo.
- EST 9-point temperature grid.
- Per-cell EST photos.

#### Calculated metrics

- EST average.
- EST CV%.
- Machine comparison outputs aggregate:
  - EST average by setter
  - EST CV by setter
  - turning angle by setter

#### Derived KPIs

- Setter temperature control accuracy.
- Setter temperature uniformity.
- Turning settings consistency.
- Setter process control quality.

#### BMK comparisons

- Current code does not implement a strong BMK setter-process benchmark layer.
- Setter relies mainly on threshold compliance rather than benchmark tables.

#### Warnings and threshold outputs

- EST target zone uses 100-101 F helpers in `lib/core/utils/calculation_utils.dart`.
- Visit fallback scorecard flags setter average EST outside 100-101 F as amber.
- No broader setter-specific CO2 alerting is implemented at the same level as CVT and shell temperature save alerts.

#### Findings and diagnostic outputs

- Setter findings currently come mainly from process deviation:
  - hot setter
  - cold setter
  - high setter variability
  - nonstandard turning angle
- No richer automated diagnostic narrative exists yet.

#### Machine-level outputs

- Setter comparison is a first-class machine-level output.
- Current repository query currently returns process metrics only.
- The comparison model has fields for hatch outcomes, but the active query does not yet populate hatchability, fertility, HOF, culled, or dead by setter.

#### Trend-capable outputs

- EST average by setter.
- EST CV by setter.
- Turning angle by setter.
- CO2 trend maps are structurally supported in models but not fully populated by repository output today.

#### Analytics interpretation

- Setter Optimizing is a leading-indicator process-control station.
- Its value rises when linked to Hatch Analysis and Chick Quality outcomes.

### 5. Hatcher Optimizing

Primary code:
- Capture: `lib/features/audits/screens/hatcher_optimizing_screen.dart`
- Data fields: `lib/data/models/audit_model.dart`
- Calculations: `lib/core/utils/calculation_utils.dart`
- Alerts: `lib/features/audits/providers/audit_provider.dart`
- Machine aggregation: `lib/data/repositories/audit_repository.dart`
- Dashboard models: `lib/features/dashboard/models/egg_storage_models.dart`

#### Raw measurements collected

- Hatcher ID.
- Breed.
- Incubation age.
- CO2.
- CO2 photo.
- CVT 9-point temperature grid.
- Per-cell CVT photos.
- Chick panting yes or no.
- Chick panting photo.
- Meconium assessment.
- Transfer day.

#### Calculated metrics

- CVT average.
- CVT CV%.
- Machine comparison outputs aggregate:
  - CVT average by hatcher
  - CVT CV by hatcher
  - meconium status by hatcher
  - transfer day by hatcher

#### Derived KPIs

- Hatcher temperature control accuracy.
- Hatcher temperature uniformity.
- Chick thermal stress proxy from panting.
- Hatch window or holding quality proxy from meconium.
- Transfer timing consistency.

#### BMK comparisons

- No strong BMK hatcher-process benchmark implementation exists today.
- Current logic is primarily threshold-driven.

#### Warnings and threshold outputs

- CVT target zone uses 103-105 F helpers in `lib/core/utils/calculation_utils.dart`.
- Audit provider triggers CVT out-of-range alerts on save.
- Visit fallback scorecard flags hatcher average CVT outside 103-105 F as amber.
- Panting and meconium are captured as risk signals but not transformed into formal severity scores.

#### Findings and diagnostic outputs

- Current diagnostic outputs are mainly:
  - hot or cold hatcher condition
  - nonuniform hatcher temperature
  - panting present
  - abnormal meconium
  - transfer timing context

#### Machine-level outputs

- Hatcher comparison is a first-class machine-level output.
- As with Setter, the comparison model is richer than the current repository query.
- Current query does not yet populate hatchability, fertility, HOF, culled, or dead by hatcher.

#### Trend-capable outputs

- CVT average by hatcher.
- CVT CV by hatcher.
- Meconium status comparison.
- Transfer day comparison.
- CO2 and panting trend maps are structurally supported in models but not fully populated by repository output today.

#### Analytics interpretation

- Hatcher Optimizing is the most immediate leading indicator for final chick condition.
- It is especially important when paired with Chick Quality CVT, Pasgar, YFBM, and PM outputs.

## Part 2: Visit-Level Intelligence From Existing Data

Primary code:
- Session model: `lib/data/models/audit_session_model.dart`
- Session provider: `lib/features/audits/providers/audit_session_provider.dart`
- Visit summary and fallback scorecards: `lib/features/dashboard/models/visit_session_summary.dart`

### Current visit-level outputs already supported

- Visit identity:
  - farm
  - house
  - flock
  - visit date
  - session completion date
- Stations completed within the visit.
- Station status summary through `scorecardJson` or fallback heuristics.
- Visit findings list from persisted `findingsJson`.
- PM summary:
  - lesion burden
  - deformity burden
  - gasping count
  - overall severity
- Hatch budget summary:
  - eggs set
  - healthy chicks
  - culled
  - dead
  - pipped
  - infertile
  - early dead
  - mid dead
  - late dead
  - contaminated
- Companion temperature summary if temperature data is linked to the visit.

### Whole-visit performance indicators that can be built now

- Visit completion score:
  - stations completed out of 5
- Visit biological outcome score:
  - hatchability
  - fertility
  - HOF
  - culled%
  - dead%
  - Pasgar
  - chick weight CV
  - YFBM%
  - PM severity burden
- Visit process-control score:
  - shell temperature compliance
  - egg storage grid stability
  - setter EST compliance
  - hatcher CVT compliance
  - turning angle consistency
  - transfer day consistency
- Visit hygiene or environmental risk score:
  - CHA CO2
  - PM10
  - PM2.5
  - UV affected burden
  - contamination counts

### Cross-station relationships supported by existing data

#### Egg Storage -> Chick Quality

- Egg weight average and uniformity versus chick weight average and uniformity.
- Shell temperature and storage temperature variability versus Pasgar and chick CV.
- UV defect burden and egg quality defect percentages versus culls, deformities, and PM burden.
- Storage days from Hatch Analysis can contextualize Egg Storage to Chick Quality changes.

#### Egg Storage -> Hatch Analysis

- Shell temperature and egg storage grid variation versus hatchability, fertility, HOF, and embryonic loss timing.
- Egg quality defect percentages versus contamination, pips, culls, and dead-at-hatch.

#### Setter Optimizing -> Hatch Analysis

- Setter EST average and CV versus hatchability.
- Setter EST average and CV versus HOF.
- Setter EST average and CV versus embryonic death distribution.
- Turning angle versus hatch outcome quality.

#### Setter Optimizing -> Chick Quality

- Setter EST average and CV versus Pasgar.
- Setter EST average and CV versus chick weight CV.
- Setter EST average and CV versus YFBM%.
- Setter EST average and CV versus PM lesions and deformities.

#### Hatcher Optimizing -> Chick Quality

- Hatcher CVT average and CV versus chick CVT, Pasgar, YFBM, and PM severity.
- Panting presence versus Pasgar and CHA environmental stress.
- Meconium status versus chick quality and hatch window stress.
- Transfer day versus chick condition outcomes.

#### Hatcher Optimizing -> Hatch Analysis

- Hatcher CVT average and CV versus dead-at-hatch, pips, culled, and healthy chicks.
- Hatcher conditions versus final hatch budget distribution.

#### Hatch Analysis -> Chick Quality

- Hatchability and HOF versus Pasgar and chick weight quality.
- Culled and dead percentages versus PM lesion and deformity burden.
- Embryonic loss timing versus downstream chick weakness patterns.

### Proposed visit health score using existing data only

The current data supports a single visit health score built from weighted sub-scores.

#### Suggested score structure

- 30% production outcome score
  - hatchability
  - fertility
  - HOF
  - culled%
  - dead%
- 25% chick biological quality score
  - Pasgar
  - chick weight CV
  - chick uniformity
  - YFBM average
  - CVT average
  - CVT CV
- 25% process-control score
  - shell temperature compliance
  - egg storage temperature CV
  - setter EST compliance
  - setter EST CV
  - hatcher CVT compliance
  - hatcher CVT CV
- 10% environmental and hygiene score
  - CHA CO2
  - PM10
  - PM2.5
  - UV affected burden
  - contamination signals
- 10% pathology and exception score
  - PM severity
  - lesion burden
  - deformity burden
  - gasping presence

#### Score behavior

- Strong outcome data should outweigh perfect process data.
- Severe red conditions in Hatch Analysis or Chick Quality should cap the final visit score even if upstream process stations look acceptable.
- Missing stations should lower confidence, not automatically mean poor health.
- The dashboard should therefore store:
  - visit health score
  - score confidence based on station coverage

## Part 3: Dashboard Decision Outputs From Current Data

### A. Leading indicators

- Shell temperature out of target.
- Egg storage temperature nonuniformity.
- Egg weight nonuniformity before setting.
- UV defect burden.
- Egg quality defect burden.
- Setter EST average out of target.
- Setter EST CV above acceptable spread.
- Turning angle inconsistency.
- Hatcher CVT average out of target.
- Hatcher CVT CV above acceptable spread.
- Panting present.
- Abnormal meconium.
- CHA environmental stress:
  - high CO2
  - high particulates
  - poor airflow
  - high noise

### B. Lagging indicators

- Hatchability.
- Fertility.
- HOF.
- Culled%.
- Dead%.
- Hatch budget loss distribution.
- Pasgar score.
- Chick average weight.
- Chick uniformity.
- Chick weight CV.
- YFBM%.
- PM lesion burden.
- PM deformity burden.
- PM severity burden.

### High-level decision outputs that can be shown now

#### Performance outcomes

- Overall hatch performance.
- Chick quality performance.
- Process-control performance.
- Machine performance quality.

#### Risk indicators

- Current upstream risk to future hatch results.
- Current downstream risk to chick livability or saleability.
- Red-station risk concentration.
- Visit confidence level based on completed stations.

#### Critical findings

- Top biological concern in the visit.
- Top process deviation in the visit.
- Top pathology concern in the visit.
- Top hygiene or environment concern in the visit.

#### Benchmark deviations

- Hatchability versus BMK.
- Fertility versus BMK.
- HOF versus BMK.
- Culled versus BMK.
- Dead versus BMK.
- Breakout deviation versus BMK where breakup data exists.

#### Machine performance comparisons

- Best setter by EST control.
- Worst setter by EST control.
- Best hatcher by CVT control.
- Worst hatcher by CVT control.
- Machine associated with most downstream losses once Hatch Analysis linkage is used.

#### Biological indicators

- Chick vitality.
- Chick weight quality.
- Chick temperature status.
- Residual yolk quality.
- Lesion and deformity burden.

#### Operational indicators

- Reconciled versus unreconciled hatch records.
- Station completion coverage.
- Transfer timing consistency.
- Turning setting consistency.
- Storage handling compliance exposure.

## Part 4: Proposed Analytics Architecture Using Existing Data Only

### Layer 1: Executive Summary KPIs

- Visit health score.
- Score confidence based on station coverage.
- Hatchability.
- HOF.
- Culled%.
- Dead%.
- Pasgar.
- Chick weight CV.
- Chick uniformity.
- Setter process status.
- Hatcher process status.
- Number of red findings.

### Layer 2: Critical Findings And Exceptions

- Stations currently in red or amber.
- Biggest BMK deviation.
- Biggest biological concern.
- Biggest process-control concern.
- Most severe pathology signal.
- Reconciliation exceptions in hatch budget.
- Visit-level exception list driven by threshold breaches and benchmark gaps.

### Layer 3: Station Analytics

- Egg Storage:
  - shell temperature compliance
  - storage grid average and CV
  - egg weight average, uniformity, CV
  - UV burden
  - egg quality defects
- Chick Quality:
  - Pasgar
  - chick weight quality
  - YFBM quality
  - CVT quality
  - CHA environment quality
  - PM burden
- Hatch Analysis:
  - hatchability
  - fertility
  - HOF
  - culled
  - dead
  - hatch budget loss distribution
  - BMK deviation status
- Setter Optimizing:
  - EST average
  - EST CV
  - turning angle
  - CO2 context where data exists
- Hatcher Optimizing:
  - CVT average
  - CVT CV
  - panting
  - meconium
  - transfer day
  - CO2 context where data exists

### Layer 4: Trend And Benchmark Analysis

- Time trend for all current trend-capable metrics in repository outputs.
- Benchmark deviation trend for hatch outcomes.
- Outcome trend by flock, farm, house, breed, and visit date.
- Stability trend:
  - shell temp
  - EST
  - CVT
  - chick weight variability
  - YFBM variability

### Layer 5: Machine Comparisons

- Setter-to-setter comparison on EST average, EST CV, and turning angle.
- Hatcher-to-hatcher comparison on CVT average, CVT CV, meconium, and transfer day.
- Outcome-linked machine ranking once setter or hatcher IDs are joined with Hatch Analysis outcomes.

### Layer 6: Relationship Intelligence

- Storage condition to chick quality linkage.
- Setter condition to hatch outcome linkage.
- Hatcher condition to chick quality linkage.
- Hatch budget loss pattern to PM pattern linkage.
- Multi-station attribution:
  - upstream issue
  - setter issue
  - hatcher issue
  - post-hatch environment issue

## Part 5: Underused Intelligence In The Current Code

### Data already captured but underutilized

- Egg Storage checklist observations are captured but not converted into analytical outputs.
- Egg quality percentage fields are captured but not summarized into a composite storage-quality burden.
- UV inspection detail is captured but not converted into a visit risk index.
- PM lesion and deformity detail is captured but only lightly summarized.
- Setter CO2 and Hatcher CO2 are captured but not strongly surfaced in machine analytics.
- Panting and meconium are captured but not formalized into risk scores.
- Setter and Hatcher IDs are already available to connect process stations with hatch outcomes.

### Metrics possible now but not currently surfaced well

- Actual versus BMK delta for chick weight.
- Actual versus BMK delta for egg weight if BMK fields are populated consistently.
- Composite storage risk score from:
  - shell temperature
  - storage grid CV
  - UV burden
  - egg defect burden
  - checklist failures
- Composite chick vitality score from:
  - Pasgar
  - chick CV
  - YFBM
  - chick CVT
- Composite incubation process score from:
  - setter EST average and CV
  - hatcher CVT average and CV
  - turning angle
  - transfer day
- PM burden score from lesion count, deformity count, gasping, and severity.

### Correlations derivable from current data

- Egg uniformity versus chick uniformity.
- Shell temperature variance versus hatchability.
- Storage defects versus culls and deformities.
- Setter EST variance versus HOF.
- Hatcher CVT variance versus Pasgar.
- Hatcher panting versus PM severity.
- Meconium status versus culled and Pasgar.
- CHA air and particulate stress versus chick vitality.
- Hatch budget death pattern versus PM lesion pattern.

### High-value insights possible without changing database structure

- Visit-level root-cause orientation:
  - mostly storage-driven
  - mostly setter-driven
  - mostly hatcher-driven
  - mostly post-hatch environment-driven
- Machine-attributed loss ranking using current setter and hatcher IDs plus hatch outcomes.
- Confidence scoring based on station coverage.
- Repeat deviation detection:
  - same setter repeatedly hot
  - same hatcher repeatedly variable
  - same farm repeatedly high chick CV
- BMK deviation prioritization:
  - which benchmark misses are most operationally important
  - which are biologically important
- Exception-based dashboard outputs instead of metric-only reporting.

### Current code limitations that matter for analytics planning

- `lib/services/diagnostics/diagnostic_engine.dart` does not yet compute live findings.
- Hatch Analysis repository and dashboard support breakout analytics more richly than the current form flow.
- Setter and Hatcher comparison models are richer than the current repository queries.
- Egg Storage repository trend currently appears to populate `uvAffectedPct` from `AVG(esEggSampleSize)`, which suggests that UV trend output should be validated before using it as a final KPI.
- The audit provider Pasgar alert compares a 0-10 style score against a 20.0 threshold constant, so the save-time Pasgar alert path should be treated as implementation behavior, not trusted analytical truth.

## Part 6: Dashboard Core End Results

The dashboard should not focus on showing everything captured.
It should focus on helping a hatchery specialist answer the decisions below.

### 1. Is this visit biologically healthy or not

Outputs:
- Visit health score.
- Confidence score.
- Biological status:
  - healthy
  - watch
  - critical
- Top drivers of that status.

### 2. Where is performance being lost

Outputs:
- Main loss station.
- Main loss metric.
- Main loss category in hatch budget.
- Whether the loss is:
  - fertility-related
  - embryo mortality-related
  - hatch window-related
  - chick quality-related
  - handling or environment-related

### 3. Is the issue upstream or downstream

Outputs:
- Upstream condition risk:
  - storage
  - setter
- Downstream condition risk:
  - hatcher
  - chick holding environment
- Attribution summary using current cross-station relationships.

### 4. Which machine or process is most responsible

Outputs:
- Worst setter.
- Best setter.
- Worst hatcher.
- Best hatcher.
- Machine linked to the biggest outcome deviation.
- Machine stability ranking.

### 5. Which deviations require intervention now

Outputs:
- Red benchmark misses.
- Red threshold breaches.
- Red biological findings.
- Critical unreconciled hatch records.
- Immediate action priority list by severity.

### 6. Are chicks leaving the hatchery in acceptable condition

Outputs:
- Chick vitality status.
- Chick weight quality status.
- Chick temperature status.
- YFBM status.
- PM burden status.
- Sellable chick quality risk.

### 7. Is performance improving or drifting

Outputs:
- Direction of change for each core KPI.
- Repeat offender metrics.
- Repeat offender machines.
- Persisting benchmark misses.
- Improvement versus prior visits.

### 8. What single conclusion should the hatchery specialist take from the visit

Outputs:
- Primary visit conclusion.
- Primary root-cause hypothesis.
- Primary operational recommendation category:
  - storage control
  - setter control
  - hatcher control
  - chick handling or environment
  - pathology review

## Recommended Dashboard Output Set

If the dashboard is built strictly on current captured data, the core output set should be:

- Visit health score.
- Visit confidence score.
- Station status summary.
- Top 3 critical findings.
- Hatchability.
- HOF.
- Culled%.
- Dead%.
- Pasgar.
- Chick uniformity.
- Chick CV.
- YFBM status.
- Setter control status.
- Hatcher control status.
- BMK deviation summary.
- Main loss category.
- Main root-cause orientation.
- Machine ranking summary.
- Trend direction summary.
- Immediate intervention priorities.

## Bottom Line

The current app already captures enough data to support a serious hatchery intelligence model without changing database structure.

The strongest dashboard outputs available now are:
- outcome intelligence from Hatch Analysis
- biological intelligence from Chick Quality
- process-control intelligence from Setter and Hatcher Optimizing
- leading-condition intelligence from Egg Storage
- visit-level synthesis through the session model

The most valuable dashboard job is not reporting measurements.

It is answering:
- how healthy was this visit
- where losses are being created
- which station is driving them
- which machine is contributing
- how far the visit is from benchmark
- what needs attention first
