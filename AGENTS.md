# ChickMark Agent Guide

This file is the lightweight repo-level guidance for coding agents working in
this repository.

## Primary Sources

When implementing the current upgrade work, treat these files as the source of
truth in this order:

1. `.specify/memory/constitution.md`
2. `specs/007-chickmark-upgrade/spec.md`
3. `specs/007-chickmark-upgrade/plan.md`
4. `specs/007-chickmark-upgrade/research.md`
5. `specs/007-chickmark-upgrade/data-model.md`
6. `specs/007-chickmark-upgrade/contracts/ui-session-contracts.md`
7. `specs/007-chickmark-upgrade/tasks.md`
8. `specs/007-chickmark-upgrade/implementation-handoff.md`

If older generated docs or historical notes disagree with the files above,
follow the files above.

## Current Workflow

- Work on exactly one task at a time from `specs/007-chickmark-upgrade/tasks.md`.
- Do not mark tasks complete unless the human reviewer explicitly approves it.
- Prefer additive, migration-safe changes.
- Preserve existing working behavior unless the task explicitly changes it.
- Run the narrowest relevant validation for the task you are implementing.
- End each task with a short handoff that lists:
  - task id
  - summary of changes
  - files changed
  - tests or commands run
  - risks or assumptions

## Approved Exceptions

The current upgrade spec includes two explicitly approved exceptions that agents
must preserve while implementing `007-chickmark-upgrade`:

1. Visit-level `audit_sessions` metadata is allowed as a companion workflow
   layer alongside station-level `audits`.
2. The dedicated Temperature tab may remain temporarily during the upgrade
   rollout and must not be removed unless a later approved task explicitly does
   so.

These are intentional, time-bounded exceptions for the upgrade rollout and
should not be treated as architecture violations.

## Practical Notes

- The repo may contain unrelated local changes; do not revert them unless the
  user explicitly asks.
- Be especially careful in files tied to persistence, sync, and migrations,
  including:
  - `lib/data/database/database_helper.dart`
  - `lib/data/models/`
  - `lib/data/repositories/`
  - `lib/services/supabase/`
- If there is a conflict between this file and the Constitution, follow the
  Constitution.
