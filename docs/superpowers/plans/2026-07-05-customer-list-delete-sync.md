# Customer List Delete and Cross-Device Cascade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let authorized editors delete any customer from the Customers list, immediately attempt the existing Supabase tombstone sync, and propagate the cascade to other devices on their next sync.

**Architecture:** `CustomerCard` exposes an optional destructive callback while `CustomersScreen` owns confirmation, progress state, and immediate sync. `CustomersProvider.deleteCustomer` remains the only local cascade; `StartupSyncService` reports remaining tombstones so the screen never claims cloud success prematurely.

**Tech Stack:** Flutter, Provider, SQLite/sqflite, Supabase, mocktail, flutter_test

---

## File Map

- Modify `lib/features/customers/widgets/customer_card.dart`: optional delete action.
- Modify `lib/features/customers/screens/customers_screen.dart`: confirmation, duplicate-submit guard, deletion, sync, and feedback.
- Modify `lib/services/supabase/startup_sync_service.dart`: report pending deletion count.
- Modify `lib/l10n/app_localizations.dart`: translate new feedback.
- Modify `test/features/customers/customer_card_test.dart`: card action tests.
- Create `test/features/customers/customers_screen_delete_test.dart`: confirmation and deletion flow tests.
- Modify `test/services/supabase/startup_sync_service_test.dart`: pending-delete outcome tests.
- Verify `test/data/database/database_integrity_test.dart` and `test/data/repositories/sync_tombstone_repository_test.dart`.
- Modify `docs/LIVING_SPEC.md`: implemented behavior.

The worktree contains unrelated overlapping changes. Preserve them and do not stage or commit implementation files unless the user explicitly requests it.

### Task 1: Customer-card delete affordance

**Files:**
- Modify: `test/features/customers/customer_card_test.dart`
- Modify: `lib/features/customers/widgets/customer_card.dart`

- [ ] **Step 1: Write failing widget tests**

Hoist the existing `CustomerModel` fixture and add:

```dart
testWidgets('CustomerCard exposes delete only when callback exists', (tester) async {
  var deleteCalls = 0;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: CustomerCard(
        customer: customer,
        flockCount: 2,
        onDelete: () => deleteCalls++,
      ),
    ),
  ));

  expect(find.byTooltip('Delete customer'), findsOneWidget);
  await tester.tap(find.byTooltip('Delete customer'));
  expect(deleteCalls, 1);
});

testWidgets('CustomerCard hides delete without a callback', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: CustomerCard(customer: customer, flockCount: 2)),
  ));
  expect(find.byTooltip('Delete customer'), findsNothing);
});
```

- [ ] **Step 2: Verify RED**

Run `flutter test test/features/customers/customer_card_test.dart`.
Expected: compilation fails because `onDelete` does not exist.

- [ ] **Step 3: Add the minimal card API and button**

Add `final VoidCallback? onDelete`, accept it in the constructor, and render:

```dart
if (onDelete != null) ...[
  const SizedBox(width: AppSizes.spaceSm),
  SizedBox(
    width: 38,
    height: 38,
    child: IconButton.outlined(
      tooltip: context.tr('Delete customer'),
      onPressed: onDelete,
      color: AppColors.statusError,
      icon: const Icon(Icons.delete_outline, size: 18),
      style: IconButton.styleFrom(
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
  ),
],
```

- [ ] **Step 4: Verify GREEN**

Run the same focused test. Expected: all card tests pass.

### Task 2: Report incomplete tombstone sync

**Files:**
- Modify: `test/services/supabase/startup_sync_service_test.dart`
- Modify: `lib/services/supabase/startup_sync_service.dart`

- [ ] **Step 1: Write failing tests**

Configure one pending tombstone. For failed `deleteRows`, keep it pending and assert:

```dart
final outcome = await service().run();
expect(outcome.online, isTrue);
expect(outcome.pendingDeletes, 1);
verify(() => tombstones.markFailed(tombstone.id, any())).called(1);
```

For successful `deleteRows`, return no tombstones from the final query and assert:

```dart
expect(outcome.pendingDeletes, 0);
verify(() => tombstones.markSynced(tombstone.id)).called(1);
```

- [ ] **Step 2: Verify RED**

Run `flutter test test/services/supabase/startup_sync_service_test.dart`.
Expected: `SyncOutcome.pendingDeletes` is undefined.

- [ ] **Step 3: Implement pending-delete reporting**

Extend `SyncOutcome`:

```dart
final int pendingDeletes;

const SyncOutcome({
  required this.online,
  this.pushed = 0,
  this.pulled = 0,
  this.conflicts = 0,
  this.pendingDeletes = 0,
  this.incomingSessions = const [],
  this.otherIncomingCount = 0,
});
```

Before the online return from `run`, query remaining tombstones and include them:

```dart
final pendingDeletes =
    (await _syncTombstoneRepository.getPendingDeletes()).length;
return SyncOutcome(
  online: true,
  pushed: pushed,
  pulled: pulled,
  conflicts: _conflictsThisRun,
  pendingDeletes: pendingDeletes,
  incomingSessions: List.unmodifiable(_incomingSessionsThisRun),
  otherIncomingCount: _otherIncomingThisRun,
);
```

- [ ] **Step 4: Verify GREEN**

Run the focused service test. Expected: all tests pass.

### Task 3: Customers-screen confirmation and immediate sync

**Files:**
- Create: `test/features/customers/customers_screen_delete_test.dart`
- Modify: `lib/features/customers/screens/customers_screen.dart`
- Modify: `lib/l10n/app_localizations.dart`

- [ ] **Step 1: Write failing screen tests**

Use `useIsolatedAppDatabase`, seed `customer-1`, and pump `CustomersScreen` with a bypass-auth `AuthProvider`, a real `CustomersProvider`, and this test seam:

```dart
typedef CustomerDeletionSync =
    Future<SyncOutcome> Function({String? userId});

CustomersScreen(
  syncAfterDelete: ({userId}) async {
    syncCalls++;
    return const SyncOutcome(online: true, pendingDeletes: 0);
  },
)
```

Cancellation test:

```dart
await tester.tap(find.byTooltip('Delete customer'));
await tester.pumpAndSettle();
expect(find.text('Delete customer?'), findsOneWidget);
expect(find.textContaining('Blue Valley Farms'), findsOneWidget);
await tester.tap(find.text('Cancel'));
await tester.pumpAndSettle();
expect(await customerExists('customer-1'), isTrue);
expect(syncCalls, 0);
```

Confirmed online test:

```dart
await tester.tap(find.byTooltip('Delete customer'));
await tester.pumpAndSettle();
await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
await tester.pumpAndSettle();
expect(await customerExists('customer-1'), isFalse);
expect(syncCalls, 1);
expect(find.textContaining('deleted and synchronized'), findsOneWidget);
```

Add a pending test returning `SyncOutcome(online: false, pendingDeletes: 1)` and expect `cloud deletion is pending sync`.

- [ ] **Step 2: Verify RED**

Run `flutter test test/features/customers/customers_screen_delete_test.dart`.
Expected: `CustomersScreen.syncAfterDelete` and the list delete callback are absent.

- [ ] **Step 3: Implement the screen flow**

Add the optional production-safe test seam:

```dart
typedef CustomerDeletionSync =
    Future<SyncOutcome> Function({String? userId});

class CustomersScreen extends StatefulWidget {
  final CustomerDeletionSync? syncAfterDelete;
  const CustomersScreen({super.key, this.syncAfterDelete});
}
```

Track in-flight customers with `final Set<String> _deletingCustomerIds = {};` and wire:

```dart
onDelete: canEdit && !_deletingCustomerIds.contains(customer.id)
    ? () => _confirmDeleteCustomer(customer)
    : null,
```

Implement the approved confirmation dialog. After confirmation, add the ID to the set, call:

```dart
await context.read<CustomersProvider>().deleteCustomer(customer.id);
```

On local failure, show `Could not delete customer: $error` and do not sync. On success, attempt:

```dart
final userId = context.read<AuthProvider>().user?.id;
final outcome = await (widget.syncAfterDelete?.call(userId: userId) ??
    StartupSyncService().run(userId: userId));
final synchronized = outcome.online && outcome.pendingDeletes == 0;
```

Treat sync exceptions as pending and show exactly one message:

```dart
synchronized
    ? '${customer.name} deleted and synchronized'
    : '${customer.name} deleted locally; cloud deletion is pending sync'
```

Always remove the ID from `_deletingCustomerIds` when mounted. Add Arabic dynamic regex translations for both messages while preserving the entered customer name.

- [ ] **Step 4: Verify GREEN**

Run the focused screen test. Expected: confirmation, cancel, online, and pending cases pass.

### Task 4: Cascade verification and living documentation

**Files:**
- Verify: `test/data/database/database_integrity_test.dart`
- Verify: `test/data/repositories/sync_tombstone_repository_test.dart`
- Modify: `docs/LIVING_SPEC.md`

- [ ] **Step 1: Verify local and second-device deletion behavior**

Run:

```bash
flutter test test/data/database/database_integrity_test.dart test/data/repositories/sync_tombstone_repository_test.dart
```

Expected: the customer graph is empty locally, child/customer tombstones exist, and pulled remote tombstones delete matching local rows.

- [ ] **Step 2: Update implemented documentation**

Describe the visible Customers-list delete action, named confirmation, immediate best-effort sync, durable offline queue, and next-sync removal on other devices. Add a `2026-07-05` change-log entry.

- [ ] **Step 3: Run localization regression tests**

Run `flutter test test/core/l10n`. Expected: all localization and static-copy scans pass.

- [ ] **Step 4: Run the complete focused test set**

```bash
flutter test test/features/customers/customer_card_test.dart test/features/customers/customers_screen_delete_test.dart test/data/database/database_integrity_test.dart test/data/repositories/sync_tombstone_repository_test.dart test/services/supabase/startup_sync_service_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Run focused analysis**

```bash
dart analyze lib/features/customers/widgets/customer_card.dart lib/features/customers/screens/customers_screen.dart lib/providers/customers_provider.dart lib/services/supabase/startup_sync_service.dart lib/l10n/app_localizations.dart test/features/customers/customer_card_test.dart test/features/customers/customers_screen_delete_test.dart test/data/database/database_integrity_test.dart test/data/repositories/sync_tombstone_repository_test.dart test/services/supabase/startup_sync_service_test.dart
```

Expected: no issues in touched and directly related files.

- [ ] **Step 6: Review the diff**

Run `git diff --check`, then inspect only the touched paths. Do not revert, stage, or overwrite unrelated local work. End with the repo-required handoff and leave product completion pending human approval.
