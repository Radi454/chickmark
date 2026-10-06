# Sampling feedback — 2026-10-06

Task: sampling-feedback-20261006. The feedback changes and focused live
verification are ready for human review; product acceptance remains pending.

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

## Final live result and handoff

Pages run 37437744321 deployed 2228c9b successfully. Authenticated sync on
that release changed the QA visit badge to Synced (screenshot 06). Read-only
Supabase verification found seven QA sampling states, 21 nodes, and the SA8
Setter row with its stable sample UUID and 100.4°F setpoint. The registered
Setter catalog, QA hatchery and visit are also present. This establishes the
QA save/reopen and cloud upload path. The independently built release passed;
its startup-sync suite passed all 47 tests.

Human acceptance, real photo transfer/deletion, and multi-device behavior are
not covered by this final check. Separate stale local records may still show
sync errors; upload isolation does not delete or repair those unrelated records.
The original tab and QA fixture remain for review. No unrelated data was deleted.

Files changed span sampling controls and editor/provider UI, Egg display,
Arabic localization, Supabase payload/startup sync, Pages build scripts, focused
tests, and living spec/changelog/evidence. Commits were pushed to remote main.
The primary checkout’s concurrent local sampling tab-layout edits remain intact.

## Resumed photo verification

On the deployed 2228c9b release, QA SA8 gallery selection accepted a generated
64×64 PNG through the normal file chooser, but the capture control remained
empty and a second click reopened Camera/Gallery. Remote QA photo metadata
count remained zero. The current PhotoService uses device documents-directory
and File APIs; its catch returns null on web. Web sync skips local-file upload,
and audit photo widgets render via Image.file. A browser byte-storage/upload
fix is being developed; this check has not passed yet.

The native photo service/repository/button baseline passed all 23 tests. No
QA records or unrelated records were deleted in this resumed check.

## Browser photo fix validation

Task: `sampling-feedback-20261006` (continuation). Compressed browser captures
now persist as JPEG data URIs in local photo records. Shared audit photo
widgets render those bytes and private cloud references. The upload pass
handles browser bytes while preserving native file behavior. Cloud panel
payloads exclude inline image data; reopen joins authoritative photo metadata
by panel and row, including the Setter Turning Angle alias and EST maps.

The combined regression run passed 178 tests; its sole compile failure was a
missing import in the newly added reconstruction test. After fixing it, all
three reconstruction tests passed. The final five-test reconstruction/capture
run passed after the production Turning Angle alias was added. Analysis has
one existing warning in `local_supabase_env_loader_io.dart:23` and no new
issues. A cheap independent review found no actionable issues.

Files changed: PhotoService, PhotoSyncService, SupabaseService, PhotoRepository,
photo_data_uri helper, station reconstruction/loading, shared PhotoImage and
audit photo widgets, their focused tests, living spec and changelog.
No schema migration or remote policy change is needed. Live gallery/upload/
reopen verification follows deployment. Real device camera and independent
multi-device UI checks remain outside this browser run.

The photo patch was rebased onto the concurrent nested-tab layout commit
`10fa83f`. Four old scope-control tests still expected free-text forms; they
now inject catalog fakes and choose registered machines and numeric trolley
positions while retaining duplicate/default-leaf/parent assertions. The
integrated scope/catalog/photo reconstruction run passed all 29 tests.

A predeployment save/sync retry showed the QA visit Failed. Read-only logs
from 11:20–11:30 UTC show PostgreSQL permission errors for sync_tombstones
and several other table reads, but no QA session identifier or named Chick
table error. Its exact cause remains unconfirmed; this is not evidence of a
clean cloud run. No grants or policies were changed.

## Live browser photo verification and compatibility repair

Pages run 37456520073 deployed 8f6f17d successfully. A synthetic blue PNG
selected through Gallery appeared as a thumbnail and in preview (07). Saving,
full browser reload, signing in and reopening Setter SA8 retained the image
(08). Reload currently asks for sign-in despite Remember me; this is recorded
as an unresolved authentication persistence issue rather than a photo loss.

The QA visit returned to Synced after fresh authentication. The object
`1791286389781000.jpg` reached private storage, but metadata initially remained
absent. Inspection confirmed the cloud photos table lacks observation_id and
the raw-observation table. Ordinary uploads now omit empty observation IDs;
metadata updates retain null-clearing on current schemas and retry without the
field only for the specific legacy missing-column response. Linked observations
keep their validation and fail when their required schema is absent. No cloud
schema or permission was changed. The 38-test photo/security run passed.

The delegated compatibility implementation was interrupted by model usage
limits; root finished its tests, corrected its response list type, and reviewed
the diff. The auth diagnosis could not finish for the same reason.

Root completed the auth diagnosis: SecureTokenStore and SessionTrustStore use
in-memory maps on web. Those maps disappear on browser reload, and
UserRepository.getRememberedUser requires a stored token. The repeat sign-in
is therefore explained by existing browser auth behavior, not by the photo
patch. No authentication storage behavior was changed.

## Latest live checkpoint

Pages run 37471584131 successfully deployed `2f9102a`. Fresh login retried
the existing photo: cloud metadata now has id `1791286389781000`, status
`synced`, field `turning_angle`, and a private
Supabase path. A join verifies the storage object exists and the associated
Setter row is SA8 UUID `be1c1974-d0e9-4294-880d-ff47505cc566` with
100.4°F. The cloud panel photo field is null, confirming inline image bytes
were removed from the panel payload while photo metadata carries the path.

Screenshot 09 records the final nested tab design. Opening Remove Trolley 4
shows 1 branch, 1 measurement, 1 photo, 0 notes (10). Permanent deletion has
not been performed: browser policy requires fresh confirmation at action time,
and a question is pending for only the named QA records. Live deletion/cleanup
and independent multi-device UI verification remain open. Human review is
pending; the product task is not marked complete.

Handoff: `sampling-feedback-20261006`. Changed photo capture/rendering, cloud
metadata compatibility, reconstruction, focused fixtures/tests, spec/changelog
and evidence. Latest validation: 38 photo/security tests pass, integrated UI
29 tests pass, release build passes, analyzer only the existing environment
loader warning. Changes were reviewed and pushed to main; no unrelated
records were removed and primary checkout local edits remain preserved.
