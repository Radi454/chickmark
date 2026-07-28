# Telegram Agent Audit Browsing Design

## Goal

Allow an authorized Telegram user to ask naturally for recent or latest audits,
see every available matching option as a numbered list, choose one, and receive
its database-backed summary. The agent must not guess customer, flock, or audit
identities and must never describe a tool-argument error as a database
permission problem.

## Selected Approach

Add two bounded read tools to the existing unified AI harness:

1. `list_customer_audits` lists recent audit options for one authorized
   customer and, when supplied, one flock.
2. `get_audit_summary` loads one selected audit after verifying that its
   customer remains inside the server-enforced scope.

This separates discovery from detail. A single "latest audit" tool would hide
other valid choices, while querying every station table would be slower,
incomplete, and unable to represent an audit session consistently.

## Conversation Flow

1. The AI resolves customer and flock names with `resolve_customer_flock`.
2. For requests such as "آخر أوديت", "الأوديتات المتاحة", or equivalent
   natural language, the AI calls `list_customer_audits`.
3. The tool returns all matching recent audits within a bounded limit, ordered
   by audit date, creation time, and ID descending. It includes audits in every
   status instead of silently filtering to completed audits.
4. The AI presents a numbered list. Every option includes the audit date,
   status, hatchery name when available, and completed or selected station
   names.
5. The user chooses by number or by an unambiguous description.
6. The AI calls `get_audit_summary` with the selected audit ID and answers from
   that result.

The AI asks exactly one focused clarification when the customer, flock, or audit
selection is ambiguous.

## Tool Contracts

### `list_customer_audits`

Inputs:

- `customerId`: required authorized customer ID.
- `flockId`: optional flock ID belonging to that customer.
- `limit`: optional integer from 1 through 20; default 10.

Output:

- `customerId`
- `flockId`
- `audits`: ordered audit option objects containing:
  - `id`
  - `date`
  - `status`
  - `customerName`
  - `flockName`
  - `hatcheryName`
  - `selectedStationKeys`
  - `stationsCompleted`
  - `createdAt`
  - `completedAt`
- `truncated`

### `get_audit_summary`

Inputs:

- `auditId`: required audit-session ID.

Output:

- The same identity and status context as the list item.
- `breed`
- `flockAgeWeeks`
- `findings`
- `scorecard`
- `notes`

Absent database values remain `null`. JSON text fields are decoded only when
they contain valid bounded JSON; invalid content is returned as unavailable
rather than guessed.

## Authorization and Safety

- Server scope is injected by the tool gateway and cannot be supplied or
  widened by the model.
- `list_customer_audits` rejects an unauthorized customer before querying.
- When `flockId` is present, the handler verifies that the flock belongs to the
  requested customer.
- `get_audit_summary` filters by the complete allowed-customer set so unknown
  and out-of-scope audit IDs return the same `scope_denied` result.
- Queries select an explicit column allowlist and return at most 20 audit rows.
- Tool evidence retains the normal sanitized arguments, results, duration, and
  scope metadata.
- A rejected tool argument is reported as an invalid selection that should be
  re-resolved, not as proof that database access is unavailable.

## Error Handling

- No audits: return `ok` with an empty `audits` list so the AI can state that no
  matching audits were found.
- Wrong customer/flock relationship: return `scope_denied`.
- Unknown or unauthorized audit: return `scope_denied`.
- Database failure: return the standard `tool_failed` result without exposing
  database messages.
- Invalid JSON detail: retain `null` for that detail and continue returning the
  verified audit context.

## Testing

- Tool definitions expose both bounded audit tools.
- A scoped list returns all statuses in deterministic newest-first order.
- A flock filter cannot cross customer boundaries.
- Detail lookup returns only an audit inside the allowed customer set.
- Unknown and out-of-scope audits are indistinguishable.
- The policy instructs the model to list options and let the user choose before
  loading details.
- The production regression covers the observed failure: a customer name cannot
  be passed as `customerId`, and a natural latest-audit request uses the audit
  catalog instead of the hatchery catalog.
- The complete Telegram agent Deno suite, type check, formatting check, and
  deployed-source verification must pass before requesting live validation.

## Deployment and Acceptance

Deploy a new `telegram-hatchery-agent` version with webhook JWT verification
unchanged. Acceptance requires a live Telegram conversation that resolves
customer `الغريب`, flock `السلام`, lists the available audits, accepts a
numbered selection, and returns the selected audit summary without claiming a
scope failure.
