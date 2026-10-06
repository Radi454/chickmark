# Sampling feedback — 2026-10-06

Task: sampling-feedback-20261006. Human acceptance and final live verification
remain pending.

## Deployed browser checks

On `a17eac4`, authenticated QA testing passed inline House registration and
code editing, adding its comparison branch, and retaining it after reopening.
The Add House picker excluded the used house and exposed registration directly.
The Trolley picker offered only 1 and 4 when 2 and 3 were in use; adding 4
created and selected Tray 1 / SA8. Machine capacity editing displayed only its
fixed ID and three capacity fields, with calculated counts of four trolleys
and 32 trays. Screenshots 02 and 03 record those controls.

Entering 100.4°F on SA8, leaving via Back, reopening the visit, and selecting
Trolley 4 restored 100.4°F. The old station-save failure did not recur. The
sampling card was visually checked at 1280px and the user's 776px width, with
readable chips and compact serial context. An additional display-only defect
was found: the Egg quality header rendered the flock UUID directly. Its
lookup now matches Home's flock display name without changing persisted IDs.
The Egg screen and Supabase payload/security suites passed all 26 tests in the
final independent combined run. Analysis retained only the two existing
warnings; the final release web build succeeded.

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

## Cloud follow-up

Pages deployment for `a17eac4` succeeded. Remote inspection found the QA flock
but no QA hatchery or catalog row. Server request logs showed a hatchery
payload containing `updated_at`, which is absent from the remote schema.
The cloud payload sanitizer now omits that legacy local field in camel and
snake case, without changing other tables or local dirty tracking. The new
regression first failed with the unsupported field present; the full Supabase
security/payload test file then passed all 12 tests, including the independent
root rerun. This establishes payload handling, not live cloud convergence.

## Limits and handoff

The original live tab remains open because its station save failed; it must
not be reloaded before its in-memory draft is safely preserved. The QA
records are the named Sampling QA 2026-10-05 fixture under Dashboard Test
Customer. No unrelated records are authorized for cleanup. Cloud catalog convergence was subsequently established on 4543546 below.
Real photo uploads/deletions and multi-device behavior have not been established
by these checks.

Changed product files: sampling scope controls, machine editor, audit provider,
and Arabic localization; corresponding widget/SQLite regressions, living spec,
changelog, and this review/evidence directory.

## Deployment cache follow-up

The browser still sent the legacy hatchery timestamp after deployment of its
payload fix. Server logs confirmed stale client code. Pages builds now
fingerprint bootstrap and compiled app filenames without clearing application
storage. The Python fixture and build wrapper regressions pass; a temporary
copy of actual release output also passes with its unregister-only service
worker unchanged. Live verification follows deployment.

## Fingerprinted release verification

Pages run 37436018031 deployed 4543546 successfully. The new release resolved
the Egg flock label, retained both QA House branches, and uploaded the QA
hatchery, Setter 1 catalog (19200 / 4800 / 150, four trolleys and 32 trays),
and audit session to Supabase. Repeating Trolley 4 creation and station Back
save/reopen restored SA8 and its 100.4°F reading; screenshot 04 records it.

Sampling states/nodes and their reading remain pending remotely. Detailed
Settings sync status reported 327 failed rows; production logs showed mixed
sampling table uploads rejected by RLS. The QA parent session and approved
admin are valid. Current sampling uploads batch unrelated sessions together,
allowing one invalid parent to reject the whole batch. A scoped upload
isolation regression and fix are in progress; RLS remains unchanged.

The primary checkout contains separate local sampling tab-layout changes and
documentation edits. They are preserved; fast-forwarding that checkout to
4543546 was stopped by Git to avoid overwriting them. The reviewed commits
are pushed to remote main from the isolated task worktree.

## Sampling upload isolation

Both sampling upload passes now group by session and panel. Regressions prove
a rejected group leaves unrelated groups and their measurements eligible, and
a failed reconciled upload retains only its own pending measurements. Existing
backoff, pull-only, serial reconciliation and deletion-order tests remain green.
Agent and independent root runs each passed all 47 startup-sync tests. Root
analysis reports only the two existing warnings listed above. Live cloud
verification follows the release deployment.
