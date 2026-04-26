# AI Agent Rules — Read Before Every Task

These rules apply to every task in every phase. Do not skip them.

---

## Before You Start Any Task

1. Read ALL files listed under "Files to modify" in the task
2. Read ALL files listed under "Files to read (context only)"
3. Do not start writing code until you have read everything listed
4. Confirm you understand what the task does before implementing

---

## While Implementing

### File scope — STRICT
- Only modify files explicitly listed in the task's "Files to modify"
- If you think another file needs changing, STOP and ask first
- Never modify `database_helper.dart` unless the task explicitly says to
- Never rename any model field — it will break `fromMap`/`toMap` and DB column mapping
- Never reorder `_onUpgrade` migration blocks — order is critical

### SQL rules
- Never use string interpolation in SQL: NO `"WHERE id = '$id'"` 
- Always use parameterized queries: `db.rawQuery('WHERE id = ?', [id])`
- Always use `whereArgs:` parameter for `db.query()` and `db.delete()`

### Dart rules
- Do not add packages to `pubspec.yaml` unless the task explicitly lists the package
- Do not refactor code outside the task scope
- Do not add comments explaining what code does — only add comments for non-obvious WHY
- Do not add TODO comments
- Maintain existing code style (no trailing summaries in functions, no multi-line docstrings)

### Provider rules
- Do not change Provider type signatures
- Do not restructure `MultiProvider` in `app.dart` unless instructed
- Always call `notifyListeners()` after state changes in ChangeNotifier

---

## Output Format

After implementing, show:
1. A list of every file you modified
2. The full diff for each file (not a summary — the actual diff)
3. Nothing else — no explanations, no "I also noticed..." additions

---

## High-Risk Operations — Require Extra Care

These operations need special attention. Double-check before writing:

| Operation | Risk | What to check |
|---|---|---|
| DB migration in `_onUpgrade` | Data loss | New block must be inside correct `if (oldVersion < X)` check |
| `ALTER TABLE ADD COLUMN` | Schema mismatch | Column must not already exist — use `IF NOT EXISTS` where supported, or check `PRAGMA table_info` first |
| `INSERT OR REPLACE` | Overwrites data | Confirm this is intentional for the table being modified |
| `Navigator.pop()` | Navigation state | Ensure mounted check before calling on async operations |
| `notifyListeners()` inside async gap | Disposed widget | Always check `if (!mounted)` or handle ChangeNotifier disposal |

---

## What "Done" Means for Each Task

A task is done when:
- [ ] `dart analyze` returns zero errors and zero new warnings
- [ ] `flutter build apk --debug` compiles successfully
- [ ] Manual test steps from the task pass
- [ ] No files outside the allowed list were modified
- [ ] No new packages were added unless specified

---

## Prompt Template (Copy This When Starting Each Task)

```
You are implementing one specific task in a Flutter application called ChickMark.
This is an offline-first hatchery audit app using sqflite (SQLite), Provider state management, and Supabase for cloud sync.

Current DB version: [X]
Branch: [branch name]

TASK: [paste full task from phase file]

Rules:
- Only modify files listed in "Files to modify"
- Use parameterized SQL only (no string interpolation)
- Do not add packages not listed in the task
- Show me the full diff when done, nothing else

Before implementing, confirm you have read and understood:
[list the files to modify and read]
```
