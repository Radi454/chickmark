# ChickMark Agent Guide

This file is the lightweight repo-level guidance for coding agents working in
this repository.

## Primary Sources

- Current Flutter codebase is the primary source of truth.
- docs/LIVING_SPEC.md is the living documentation of implemented behavior.
- If docs and code conflict, inspect code and report mismatch.
- Do not use deleted/old specs for implementation decisions.

Old generated specs must not be used unless the user explicitly provides them
again for a future task. Agents must inspect the current code before planning or
modifying product behavior.

## Current Workflow

- Work on one user-scoped task at a time.
- Do not mark product tasks complete unless the human reviewer explicitly
  approves it.
- Prefer additive, migration-safe changes.
- Preserve existing working behavior unless the task explicitly changes it.
- Run the narrowest relevant validation for the task you are implementing.
- Update `docs/LIVING_SPEC.md` after every meaningful code change.
- End each task with a short handoff that lists:
  - task id
  - summary of changes
  - files changed
  - tests or commands run
  - risks or assumptions

## Practical Notes

- The repo may contain unrelated local changes; do not revert them unless the
  user explicitly asks.
- Use `http://127.0.0.1:57863` as the stable Flutter web preview origin. This
  preserves the browser's IndexedDB-backed local app data between runs. Restart
  current code on that same origin with `make restart-web` or
  `RESTART=1 make run-web`; do not switch ports unless the user asks for a
  clean browser-storage environment.
- Be especially careful in files tied to persistence, sync, and migrations,
  including:
  - `lib/data/database/database_helper.dart`
  - `lib/data/models/`
  - `lib/data/repositories/`
  - `lib/services/supabase/`
- Documentation should describe implemented behavior, not planned or deprecated
  spec behavior.
