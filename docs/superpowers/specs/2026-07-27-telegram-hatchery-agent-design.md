# Telegram Hatchery Agent Design

Date: 2026-07-27

## Goal

Build a Telegram-connected AI agent for ChickMark hatchery data entry. Staff can send text, photos, spreadsheets, PDFs, or other files through Telegram. The agent extracts hatchery rows, asks the submitting staff member for missing simple details, calculates hatchability, checks historical and BMK context, and creates a draft batch in ChickMark. The admin reviews, edits, approves, or rejects each row before anything becomes final cloud data.

The first version keeps the agent controlled from inside ChickMark. Trigger.dev or another workflow dashboard can be added later if workflow replay and external orchestration become necessary.

## Current Project Fit

ChickMark already has local and cloud persistence patterns, Supabase sync, BMK data, hatchery models, and app review surfaces. The implementation should follow existing Flutter, repository, model, migration, and Supabase service patterns.

Existing pieces to reuse where practical:

- BMK breed and age lookup, including hatchability benchmarks.
- Hatchery data models and repositories.
- Existing draft, audit, attachment, and sync patterns.
- Existing localization approach for English and Arabic.
- Existing dashboard and alert concepts for performance warnings.

## Actors

- Staff submitter: sends Telegram messages and answers follow-up questions.
- Admin: owns approval, correction, rejection, staff access, and agent control.
- Telegram bot: receives submissions and sends questions/status updates.
- AI agent: extracts fields, calculates hatchability, checks history and BMK, and creates draft rows.
- ChickMark app: displays the Agent Monitor and draft approval workflow.
- Backend: handles Telegram webhooks, AI calls, storage, draft creation, and audit logs.

## Selected Approach

Use a ChickMark backend endpoint connected to Telegram.

Flow:

1. Staff sends text, photo, spreadsheet, PDF, or file to the Telegram bot.
2. Telegram sends the update to the ChickMark backend.
3. Backend stores the original source and creates an agent submission.
4. Backend sends the source to the AI extraction pipeline.
5. AI extracts one or many hatchery rows.
6. If simple fields are missing or unclear, the bot asks the same staff member follow-up questions.
7. Staff answers are attached to the submission as draft evidence.
8. AI calculates hatchability for each row.
9. AI compares each row against historical approved data for the same category.
10. AI compares each row against BMK using stored flock age.
11. Backend creates one draft batch in ChickMark with all extracted rows.
12. Admin reviews rows in the app and approves, edits, or rejects each row.
13. Only approved rows update final hatchery records, flock metadata, and cloud data.

## Extracted Fields

Each extracted row should support:

- Customer name
- Flock name
- Station
- Breed
- Eggs placed
- Production date
- Placement date
- Egg weight
- Fertility percentage
- Transfer weight
- Setter number
- Hatcher number
- Hatch date
- Healthy chicks
- Second-grade or rejected chicks
- Condemned or dead chicks
- Total production

One Telegram submission may contain multiple rows. Those rows remain grouped in one draft batch, but each row can be reviewed independently.

## Hatchability Rule

Only one hatchability value is calculated in the first version:

```text
Hatchability = Total production / Eggs placed * 100
```

The agent should calculate this value from extracted numbers and show it in the draft row. If either total production or eggs placed is missing or invalid, hatchability remains blank and the row is marked as needing review.

## Historical Review Rule

The agent checks the previous approved comparable row for the same:

- Customer
- Flock
- Station
- Breed

If hatchability changes by 3 percentage points or more compared with the previous approved comparable row, the draft row gets a warning. This applies to both increases and decreases.

Examples:

- Previous 80%, current 75%: warning because the decline is 5 points.
- Previous 80%, current 83%: warning because the increase is 3 points.
- Previous 80%, current 82%: no historical warning because the increase is 2 points.

The warning does not mean the AI is unsure about extraction. Extraction confidence and biological or historical warnings must be shown separately.

## BMK Confirmation Rule

BMK is used as a second confirmatory point, especially when hatchability rises.

The agent uses:

- Breed
- Stored flock age
- BMK hatchability value for that breed and age

If the current hatchability rises sharply but is moving toward the expected BMK value for the flock age, the row should still show a warning note but with calmer wording.

Example:

```text
Hatchability increased from 80% to 85%. BMK is 88% at flock age 30 weeks, so the increase may be consistent with expected peak movement. Review before approval.
```

If flock age is missing, the bot asks the staff submitter for flock age. The answer is stored as draft flock metadata and is not final until admin approval.

## Matching and Master Data

The agent should match customer, flock, station, and breed names to existing ChickMark records.

If a match is uncertain:

- The bot may ask the staff submitter for clarification.
- The draft batch stores the proposed match and the staff answer.
- New or uncertain master data is not created as final data from Telegram alone.
- Admin confirmation is required before creating or updating customer, flock, station, breed, or flock age records.

Staff can help complete the draft, but staff cannot approve final records.

## Agent Monitor

ChickMark should add an in-app Agent Monitor page for admin control.

Submission statuses:

- Received
- Processing
- Waiting for staff answer
- Draft ready
- Needs admin review
- Partially approved
- Approved
- Rejected
- Failed

The monitor should show:

- Original Telegram text, photo, or file
- Staff submitter identity
- Extracted rows
- Missing questions asked by the bot
- Staff answers
- Calculated hatchability
- Historical comparison
- BMK comparison
- Extraction confidence
- Warning reasons
- Admin action history

Admin controls:

- Pause or resume the Telegram agent
- Allow or revoke Telegram staff submitters
- Reprocess a submission
- Edit extracted row values
- Approve, reject, or leave rows pending
- Manage proposed customer, flock, station, breed, and flock age changes

## Draft Review Behavior

One Telegram source creates one draft batch. A batch can contain many rows.

Admin can review rows together but approve, edit, or reject row by row. Good rows can be approved even if other rows in the same batch remain pending or rejected.

Approved rows write final hatchery records and cloud updates. Rejected rows remain in the audit trail but do not update operational records.

## Staff Telegram Behavior

Staff submitters interact only through Telegram.

Bot behavior:

- Acknowledge received submissions.
- Ask the same staff member about missing simple data.
- Ask for flock age when needed for BMK comparison.
- Confirm when a draft has been sent for admin review.
- Avoid exposing unrelated company or cloud records to staff.

Staff cannot approve, save final records, view all drafts, or manage master data.

## Security

The Telegram bot token must never be committed to the repository or embedded in app code. It must be stored as a backend secret.

The token previously shared in chat should be treated as compromised and replaced before implementation. The replacement token should not be pasted into chat. It should be stored directly in the deployment secret manager.

Telegram webhook requests must be verified using a secret path, header, or equivalent server-side verification supported by the chosen deployment setup.

Admin-only approval must be enforced on the backend. The Flutter UI should not be the only protection.

## Error Handling

- Unreadable file or image: mark submission Failed with a readable error.
- AI extraction failure: mark submission Failed or Needs admin review based on partial results.
- Missing required field: ask staff if it is simple, otherwise mark row Needs admin review.
- Missing flock age: ask staff and store the answer as draft flock metadata.
- No historical comparison exists: show no historical warning and note that this is the first comparable record.
- No BMK exists for breed and age: show no BMK warning and note that BMK was unavailable.
- One bad row in a batch must not block other rows from approval.

## Audit Trail

Every submission and row should retain:

- Original source reference
- Extracted values
- Extraction confidence per row and, where practical, per field
- AI warning reasons
- Historical comparison used
- BMK comparison used
- Bot questions
- Staff answers
- Admin edits
- Admin approval or rejection
- Final record identifiers created by approval

## Data Model Direction

The implementation can introduce additive, migration-safe tables or equivalent models for:

- Telegram staff links and permissions
- Agent settings
- Agent submissions
- Submission source assets
- Bot follow-up questions and answers
- Draft hatchery batches
- Draft hatchery rows
- Row warnings and confidence metadata
- Approval audit events

Names and exact schema should follow current ChickMark repository and migration conventions during implementation planning.

## Localization

The user-facing Flutter screen and Telegram bot messages should support English and Arabic.

AI extraction should support mixed English and Arabic hatchery tables and free-text messages.

## Testing Scope

Implementation should include focused tests for:

- Telegram submission ingestion without using a real bot token.
- English extraction sample.
- Arabic extraction sample.
- Multi-row extraction from one source.
- Hatchability calculation.
- 3 percentage point historical warning.
- BMK confirmation with stored flock age.
- Missing flock age follow-up.
- Staff answer attached to the draft.
- Admin-only approval enforcement.
- Partial approval within one batch.
- Failed unreadable source handling.

## Out of Scope for Version 1

- Trigger.dev workflow orchestration.
- Automatic final saving without admin approval.
- Staff access to ChickMark app records.
- WhatsApp integration.
- More hatchability formulas beyond total production divided by eggs placed.
- Automatic final creation of new master data from Telegram without admin confirmation.
