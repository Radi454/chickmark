# Telegram Agent Cloud-First Toggle Design

Date: 2026-08-13

## Goal

Make the Agent Monitor pause/resume control reflect the Telegram agent's
actual backend state immediately, without requiring an app restart. Supabase
is authoritative for `agent_settings.telegram_enabled`; SQLite mirrors only a
cloud-confirmed value.

## Root Cause

`AgentMonitorProvider.setTelegramEnabled` currently saves the requested value
only through `HatcheryAgentRepository`, which writes a pending SQLite row. The
Telegram Edge Function reads `public.agent_settings` from Supabase for every
message. Because the agent-settings write does not request an immediate sync,
the monitor can display the requested local value while Telegram continues to
use the previous cloud value. Restarting or resuming the app triggers the
general sync and makes the backend catch up.

## Selected Approach

Add a focused Telegram settings control port backed by the existing
`SupabaseService.upsertRowsStrict` path. The control writes the complete
`AgentSettings` row to Supabase and treats the verified row returned by the
upsert as the confirmed value. The provider awaits that result before writing
SQLite or changing its visible state.

This targeted operation deliberately does not run the full application sync.
It reuses the existing Supabase initialization, authentication, camel-to-snake
payload mapping, strict affected-row verification, and admin RLS policies.
No schema migration or Edge Function change is required.

## Components

### Cloud control port

A small service in `lib/services/supabase/` owns the remote operation. Its
interface accepts an `AgentSettings` value and returns the cloud-confirmed
`AgentSettings` row. The production implementation uses the authenticated
Supabase client through `SupabaseService` and rejects missing, malformed, or
non-matching confirmation instead of guessing that the write succeeded.

The port is injectable into `AgentMonitorProvider`, allowing provider tests to
use a deterministic fake while the production service test exercises the real
payload conversion and verified response contract at the Supabase boundary.

### Provider state transition

`AgentMonitorProvider` keeps the previous confirmed `_settings` value while a
toggle request is active and exposes an `isUpdatingTelegram` flag. The screen
disables the action while this flag is true and may show its existing loading
indicator without changing the running/paused label.

The provider assigns each request a monotonically increasing operation token.
Only the currently active token may publish a completion. The disabled action
prevents normal rapid taps, while the token prevents stale or out-of-order
async completions from overwriting a newer result if the provider method is
called directly or future UI changes permit overlap.

### Local mirror

After Supabase returns the confirmed row, the provider persists that confirmed
row with `HatcheryAgentRepository.saveSettings` and then publishes it to the
UI. A cloud failure happens before the local write, so SQLite and visible state
remain unchanged. If cloud confirmation succeeds but the local mirror write
fails, the cloud-confirmed value remains authoritative and visible; the
provider reports a local-cache warning so a later pull can heal the mirror.

## Data Flow

Successful resume from a confirmed paused state:

1. Set `isUpdatingTelegram` and retain `telegramEnabled == false` in the UI.
2. Send the complete requested settings row to Supabase.
3. Verify and parse the returned cloud row.
4. Save the returned row to SQLite.
5. Publish the returned row and clear the in-progress state.

Failed resume:

1. Set `isUpdatingTelegram` and retain the paused state.
2. Attempt the Supabase update.
3. On failure, skip the SQLite write, retain the paused provider state, expose
   a useful error, and re-enable the action.

Pause follows the same transition in the opposite direction.

## Concurrency

The UI disables the toggle during an active request. The provider also ignores
a second request while one is active and guards completion with an operation
token. These protections ensure a rapid `Pause -> Resume -> Pause` sequence
cannot allow an older network response to overwrite the newest confirmed
state.

## Error Handling

- Supabase unavailable, authentication/RLS rejection, request failure, empty
  confirmation, or malformed confirmation: preserve cloud/local/UI state and
  show `Unable to update Telegram agent. Please try again.`
- Returned cloud value differs from the requested value: reject the transition
  as unconfirmed and preserve the previous state.
- Local SQLite failure after cloud confirmation: show the confirmed cloud state
  and a cache-specific warning; do not claim the cloud change failed.

## Testing

Focused regression coverage will prove:

- resume writes cloud first, then local, then publishes Running;
- pause follows the same ordering and publishes Paused;
- cloud failure during resume preserves Paused and never writes local;
- cloud failure during pause preserves Running and never writes local;
- repeated requests are suppressed and stale completions cannot publish;
- the provider uses the returned cloud value as its confirmed state;
- the screen disables the action while the request is active;
- the Supabase adapter sends the expected `agent_settings` payload and rejects
  missing or mismatched confirmation.

Validation includes the focused provider, screen, service, and repository
tests, the broader agent test area, `flutter analyze`, and final-diff review.

## Documentation

`docs/LIVING_SPEC.md` will state that Telegram running/paused state is
cloud-authoritative, the monitor transitions only after a confirmed Supabase
write, and SQLite mirrors the confirmed cloud value.

## Out of Scope

- Full application sync for this control.
- Database migrations or RLS changes.
- Telegram Edge Function changes or deployment.
- Unrelated Agent Monitor or synchronization refactors.
