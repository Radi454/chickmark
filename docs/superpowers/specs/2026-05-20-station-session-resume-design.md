# Station Session Resume Design

## Purpose

Make visit sessions feel continuous and editable. Starting a visit for the same
customer, flock, hatchery, and visit date should resume the existing in-progress
session instead of creating a duplicate. Saved station data should be visible in
station setup, reopen into the station entry screens with all fields hydrated,
and remain editable. Dashboard remains the final-results surface.

## Decisions

- Same-session identity is `customerId + flockId + hatcheryId + visit date`.
- Same-context Start Visit resumes an existing in-progress session through Select
  Stations before entering any station.
- Saved stations use the existing selected-station row with a compact `Saved`
  badge.
- Saved stations cannot be removed from the visit order.
- Unsaved stations can still be added, removed, and reordered while the visit is
  in progress.
- Completed visits open station screens first for edit/review, with a separate
  action to view dashboard/final results.
- Re-saving a completed station keeps that station completed.
- Editing a completed visit keeps the visit completed as long as all selected
  stations are still completed.

## User Flow

### New Visit

1. User chooses audit context.
2. User reaches Select Stations.
3. User selects station order.
4. Tapping Start Visit creates a new `audit_sessions` row only when no matching
   in-progress session exists.
5. The app opens the selected station workflow.

### Resume Existing In-Progress Visit

1. User chooses the same customer, flock, hatchery, and visit date.
2. Select Stations loads the existing in-progress session.
3. The selected visit order shows saved stations with a `Saved` badge.
4. Saved stations stay in the order and cannot be removed.
5. The primary action reads as a continuation action, such as Continue Visit.
6. Opening a saved station hydrates fields from panel rows and allows edits.

### Completed Visit Review

1. User taps a completed visit from Home or Audits.
2. The app opens the station workflow in review/edit mode.
3. Station screens hydrate saved data and allow edits.
4. A separate dashboard/final-results action opens the results view.
5. Saving edits updates panel rows and keeps the visit complete when all selected
   stations remain complete.

## Select Stations Behavior

Select Stations supports both setup and resumed sessions.

- The selected list remains the canonical visit order.
- Rows for completed or saved stations show a `Saved` badge.
- Saved rows disable remove affordances.
- Unsaved selected rows keep the existing remove and drag affordances.
- Available stations can still be added to an in-progress session.
- Home, Recent Visits, and Audits display progress as
  `stationsCompleted.length / selectedStationKeys.length`, for example `3/5`.

## Data Model

No core schema change is required.

- `audit_sessions.selectedStationKeys` remains the selected visit order.
- `audit_sessions.stationsCompleted` remains station completion progress.
- Panel tables remain the source of truth for station field data.
- Existing panel-row identity continues to update saved rows by session and
  sample identity.

The implementation may add repository/provider helpers for loading a matching
in-progress session and updating selected station keys, but those helpers should
reuse the current `audit_sessions` columns.

## Routing

- Start Visit:
  - Look for matching in-progress session.
  - If found, load it into `AuditSessionProvider` and keep the user in the
    station-selection/continuation path.
  - If not found, create a new session normally.
- Home and Audits:
  - In-progress sessions route to the station-selection/continuation path so the
    user sees saved badges, completed progress, and remaining stations before
    entering data.
  - Completed sessions route directly to the station workflow for review/edit.
  - Dashboard/final results is a separate explicit action.

## Error Handling

- If resume lookup fails, show a concise error and keep the Start Visit action
  enabled.
- If saved station hydration fails, show the station screen with an empty draft
  only when no saved panel rows can be loaded, and do not mark data as lost.
- If station save fails, keep the user on the station screen and preserve dirty
  state for retry.
- Do not delete or hide saved panel rows when the station selection changes.

## Testing

Add or update focused tests for:

- Same-context Start Visit resumes an existing in-progress session instead of
  creating a duplicate.
- Select Stations shows `Saved` for saved stations and disables removing those
  rows.
- Unsaved stations can still be added to a resumed in-progress session.
- Home and Audits show progress such as `3/5`.
- Reopened station screens hydrate saved fields and can save edits back to the
  same session rows.
- Completed visits open the station workflow first, while final dashboard results
  remain available through a separate action.
- Re-saving a completed station keeps station and visit completion state.

## Out Of Scope

- Changing panel table schemas.
- Rebuilding dashboard result cards.
- Reworking station field layouts beyond the saved-state affordances.
- Deleting saved station data from Select Stations.
