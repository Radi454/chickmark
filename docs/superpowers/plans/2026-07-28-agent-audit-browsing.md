# Telegram Agent Audit Browsing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the unified Telegram AI list every recent audit available for an authorized customer/flock, let the user choose one, and return its verified summary.

**Architecture:** Extend the typed agent protocol with two bounded read tools and implement their database access in a focused `agent_audit_tools.ts` module. The server injects customer scope, the audit store selects an explicit allowlist from `audit_sessions` with customer/flock/hatchery relations, and the model policy requires numbered discovery before detail retrieval.

**Tech Stack:** Deno TypeScript, Supabase Edge Functions, `@supabase/supabase-js`, PostgREST embedded relations, Deno test, existing ChickMark agent tool gateway.

## Global Constraints

- Work only inside `AgentScope.allowedCustomerIds`; unknown and unauthorized records must share the same `scope_denied` result.
- Return audits in every status and let the user choose; do not silently pick only the newest or completed audit.
- Return at most 20 audit options, defaulting to 10.
- Keep Telegram replies model-authored plain text; add no phrase router or fixed conversational reply.
- Ask exactly one focused clarification when customer, flock, or audit selection is ambiguous.
- Preserve null database values and never guess missing data.
- Update `docs/LIVING_SPEC.md` after the behavior is implemented.
- Keep production webhook JWT verification disabled because Telegram secret authentication remains inside the function.
- Do not mark the product task complete before live human approval.

---

## File Structure

- Modify `supabase/functions/telegram-hatchery-agent/agent_protocol.ts` to add the two tool names.
- Modify `supabase/functions/telegram-hatchery-agent/agent_tools.ts` to publish bounded JSON contracts.
- Modify `supabase/functions/telegram-hatchery-agent/agent_prompt.ts` to require audit discovery and forbid names in ID arguments.
- Modify `supabase/functions/telegram-hatchery-agent/agent_tools_test.ts` and `agent_acceptance_test.ts` for contract and policy regressions.
- Create `supabase/functions/telegram-hatchery-agent/agent_audit_tools.ts` for audit rows, Supabase queries, scope checks, mapping, and handlers.
- Create `supabase/functions/telegram-hatchery-agent/agent_audit_tools_test.ts` for scoped list/detail behavior.
- Modify `supabase/functions/telegram-hatchery-agent/index.ts` to register the new handlers in the unified runtime.
- Modify `docs/LIVING_SPEC.md` to record implemented behavior and deployment evidence.

### Task 1: Typed audit contracts and model policy

**Files:**
- Modify: `supabase/functions/telegram-hatchery-agent/agent_protocol.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/agent_tools.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/agent_prompt.ts`
- Test: `supabase/functions/telegram-hatchery-agent/agent_tools_test.ts`
- Test: `supabase/functions/telegram-hatchery-agent/agent_acceptance_test.ts`

**Interfaces:**
- Produces: `AgentToolName` members `list_customer_audits` and `get_audit_summary`.
- Produces: `list_customer_audits({customerId, flockId?, limit?})`, where `limit` is 1–20.
- Produces: `get_audit_summary({auditId})`.

- [ ] **Step 1: Add failing tool-catalog assertions**

Add to the catalog test:

```ts
assertStringIncludes(json, 'list_customer_audits')
assertStringIncludes(json, 'get_audit_summary')
const auditCatalog = AGENT_TOOL_DEFINITIONS.find(
  (tool) => tool.name === 'list_customer_audits',
)
assertEquals(auditCatalog?.parameters.properties.limit.maximum, 20)
```

Add a gateway regression that calls:

```ts
{
  id: 'call-audit-name',
  name: 'list_customer_audits',
  arguments: { customerId: 'الغريب' },
}
```

under the existing `customer-a` scope and expects:

```ts
{ ok: false, code: 'scope_denied', data: null }
```

- [ ] **Step 2: Add failing policy assertions**

Add these required policy fragments to `agent_acceptance_test.ts`:

```ts
'Never pass a customer, flock, hatchery, or audit display name into an ID argument'
'call list_customer_audits'
'present every returned audit as a numbered option'
'let the user choose before calling get_audit_summary'
'Never use list_customer_hatcheries to answer an audit-history request'
```

- [ ] **Step 3: Run the focused tests and verify RED**

Run:

```bash
cd supabase/functions/telegram-hatchery-agent
npx --yes deno test --allow-env --allow-net agent_tools_test.ts agent_acceptance_test.ts
```

Expected: FAIL because the audit tool names, definitions, limit, and policy text do not exist.

- [ ] **Step 4: Implement the minimal contracts and policy**

Add both names to `AgentToolName`. Add an `auditLimitRule`:

```ts
const auditLimitRule: ArgumentRule = {
  type: 'integer',
  minimum: 1,
  maximum: 20,
}
```

Add definitions:

```ts
definition(
  'list_customer_audits',
  'List all recent audit options for an allowed customer and optional flock so the user can choose one.',
  { customerId: idRule, flockId: idRule, limit: auditLimitRule },
  ['customerId'],
),
definition(
  'get_audit_summary',
  'Load the verified summary of one selected authorized audit.',
  { auditId: idRule },
  ['auditId'],
),
```

Add the asserted policy rules under Evidence and scope. Require a fresh
`resolve_customer_flock` call whenever the current turn has names but no
verified IDs in a current tool result.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run the command from Step 3.

Expected: both test files pass with no warnings.

- [ ] **Step 6: Commit the green contract**

```bash
git add -- \
  supabase/functions/telegram-hatchery-agent/agent_protocol.ts \
  supabase/functions/telegram-hatchery-agent/agent_tools.ts \
  supabase/functions/telegram-hatchery-agent/agent_prompt.ts \
  supabase/functions/telegram-hatchery-agent/agent_tools_test.ts \
  supabase/functions/telegram-hatchery-agent/agent_acceptance_test.ts
git commit --only -m "feat: add agent audit tool contracts" -- \
  supabase/functions/telegram-hatchery-agent/agent_protocol.ts \
  supabase/functions/telegram-hatchery-agent/agent_tools.ts \
  supabase/functions/telegram-hatchery-agent/agent_prompt.ts \
  supabase/functions/telegram-hatchery-agent/agent_tools_test.ts \
  supabase/functions/telegram-hatchery-agent/agent_acceptance_test.ts
```

### Task 2: Scoped audit list and detail handlers

**Files:**
- Create: `supabase/functions/telegram-hatchery-agent/agent_audit_tools.ts`
- Create: `supabase/functions/telegram-hatchery-agent/agent_audit_tools_test.ts`

**Interfaces:**
- Consumes: `AgentToolHandler`, `AgentToolExecutionInput`, and the two tool names from Task 1.
- Produces: `AgentAuditStore`, `AgentAuditClient`, `createSupabaseAgentAuditStore(client)`, and `createAgentAuditToolHandlers(store)`.

- [ ] **Step 1: Write failing list tests**

Create a fixture store containing:

```ts
[
  {
    id: 'audit-new',
    customerId: 'customer-a',
    flockId: 'flock-a',
    hatcheryId: 'hatchery-a',
    date: '2026-07-28',
    status: 'in_progress',
    customerName: 'الغريب',
    flockName: 'السلام',
    hatcheryName: 'الغريب',
    selectedStationKeys: ['egg', 'chicks'],
    stationsCompleted: ['egg'],
    createdAt: '2026-07-28T12:00:00Z',
    completedAt: null,
    breed: 'Ross308',
    flockAgeWeeks: 38,
    findings: null,
    scorecard: null,
    notes: null,
  },
  {
    id: 'audit-completed',
    customerId: 'customer-a',
    flockId: 'flock-a',
    hatcheryId: 'hatchery-a',
    date: '2026-06-23',
    status: 'completed',
    customerName: 'الغريب',
    flockName: 'السلام',
    hatcheryName: 'الغريب',
    selectedStationKeys: ['egg', 'chicks', 'hatch_analysis_egg_breakouts'],
    stationsCompleted: ['egg', 'chicks', 'hatch_analysis_egg_breakouts'],
    createdAt: '2026-06-23T13:04:26Z',
    completedAt: '2026-06-23T18:07:00Z',
    breed: 'Ross308',
    flockAgeWeeks: 33,
    findings: { total: 3 },
    scorecard: { score: 91 },
    notes: 'reviewed',
  },
]
```

Assert that `list_customer_audits` returns both statuses newest-first, maps
identity names, honors `limit: 1`, and reports `truncated: true`.

- [ ] **Step 2: Write failing authorization and detail tests**

Assert:

```ts
await call('list_customer_audits', {
  customerId: 'customer-a',
  flockId: 'flock-b',
})
```

returns `scope_denied`, and both unknown and customer-B audit detail calls
return the identical denial:

```ts
{ ok: false, code: 'scope_denied', data: null }
```

Assert `get_audit_summary({auditId: 'audit-completed'})` returns the verified
identity, status, decoded findings/scorecard, and notes.

- [ ] **Step 3: Run the new test and verify RED**

Run:

```bash
cd supabase/functions/telegram-hatchery-agent
npx --yes deno test --allow-env --allow-net agent_audit_tools_test.ts
```

Expected: FAIL because `agent_audit_tools.ts` and its exported interfaces do
not exist.

- [ ] **Step 4: Implement the audit store and handlers**

Define:

```ts
export interface AgentAuditReadRow {
  id: string
  customerId: string
  flockId: string | null
  hatcheryId: string | null
  date: string | null
  status: string | null
  customerName: string | null
  flockName: string | null
  hatcheryName: string | null
  selectedStationKeys: readonly string[] | null
  stationsCompleted: readonly string[] | null
  createdAt: string | null
  completedAt: string | null
  breed: string | null
  flockAgeWeeks: number | null
  findings: unknown
  scorecard: unknown
  notes: string | null
}

export interface AgentAuditStore {
  findFlockCustomerId(flockId: string): Promise<string | null>
  listAudits(input: {
    customerId: string
    flockId: string | null
    limit: number
  }): Promise<readonly AgentAuditReadRow[]>
  findAudit(
    auditId: string,
    allowedCustomerIds: readonly string[],
  ): Promise<AgentAuditReadRow | null>
}

interface AuditDatabaseQuery {
  select(columns: string): AuditDatabaseQuery
  eq(column: string, value: unknown): AuditDatabaseQuery
  in(column: string, values: readonly unknown[]): AuditDatabaseQuery
  order(
    column: string,
    options: { ascending: boolean },
  ): AuditDatabaseQuery
  limit(
    count: number,
  ): Promise<{
    data: Record<string, unknown>[] | null
    error: { message: string } | null
  }>
  maybeSingle(): Promise<{
    data: Record<string, unknown> | null
    error: { message: string } | null
  }>
}

export interface AgentAuditClient {
  from(table: string): AuditDatabaseQuery
}
```

Select only:

```text
id, customer_id, flock_id, hatchery_id, date, breed, flock_age_weeks,
status, selected_station_keys, stations_completed, findings_json,
scorecard_json, notes, created_at, completed_at,
customer:customers(name), flock:flocks(flock_id), hatchery:hatcheries(name)
```

For list queries, filter by `customer_id`, optionally filter by `flock_id`,
order by `date`, `created_at`, and `id` descending, and request `limit + 1`.
For detail queries, filter by allowed customer IDs and audit ID before
`maybeSingle()`.

Map valid JSON text into arrays or objects. Map malformed JSON to `null`.
Before listing with a flock, require
`findFlockCustomerId(flockId) === customerId`. Re-filter all returned rows by
the requested customer/flock before sorting and slicing.

- [ ] **Step 5: Run the audit tests and verify GREEN**

Run the command from Step 3.

Expected: all audit tool tests pass.

- [ ] **Step 6: Format and commit the green handlers**

```bash
npx --yes deno fmt agent_audit_tools.ts agent_audit_tools_test.ts
git add -- \
  supabase/functions/telegram-hatchery-agent/agent_audit_tools.ts \
  supabase/functions/telegram-hatchery-agent/agent_audit_tools_test.ts
git commit --only -m "feat: add scoped agent audit reads" -- \
  supabase/functions/telegram-hatchery-agent/agent_audit_tools.ts \
  supabase/functions/telegram-hatchery-agent/agent_audit_tools_test.ts
```

### Task 3: Runtime wiring, documentation, verification, and deployment

**Files:**
- Modify: `supabase/functions/telegram-hatchery-agent/index.ts`
- Modify: `docs/LIVING_SPEC.md`

**Interfaces:**
- Consumes: `AgentAuditClient`, `createSupabaseAgentAuditStore`, and `createAgentAuditToolHandlers` from Task 2.
- Produces: live unified runtime registration of both audit tools.

- [ ] **Step 1: Add a failing source-wiring assertion**

In `index_test.ts`, add:

```ts
const indexSource = await Deno.readTextFile(
  new URL('./index.ts', import.meta.url),
)
assertStringIncludes(indexSource, 'createSupabaseAgentAuditStore')
assertStringIncludes(indexSource, 'createAgentAuditToolHandlers')
```

The existing unified-runtime tests continue proving every authorized text
reaches one model loop.

- [ ] **Step 2: Run the wiring test and verify RED**

Run:

```bash
cd supabase/functions/telegram-hatchery-agent
npx --yes deno test --allow-env --allow-net --allow-read=. index_test.ts
```

Expected: FAIL because the audit store and handlers are not registered.

- [ ] **Step 3: Register the handlers**

Import the Task 2 APIs and add:

```ts
const auditStore = createSupabaseAgentAuditStore(
  adminClient as unknown as AgentAuditClient,
)
```

Then spread `createAgentAuditToolHandlers(auditStore)` into the existing
unified `handlers` object. Do not add a webhook branch or phrase classifier.

- [ ] **Step 4: Run the wiring test and verify GREEN**

Run the command from Step 2.

Expected: the wiring test passes.

- [ ] **Step 5: Update the living specification**

Document that recent audit discovery returns every status as numbered choices,
detail retrieval is a second scoped tool call, names are forbidden in ID
arguments, and list/detail denial shapes do not reveal out-of-scope records.
Add a dated change-log entry.

- [ ] **Step 6: Run complete local verification**

Run:

```bash
cd supabase/functions/telegram-hatchery-agent
npx --yes deno test --allow-env --allow-net --allow-read=. .
npx --yes deno check index.ts
npx --yes deno fmt --check .
cd ../../..
git diff --check
```

Expected: all tests pass, type checking passes, formatting reports no changed
files, and `git diff --check` exits 0.

- [ ] **Step 7: Commit runtime wiring and documentation**

```bash
git add -- \
  supabase/functions/telegram-hatchery-agent/index.ts \
  supabase/functions/telegram-hatchery-agent/index_test.ts \
  docs/LIVING_SPEC.md
git commit --only -m "feat: expose audit browsing to Telegram agent" -- \
  supabase/functions/telegram-hatchery-agent/index.ts \
  supabase/functions/telegram-hatchery-agent/index_test.ts \
  docs/LIVING_SPEC.md
```

- [ ] **Step 8: Deploy the Edge Function**

Discover current CLI syntax first:

```bash
npx --yes supabase functions deploy --help
```

Then deploy to the linked ChickMark project:

```bash
npx --yes supabase functions deploy telegram-hatchery-agent \
  --project-ref kgucchapksiiqxmiutsz \
  --no-verify-jwt \
  --use-api
```

Expected: Supabase reports `Deployed Functions`.

- [ ] **Step 9: Verify production**

Run:

```bash
npx --yes supabase functions list \
  --project-ref kgucchapksiiqxmiutsz \
  --output json
```

Download the deployed source into a fresh temporary directory and verify it
contains `list_customer_audits`, `get_audit_summary`, and
`createAgentAuditToolHandlers`. Invoke the endpoint without the Telegram secret
and verify HTTP 401 `Unauthorized webhook`.

- [ ] **Step 10: Request live human acceptance**

Ask the user to send:

```text
العميل الغريب، القطيع السلام، وريني الأوديتات المتاحة
```

Expected: the bot lists all matching audits as numbered options. After the user
chooses one, it returns that audit summary. Keep the task in progress until the
user approves the live result.
