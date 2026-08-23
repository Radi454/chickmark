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

## Plain-English summary rule (required after every task)

After finishing any task or change, end the response with a short
plain-English summary of what was done and why — written for a non-programmer.
No jargon, no file paths, no code terms; explain it the way you would to the
app's owner over the phone: what was broken or requested, what changed, and
what they should notice or do next. Technical detail can appear earlier in the
response, but the plain-English summary must always be present and last.
