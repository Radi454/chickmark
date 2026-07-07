# Dashboard Station Collapse-State Design

## Problem

Dashboard station cards default to expanded and currently own their expansion
state inside each card widget. If a card widget is recreated while scrolling or
the dashboard section rebuilds, that local state returns to the expanded
default. A station the user deliberately collapsed can therefore reopen when
they scroll away and back.

## Scope

Preserve each station card's expanded or collapsed state for the current
dashboard visit. Do not persist this preference across navigation, app restarts,
users, or dashboard filters. Do not change the card layout, animation, completed
item chips, or sector content.

## Design

Let `DashboardScreenState` own a set of collapsed stable station identifiers.
Every station starts expanded when it is absent from that set. Pass the set and
a toggle callback into `ScopeInsightsSection`, making each station card's
expansion state controlled by the dashboard screen rather than initialized
inside the lazily scrolled card subtree.

Because the state is keyed by station rather than list position, rebuilding,
reordering, or recycling card widgets cannot transfer or reset state. The set
lives only as long as the current dashboard screen state, matching the
requested current-visit lifetime.

## Verification

Add a widget regression test that:

1. Renders the dashboard scope section in a constrained scroll viewport.
2. Collapses a station card and confirms its body is hidden.
3. Scrolls the station off-screen and then back into view.
4. Confirms the station body remains hidden and its chevron remains collapsed.

Run the focused dashboard scope test and analyze only the touched Dart files.
Update `docs/LIVING_SPEC.md` to document the implemented current-visit behavior.
