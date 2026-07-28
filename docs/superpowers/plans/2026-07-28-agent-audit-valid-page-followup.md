# Agent Audit Valid-Page Follow-up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure malformed audit relation rows cannot consume the bounded database window and hide older valid audit choices, while describing the 10-default/20-maximum behavior accurately.

**Architecture:** Keep the existing model-driven Telegram runtime, authorization, immutable choice snapshots, and public response contract. Change the Supabase audit adapter to scan ordered customer-scoped rows in bounded pages until it has `limit + 1` valid audits, exhausts the source, or reaches a hard scan cap; relation validation continues to happen before any label is exposed. The handler uses adapter truncation metadata conservatively, and human/tool documentation stops claiming the bounded result contains “all” or “every” audits.

**Tech Stack:** Deno TypeScript, Supabase JS/PostgREST, `@std/assert`, existing Telegram agent tool gateway.

## Global Constraints

- Preserve the single model-driven Telegram runtime; do not add phrase routing, fixed replies, or a special audit conversation branch.
- Preserve server-injected customer and conversation scope; the model must not provide customer scope, conversation IDs, audit IDs for ordinal selection, or database identifiers reconstructed from text.
- `list_customer_audits` defaults to 10 public choices and accepts at most 20.
- Database scanning uses ordered pages of 50 raw rows and stops after at most 500 raw rows.
- Stop early once `limit + 1` valid rows have been collected or the source is exhausted.
- Return `truncated: true` when more than `limit` valid rows were found or when the 500-row safety cap is reached before source exhaustion; never claim a capped/unknown scan is complete.
- Continue discarding malformed or cross-customer embedded customer, flock, or hatchery relations before any labels reach the model.
- Preserve stable descending order by `date`, `created_at`, and `id`, with nulls last.
- Preserve unrelated staged, unstaged, and untracked Flutter/intake work.
- Update `docs/LIVING_SPEC.md` to describe implemented behavior.
- Deploy only from a clean archive of the reviewed commit using `--no-verify-jwt`.

---

### Task 1: Return a Complete Bounded Page of Valid Audit Choices

**Files:**
- Modify: `supabase/functions/telegram-hatchery-agent/agent_audit_tools.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/agent_audit_tools_test.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/agent_tools.ts`
- Modify: `docs/LIVING_SPEC.md`

**Interfaces:**
- Consumes: existing `AgentAuditReadRow`, `auditFromRemote`, `compareAuditRows`, customer/flock scope checks, and `list_customer_audits` public data shape.
- Produces: `AgentAuditListPage` with `rows: readonly AgentAuditReadRow[]` and `truncated: boolean`; `AgentAuditStore.listAudits(...)` returns this page without changing the public tool result shape.

- [ ] **Step 1: Add the failing adapter/handler regression test**

Extend the fake PostgREST query with a recorded `range(from, to)` operation that returns the inclusive ordered slice. Add a test named:

```ts
Deno.test(
  'audit list scans past malformed leading rows to fill the valid page',
  async () => {
    // Create exactly 50 newest rows whose embedded customer relation belongs
    // to customer-b, followed by two valid customer-a rows.
    // Call list_customer_audits with customer-a and limit 1.
    // Assert the one returned choice is the newer valid row and
    // truncated is true because a second valid row exists.
    // Assert the adapter issued ranges [0, 49] and [50, 99].
    // Assert no foreign relation label appears in the result.
  },
)
```

Expected public result:

```ts
{
  ok: true,
  code: 'ok',
  data: {
    customerId: 'customer-a',
    flockId: null,
    audits: [{
      id: 'aa-valid-new',
      date: '2026-07-28',
      status: 'completed',
      customerName: 'Customer a',
      flockName: 'Flock a',
      hatcheryName: 'Hatchery a',
      selectedStationKeys: ['egg'],
      stationsCompleted: ['egg'],
      createdAt: '2026-07-28T12:00:00Z',
      completedAt: '2026-07-28T13:00:00Z',
    }],
    truncated: true,
  },
}
```

- [ ] **Step 2: Run the regression test and verify RED**

Run:

```bash
cd supabase/functions/telegram-hatchery-agent
npx --yes deno test --allow-env --allow-net --allow-read=. \
  agent_audit_tools_test.ts \
  --filter 'scans past malformed leading rows'
```

Expected: FAIL because the current `.limit(input.limit + 1)` query returns only malformed leading rows, which are discarded after the database window has already been applied.

- [ ] **Step 3: Add a failing safety-cap test**

Add a test named:

```ts
Deno.test(
  'audit list reports truncation when invalid rows exhaust the scan cap',
  async () => {
    // Create 500 ordered customer-a audit rows with a foreign embedded
    // customer relation and no valid rows.
    // Request limit 10.
    // Assert audits is empty, truncated is true, exactly ten 50-row ranges
    // were requested, and no eleventh page was queried.
  },
)
```

- [ ] **Step 4: Run the cap test and verify RED**

Run:

```bash
npx --yes deno test --allow-env --allow-net --allow-read=. \
  agent_audit_tools_test.ts \
  --filter 'invalid rows exhaust the scan cap'
```

Expected: FAIL because the current adapter has no bounded multi-page scan or conservative truncation metadata.

- [ ] **Step 5: Implement the minimal bounded-page adapter**

In `agent_audit_tools.ts`:

```ts
export interface AgentAuditListPage {
  rows: readonly AgentAuditReadRow[]
  truncated: boolean
}

const AUDIT_SCAN_PAGE_SIZE = 50
const MAX_SCANNED_AUDIT_ROWS = 500
```

Change `AgentAuditStore.listAudits(...)` to return `Promise<AgentAuditListPage>`. For the Supabase implementation:

1. Build a fresh ordered, customer-scoped, optional-flock-scoped query for each page.
2. Request inclusive ranges `[0, 49]`, `[50, 99]`, and so on.
3. Decode each page with `auditFromRemote` and append only valid rows.
4. Stop when `limit + 1` valid rows exist, the raw page contains fewer than 50 rows, or 500 raw rows have been scanned.
5. Return at most `limit + 1` valid rows.
6. Set adapter `truncated` when more than `limit` valid rows exist or when the 500-row cap was reached without proving source exhaustion.

Update fixture stores to return `{ rows, truncated: false }`. In `listCustomerAudits`, apply the existing defensive scope filter and sort to `page.rows`, then set public truncation to:

```ts
truncated: page.truncated || rows.length > limit
```

Do not weaken any relation validation or authorization path.

- [ ] **Step 6: Verify GREEN and run the focused audit suite**

Run:

```bash
npx --yes deno test --allow-env --allow-net --allow-read=. \
  agent_audit_tools_test.ts agent_tools_test.ts index_test.ts \
  agent_acceptance_test.ts
```

Expected: all focused tests pass with zero failures.

- [ ] **Step 7: Correct bounded-list wording**

Change the `list_customer_audits` tool description from “List all recent audit options” to “List a bounded page of recent audit options”. In `docs/LIVING_SPEC.md`, replace the changelog claim that users receive “every matching recent audit” with an accurate statement: default 10, maximum 20, and `truncated` signals a larger or conservatively incomplete bounded result.

- [ ] **Step 8: Run complete verification**

Run:

```bash
cd supabase/functions/telegram-hatchery-agent
npx --yes deno test --allow-env --allow-net --allow-read=. .
npx --yes deno check index.ts
npx --yes deno fmt --check .
cd ../../..
git diff --check
```

Expected: zero test failures, successful type checking, formatting, and diff checks.

- [ ] **Step 9: Commit the scoped follow-up**

Stage only the four files listed by this task, verify the staged diff, and commit:

```bash
git commit -m "fix: complete bounded audit paging"
```

- [ ] **Step 10: Write the task report**

Record the root cause, RED outputs, GREEN outputs, changed files, commit hash, clean-archive verification, and any concerns in the SDD report file supplied by the controller. Do not deploy until the controller’s scoped review is clean.
