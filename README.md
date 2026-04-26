

## Speckit Workflow

This repository already includes Speckit project scaffolding for spec-driven work.

- Core templates and workflow files live in `.specify/`
- Codex/Claude skills live in `.agents/skills/speckit-*` and `.claude/skills/speckit-*`
- Project constitution and workflow rules live in `.specify/memory/constitution.md`
- Generated feature artifacts are stored under `specs/<feature-id>/`

The normal feature flow is:

1. `/speckit-specify` to create or update the feature spec
2. `/speckit-plan` to produce the implementation plan
3. `/speckit-tasks` to generate dependency-ordered tasks
4. `/speckit-implement` to execute the plan

Supporting commands are also available for clarification, checklists, analysis, and
git automation:

- `/speckit-clarify`
- `/speckit-checklist`
- `/speckit-analyze`
- `/speckit-git-feature`
- `/speckit-git-commit`

If you use AI agents in this repo, start new product work through the Speckit flow
instead of jumping straight into code so the spec, plan, and tasks stay in sync.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
