# Breakout Item Photos Design

## Goal

Give every Fresh, Candled, and Residue breakout metric its own photo control in
the same horizontal row as the count and benchmark result. Saved photos remain
visible at that metric, can be replaced or removed, and continue to appear in
the existing dashboard breakout photo grid.

## UI Design

Each breakout count row keeps its count field and BMK summary, then adds a
fixed-width horizontal photo viewport on the right. The viewport never wraps
below the row, including on narrow phones. It contains the existing thumbnail,
edit, remove, and add-more controls and scrolls horizontally when a metric has
more photos than fit in the viewport.

The sample-level Photos control is removed for new item-scoped capture. Legacy
sample-level photo entries remain preserved and visible through a read-only
legacy photo area only when such entries already exist, so this refinement does
not discard previously captured evidence.

## Persistence Design

No SQLite schema migration is required. The sample JSON `photos` map remains a
flat `Map<String, String>`, with each new key prefixed by its breakout metric
key. This makes photos round-trip with their owning item while preserving older
JSON.

Each `photos` table row uses:

- the active breakout panel name (`fresh_egg_breakout`,
  `candled_egg_breakout`, or `residue_breakout`);
- a `panelRowId` containing the session, breakout type, sample id, and metric
  key;
- a metric-specific `fieldKey`, such as `breakout_infertile_photo`,
  `breakout_earlyDead_photo`, or `breakout_midDead_photo`.

Replacing or removing a thumbnail also removes the superseded SQLite photo row
and queues its sync tombstone, preventing stale images from remaining in the
dashboard or returning from cloud sync.

## Dashboard Data Flow

The dashboard breakout loader aggregates both the new metric-specific field
keys and the legacy `breakout_photo` / `photo` keys. It de-duplicates paths and
continues rendering the combined result through the existing `PhotoGrid`; the
dashboard layout does not change.

## Tests

Focused tests cover:

- one same-row photo control per metric for all three breakout types;
- metric-specific widget identities, photo storage keys, and visible saved
  thumbnails;
- removal of replaced/deleted photo rows;
- dashboard aggregation of metric-specific plus legacy breakout photos;
- existing editable multi-photo behavior.

`docs/LIVING_SPEC.md` is updated only after the behavior passes focused tests.
