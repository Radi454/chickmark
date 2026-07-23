# Audit Scope Add and Remove Guards

**Date:** 2026-07-23
**Status:** Approved design

## Goal

Make scope creation and removal safer and clearer while users enter results in
audit stations:

- collect the scope-specific identity before creating a scope; and
- require confirmation before removing a scope when that removal would discard
  entered results.

The change applies to the currently mounted audit-station data-entry flows. It
does not change Dashboard filters, saved-visit deletion, station clearing, or
standalone Govee and Lab Analysis workflows.

## User Experience

### Adding a scope

Pressing a scope `+` action opens an `Add <scope>` dialog before provider or
screen state changes. The dialog presents the identity fields already used by
that scope:

| Audit station area | Scope | Identity requested before creation |
| --- | --- | --- |
| Egg Quality | House | House |
| Chick Weights | House | House |
| Chick Quality | Machine | Setter and Hatcher |
| Hatch Analysis / Egg Breakouts | House | House |
| Hatch Analysis / Egg Breakouts | Machine | Setter and Hatcher |
| Hatch Analysis / Egg Breakouts | Trolley | Trolley |
| Hatch Analysis / Egg Breakouts | Tray | Tray |
| Setter Optimizing | Machine | Setter |
| Setter Optimizing EST comparison | Incubation-age sample | Incubation age and hours |
| Hatcher Optimizing | Machine | Hatcher |

Dialog behavior:

- Identity values are trimmed and required. A multi-field Machine scope
  requires every identity field shown by the existing scope card.
- The primary action is disabled, or inline validation is shown, until the
  required identity is complete.
- A new identity cannot duplicate a sibling scope under the same active parent
  hierarchy. Comparison is performed on normalized identity values.
- `Cancel`, dismissing the dialog, or using the system back action leaves all
  audit state unchanged.
- `Add` creates or converts the scope through the existing provider/screen
  workflow, applies the entered identity, selects the resulting scope, and
  performs the same autosave scheduling as the current add action.
- The existing inline identity fields remain editable so users can correct a
  scope after creation.
- When the first scope converts an existing pooled draft, existing pooled
  results are preserved exactly as they are today; the dialog supplies the
  identity before the conversion is exposed to the user.

No temporary scope with generated `H`, `S`, `H`, `T`, `SH`, or numbered
placeholder identity is shown between pressing `+` and entering the identity.
Internal identifiers may still be generated where persistence requires them,
but they must not replace the user-provided identity.

### Removing a scope

Pressing a scope remove action first determines the exact records or
screen-local samples that the existing action would discard.

- If those records contain no entered result data, removal proceeds immediately.
- If any affected record contains entered result data, the app shows:
  - title: `Remove scope?`
  - message: `This scope contains entered results. Removing it will permanently discard those results.`
  - actions: `Cancel` and destructive `Remove`
- `Cancel`, dismissing the dialog, or using the system back action preserves the
  scope, active selection, results, and autosave state.
- `Remove` runs the existing removal behavior once.
- Removing a parent House, Machine, or Trolley scope checks all descendant
  samples that the action will delete or reset, not only the selected row.

An entered result is meaningful audit content that would be lost, including
typed numeric/text results, selected assessment values, populated result grids
or lists, and result evidence such as photos. The following do not trigger the
warning:

- House, Setter, Hatcher, Trolley, Tray, or incubation-age identity alone;
- generated identity placeholders and default labels;
- untouched model defaults used only to initialize a form; or
- station-level/shared values that remain available after the scope is removed.

## Architecture

Use small shared UI helpers and keep domain-specific knowledge with the owning
station:

1. A reusable add-scope dialog accepts a title and field descriptors and returns
   normalized identity values only after validation succeeds.
2. A reusable removal-confirmation helper accepts whether affected results
   exist and returns whether removal may continue.
3. Each audit screen maps its scope type to the correct dialog fields, duplicate
   check, result-data predicate, and existing add/remove callback.
4. Pure result-data predicates are preferred where practical so meaningful
   versus default-only data can be tested without rendering a dialog.

The dialogs must not own `AuditProvider` or mutate persistence. Provider and
screen-local mutations remain in the existing callbacks and run only after the
dialog returns a positive result. This keeps UI concerns out of the provider
and avoids a broad rewrite of the offline-first persistence and sync paths.

## Result Detection Rules

Each removal adapter evaluates the data grain actually affected:

- station-sample removals inspect the relevant `AuditModel` draft and associated
  station sample;
- Chick Weight House removal inspects only that house's weight results;
- Hatch Analysis hierarchy removal aggregates all affected drafts and breakout
  samples below the removed hierarchy;
- Tray and Trolley removal inspects the affected breakout sample entries,
  including entered counts and linked evidence;
- Setter incubation-age removal inspects the selected EST sample's readings and
  evidence.

Existing helpers that already distinguish entered results from identifiers or
defaults should be reused or extracted. Detection must not treat copied shared
Egg Storage metadata as scope-local loss.

## Error Handling and Accessibility

- Dialogs use the app's existing Material dialog conventions and localization
  path.
- Every field has a visible label and normal keyboard/focus behavior.
- The destructive `Remove` action is visually distinguishable and has semantic
  text.
- Duplicate or missing identity errors remain in the add dialog; no partial
  scope is created.
- If an add/remove callback is unavailable because the station is read-only,
  existing disabled controls remain disabled and no dialog opens.
- Dialog dismissal is a normal cancellation, not an error.

## Acceptance Criteria

1. Every mounted audit-station scope `+` action requests the applicable existing
   scope identity before creating or converting a scope.
2. Cancelling the add dialog causes no provider, screen-local, autosave, or
   persistence mutation.
3. Submitting valid identity data creates/selects the scope with that identity
   already visible.
4. Blank or duplicate sibling identities are rejected without creating a scope.
5. Removing a scope with no affected entered results remains a one-tap action.
6. Removing a scope with affected entered results shows the confirmation dialog.
7. Cancelling removal preserves the scope and all entered results.
8. Confirming removal performs the existing removal and deletes/resets exactly
   the same scope data as before.
9. Identity-only and untouched default-only scopes do not trigger removal
   confirmation.
10. Parent-scope removal warns when any descendant result would be lost.
11. Read-only audit behavior and current offline persistence, tombstone,
    autosave, and sync behavior remain unchanged.
12. `docs/LIVING_SPEC.md` is updated to describe the implemented behavior.

## Testing and Verification

Implementation follows test-driven development:

1. Add failing widget or pure-Dart tests for the shared dialogs and meaningful
   result predicates.
2. Add focused tests for each mounted add/remove control family:
   - add cancellation and successful named creation;
   - missing and duplicate identity validation;
   - empty removal without a dialog;
   - result-bearing removal with cancel and confirm;
   - parent removal with result-bearing descendants.
3. Run the narrow affected widget/provider tests during development.
4. Format changed Dart files, run `flutter analyze`, run the relevant audit test
   suite, and build Flutter web.
5. Restart the stable web preview at `http://127.0.0.1:57863` and exercise the
   successful, validation, cancellation, destructive, navigation, persistence,
   and regression paths through the graphical interface.
6. Review the final diff for unrelated changes and perform the Flutter feature
   quality-gate safety, data-integrity, security, and cleanliness checks.

## Risks and Constraints

- Several stations keep result data in different representations. A single
  generic non-null check would produce false warnings from initialized defaults,
  so detection must remain data-grain aware.
- Parent hierarchy removal can affect more than the active draft; descendant
  aggregation is required to avoid silent loss.
- The worktree already contains unrelated local changes. Implementation and
  commits must isolate only files required for this feature and must not revert
  user changes.
- No database schema, Supabase table, RLS policy, or sync protocol change is
  intended.
