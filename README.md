

## Project Guidance

The current Flutter codebase is the primary source of truth for implemented
behavior. `docs/LIVING_SPEC.md` is the living documentation of that behavior.
If documentation and code conflict, inspect the code and report the mismatch.

Old generated specs are not active source material for implementation decisions
unless the user explicitly provides them again.

## Speckit Scaffolding

This repository still includes Speckit project scaffolding for optional future
spec-driven work.

- Core templates and workflow files live in `.specify/`
- Codex/Claude skills live in `.agents/skills/speckit-*` and `.claude/skills/speckit-*`
- Generated future feature artifacts may be stored under `specs/<feature-id>/`

When using Speckit for new work, start a fresh feature flow from the current
codebase and living spec instead of relying on deleted historical artifacts.

The normal optional feature flow is:

1. `/speckit-specify` to create or update a feature spec
2. `/speckit-plan` to produce an implementation plan
3. `/speckit-tasks` to generate dependency-ordered tasks
4. `/speckit-implement` to execute the plan

Supporting commands are also available for clarification, checklists, analysis, and
git automation:

- `/speckit-clarify`
- `/speckit-checklist`
- `/speckit-analyze`
- `/speckit-git-feature`
- `/speckit-git-commit`

If you use AI agents in this repo, have them inspect the current code before
planning or modifying product behavior.

## Getting Started

This project is a starting point for a Flutter application.

## Dev Shortcuts

- `make run` restarts Flutter web on `http://127.0.0.1:57863`.
- `make run-web` starts Flutter web on the same stable origin if it is not
  already running.
- `make restart-web` forces the stable Flutter web preview to restart with the
  current code.
- `make run-macos` starts the local macOS app with the same `.env` Supabase
  credentials used by the other local run targets. Direct debug/profile macOS
  builds also copy the local `.env` into the built app bundle.
- `make build-macos` builds the local macOS app with `.env` Supabase
  credentials compiled into the app.
- The web shortcut defaults to a profile web-server build with local Flutter web
  resources so the Codex side browser can run it without the Dart Debug Chrome
  extension. Set `WEB_BUILD_MODE=debug` when you explicitly need debug web mode.
- `scripts/run_flutter_web.command` can be double-clicked to restart the same
  Flutter web preview.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
