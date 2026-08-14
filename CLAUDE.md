# ChickMark — Agent Instructions

See `AGENTS.md` for repo-level workflow guidance, primary sources, and the
files that need extra care around persistence, sync, and migrations.

## Doc maintenance rule (required on every change)

Any change to the code MUST, in the same commit:

1. Update `docs/LIVING_SPEC.md` so it still describes only current behaviour.
   If the change alters something the spec describes, edit that section. The
   code is the source of truth.
2. Add a dated entry to `docs/CHANGELOG.md` (newest at top, format
   `- YYYY-MM-DD:`) describing what changed.

Never rewrite old changelog entries when behaviour later changes — add a new
entry instead. The spec says what is true now; the changelog says what happened
over time. A meaningful change touches both files.
