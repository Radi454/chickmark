# Customer List Delete and Cross-Device Cascade Design

## Goal

Allow an authorized editor to delete any visible customer directly from the
Customers screen. The deletion must remove the customer's related local data,
delete the corresponding Supabase data, and propagate to other devices through
the existing offline-first tombstone sync flow.

## Scope

- Add a visible delete action to each editable customer card on the Customers
  screen.
- Reuse the existing customer deletion cascade rather than introducing a second
  data-deletion path.
- Attempt Supabase sync immediately after local deletion.
- Preserve queued deletion tombstones when the device is offline or sync fails,
  so a later sync completes the cloud deletion.
- Keep the existing delete action on the Customer Detail screen working.
- Update the living specification and add focused regression coverage.

This change does not add delete permission to read-only customer users and does
not bypass the app's existing role checks or Supabase RLS policies.

## User Experience

Each `CustomerCard` receives an optional delete callback. When the current user
can edit audits, the card shows a red outlined delete icon beside the existing
Edit action. Read-only users see neither editable delete behavior nor a disabled
destructive control.

Tapping Delete opens a confirmation dialog that:

- names the selected customer;
- states that flocks, hatcheries, visits, station data, Govee captures, and
  linked photos will be permanently removed;
- explains that deletion is synchronized to the cloud and cannot be undone;
- provides Cancel and a visually destructive Delete action.

After confirmation, the dialog closes and the screen performs the deletion. The
customer disappears from the list after the local cascade succeeds. The app
then immediately attempts sync:

- online success reports that the customer was deleted and synchronized;
- offline or remote failure reports that the customer was deleted locally and
  cloud deletion is pending sync;
- local deletion failure leaves the customer visible and reports the error.

The UI must prevent an accidental double submission while the deletion is in
progress.

## Data Flow

`CustomersScreen` calls the existing `CustomersProvider.deleteCustomer` method.
That provider remains the single owner of the local cascade and deletion
tombstone creation. It deletes in child-before-parent order:

1. linked photo files and photo rows;
2. audit sessions and their station/panel rows;
3. Govee captures;
4. flocks;
5. hatcheries;
6. the customer row.

Repositories queue `sync_tombstones` before local SQLite rows disappear. This is
important because SQLite foreign-key cascades can otherwise remove child rows
before their remote identifiers have been recorded.

After the local cascade, `CustomersScreen` invokes the existing
`StartupSyncService` with push permission. The sync uploads pending tombstones
and deletes remote rows child-before-parent. Supabase retains the tombstones so
another device can pull them and apply the same deletes to its local database on
its next startup, background, or manual sync.

Offline operation is intentionally supported: local removal is not rolled back
when Supabase is unavailable. Pending tombstones are durable and later sync
finishes the remote and cross-device cascade.

## Component Boundaries

- `CustomerCard`: renders the optional delete affordance and forwards taps. It
  does not own confirmation, persistence, or sync.
- `CustomersScreen`: owns selected-customer confirmation, progress protection,
  immediate sync attempt, and user feedback.
- `CustomersProvider`: owns the customer-related local cascade and refreshes its
  in-memory customer state.
- Repositories and `StartupSyncService`: own tombstone persistence, remote
  deletion, and cross-device application.

The existing Customer Detail delete flow continues to call the same provider.
Shared wording may be extracted only if it keeps the implementation smaller and
does not broaden the feature.

## Error Handling

- Cancel performs no mutation.
- Provider/local-database errors show a failure message and do not start sync.
- Offline sync is a successful local deletion with a pending-cloud message.
- Unexpected sync errors do not restore deleted local rows; tombstones remain
  available for retry and the message clearly says cloud deletion is pending.
- Permission checks remain enforced in both the UI and provider.

## Testing

Use test-first development with the narrowest relevant Flutter tests:

- a `CustomerCard` widget test proves the delete action is visible only when a
  callback is supplied and that tapping it invokes the callback;
- a Customers screen/widget test proves the confirmation dialog names the
  customer and Cancel does not delete;
- a confirmation test proves Delete invokes the customer cascade once and
  protects against duplicate submission;
- the database integrity test verifies the local customer graph is removed and
  tombstones include customer, flocks, hatcheries, sessions, photos, panel rows,
  and Govee captures;
- sync service tests verify pending tombstones are uploaded and remote
  tombstones remove matching rows from another local database.

Run focused `flutter test` commands for the changed test files and focused
`dart analyze` for the touched Dart files. Broader unrelated analyzer warnings
are outside this task.

## Documentation

Update `docs/LIVING_SPEC.md` to describe the Customers-screen delete action,
confirmation, immediate best-effort sync, offline pending state, and
cross-device removal behavior.

## Assumptions and Risks

- Other devices must sync before their local copies disappear; the deleting
  device cannot directly mutate another device's offline SQLite database.
- Supabase RLS and foreign-key behavior must continue to allow the current
  authenticated editor to delete the same tables already handled by startup
  sync.
- Existing uncommitted localization and customer-delete work belongs to the
  user and must be preserved.
