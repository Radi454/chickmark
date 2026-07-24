# Home Incomplete Visits Design

## Goal

Make every unfinished audit visit visible and actionable on the Home screen so
users are reminded to complete it soon and can resume directly at its first
unfinished station.

## Scope

- Add an `Incomplete Visits` Home section immediately after Quick Actions.
- Show every customer-visible `audit_sessions` row whose status is
  `in_progress`, ordered by the existing most-recently-updated query.
- Hide the section when there are no incomplete visits.
- Resume a selected visit directly at its first unfinished station.
- Refresh Home after the resumed workflow closes so newly completed visits
  disappear from the section.
- Update the living specification and add focused widget coverage.

This change does not add a database column, notification scheduler, deadline,
or Supabase trigger. It uses the existing audit-session lifecycle fields and
customer access rules.

## User Experience

The new section appears between Quick Actions and Recent Audits when at least
one incomplete visit exists. Its title is `Incomplete Visits`.

Each visit card shows:

- customer name;
- flock identifier and breed when available;
- visit date;
- completed-station progress as `completed/selected`;
- the selected stations that are not yet in `stationsCompleted`;
- the reminder `Please complete this visit soon.`;
- a `Complete now` action.

All incomplete visits are rendered; the section does not truncate the list or
add a separate `View all` route. Cards follow existing Home spacing,
typography, accessibility, and warning-color patterns.

Tapping the card or `Complete now` resumes the session through
`AuditSessionProvider.resumeSession`. The provider's existing resume-index
logic selects the first station key that is absent from `stationsCompleted`,
and Home opens `AuditSessionScreen` directly instead of returning to station
selection.

When the visit route closes, Home reloads its data. A visit whose selected
stations are now all completed no longer appears.

## Data Flow and Component Boundaries

`HomeProvider.activeSessions` remains the source of truth. It already loads
`AuditSessionRepository.getInProgressSessions()` and filters those rows to the
signed-in customer's accessible customer id when required.

`HomeScreen`:

1. skips the section when `activeSessions` is empty;
2. resolves customer and flock display values through `CustomersProvider`;
3. derives missing station keys by subtracting `stationsCompleted` from
   `selectedStationKeys`;
4. renders one presentation-only card per session;
5. sends the selected session to the existing direct station-workflow helper;
6. reloads Home after the route returns.

The visit card receives display data and a callback. It does not query the
database or own navigation. No completion state is inferred from panel rows;
the lifecycle continues to use `selectedStationKeys`,
`stationsCompleted`, and `status`.

## Error and Edge Handling

- If session resume fails, preserve the existing Home error SnackBar and leave
  the card visible.
- Missing customer or flock display records fall back to stored ids, matching
  the Recent Audits behavior.
- A malformed legacy row with no selected station keys may still appear, but
  its progress remains safe and the existing resume flow handles the session.
- Read-only users can see customer-scoped incomplete visits but cannot gain new
  edit authority from the Home card; existing audit workflow authorization
  remains authoritative.
- The list is scrollable as part of the existing Home `ListView`, so showing all
  incomplete visits does not introduce a nested scroll view.

## Testing

Use test-first Flutter widget coverage to prove:

- the section is absent when there are no incomplete visits;
- every incomplete visit is rendered rather than truncating the list;
- a card shows its reminder, progress, and missing station labels;
- tapping `Complete now` resumes the session and opens
  `AuditSessionScreen` directly at the first unfinished station;
- returning from the workflow reloads Home so a completed visit disappears;
- customer-scoped Home data does not expose another customer's incomplete
  visit.

Run the focused Home widget tests and focused Dart analysis for changed files.

## Documentation

Update `docs/LIVING_SPEC.md` to describe the Home incomplete-visits section,
its all-session list, its reminder copy, direct resume behavior, and automatic
removal after completion.

## Assumptions and Risks

- `HomeProvider.activeSessions` remains ordered by the repository's
  `updatedAt DESC` query.
- A large number of incomplete visits lengthens the Home page because the user
  explicitly requested all sessions; pagination is outside this feature.
- The reminder is in-app copy only. Timed push/local notifications are outside
  scope.
