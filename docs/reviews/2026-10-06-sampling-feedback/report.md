# Sampling feedback — 2026-10-06

Task: sampling-feedback-20261006. Human acceptance and final live verification
remain pending.

## User feedback and changes

- Comments 1–2: SA numbers identify the sample owning the readings. The card
  now shows a short selected serial when full reference codes are unavailable,
  removes the missing-code prompt and doubled scope prefixes, and hides a
  redundant singleton native selector. Sample identities remain unchanged.
- Comment 3: House pickers offer flock-owned registration and editing. Machine
  pickers retain registration/capacity editing, and numbered pickers expose
  capacity editing directly. Historical samples retain their identities.
- Comment 4: Before these changes, the live registered Setter 1 offered four
  trolleys after its popup settled. Adding Trolley 3 succeeded and created a
  selected Tray 1. The evidence is `01-trolley-added-before-filter.png`.
  Used choices are now excluded and exhausted pickers explain the capacity
  limit and offer capacity editing.
- Comment 5: Used identities are excluded only among siblings under the same
  parent. Editing retains the current identity. Setter/Hatcher comparison
  uniqueness uses the complete pair, allowing other pair combinations.
- Comment 6: Setter/Hatcher registration and menus use the fixed physical
  number/ID without a separate Name field. Existing stored names are preserved.

## Additional save regression

The old published build failed to leave the Setter screen with “Could not save
station. Try again.” Its canonical tree was valid, but a stale legacy adapter
contained a blank machine identity. The provider now exempts those adapter
rows only when the exact optimizer panel has a loaded canonical tree. The
canonical save path retains its validation; legacy panels without a managed
tree still reject invalid machine identities.

## Validation so far

- Machine editor regression: three tests failed against the old five-field
  form and passed after removing Name.
- Provider/save regression: the new real SQLite case failed against the old
  preflight; the provider and adapter suites then passed all 45 tests.
- The final combined machine editor, scope/House, provider/SQLite adapter,
  sampling model/repository, and localization run passed all 103 tests.
  Capacity shrink, same-parent filtering, cross-parent reuse, and missing
  nearer-machine handling are covered. An existing paired-picker test emits
  a Cancel hit-test warning, without a test failure.
- CodeRabbit reviewed the patch and reported one minor controller-lifetime
  issue against an earlier snapshot. The final house editor uses Form-owned
  implicit controllers, removing that disposal hazard. Independent review also
  caught and corrected fallback to an ancestor Setter when the nearer Hatcher
  could not be resolved.
- After the paired dropdowns gained selection/options-aware keys, two test
  finders needed updating and one selected menu option appeared twice (field
  and popup). The final focused scope/House rerun passed all 20 tests, including
  preventing an edit into an existing complete pair.
- `flutter analyze --no-pub` reports only the two existing
  `unawaited_return_in_try_block` warnings in the environment loader and photo
  service. The new closure-style diagnostic was corrected.
- `flutter build web --release --base-href=/chickmark/
  --dart-define-from-file=.env --no-pub` succeeded. Existing secure-storage Wasm
  dry-run and icon-font warnings remain.
- Deployment and post-deployment browser verification are pending at this
  checkpoint.

## Limits and handoff

The original live tab remains open because its station save failed; it must
not be reloaded before its in-memory draft is safely preserved. The QA
records are the named Sampling QA 2026-10-05 fixture under Dashboard Test
Customer. No unrelated records are authorized for cleanup. Cloud catalog
convergence, real photo uploads/deletions, and multi-device behavior have not
yet been established by these checks.

Changed product files: sampling scope controls, machine editor, audit provider,
and Arabic localization; corresponding widget/SQLite regressions, living spec,
changelog, and this review/evidence directory.
