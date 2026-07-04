# Breakout Photo Path Recovery Design

## Problem

Breakout photo rows remain available to the dashboard, but their stored local
file paths can become invalid when the iOS application-container path changes.
The dashboard therefore renders one placeholder per photo row even when the
photo still exists in the current documents directory or has a valid cloud
copy.

Cloud pull cannot currently repair this state. `PhotoRepository.upsertPhoto()`
keeps any existing path that looks local when a remote photo row arrives,
without checking whether the local file exists. A stale local path therefore
replaces the usable remote reference before `PhotoSyncService.syncDownloaded()`
can download it.

## Design

Photo recovery belongs in the persistence and sync path, not in `PhotoGrid`.
The implementation will:

1. Reconcile stored local photo paths against the current application documents
   directory. If the stored absolute path is missing but a file with the same
   basename exists in the current documents directory, update the photo row to
   that current path.
2. Run reconciliation as part of downloaded-photo synchronization before cloud
   availability is required, allowing path recovery to work offline.
3. When a remote photo row is upserted, preserve an existing local path only if
   its file currently exists. If it is missing, retain the incoming remote
   reference so the existing download pass can restore the photo bytes.

The UI remains unchanged. All dashboard grids, fullscreen photo views, audit
thumbnails, and upload retries continue to consume the repaired local path from
the `photos` table.

## Error Handling

Path reconciliation is best effort. Missing candidates remain unchanged until
a remote row is pulled. Individual filesystem failures must not abort startup
sync or affect other photos. Remote download retains its current retry behavior:
failed downloads keep the remote reference for a later sync.

## Tests

Focused tests will verify:

- a stale absolute path is updated when the same filename exists in the current
  documents directory;
- reconciliation runs even when Supabase is unavailable;
- remote upsert preserves an existing local file;
- remote upsert accepts the remote reference when the existing local file is
  missing, allowing the download pass to recover it.

The narrow photo sync and repository tests will be run along with static
analysis of the changed files. `docs/LIVING_SPEC.md` will be updated after the
implemented behavior is verified.

## Scope

This change repairs all persisted evidence photos that use the shared `photos`
table, including breakout photos. It does not change photo capture, dashboard
layout, image quality, retention policy, or Supabase storage structure.
