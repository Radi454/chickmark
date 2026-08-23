// Schema-drift contract for `agent_realtime_response_usage`.
//
// WHAT THIS TEST CATCHES
//
// A hand-copied list of "the columns I think this table has" would rot in
// exactly the way a deployed schema can rot: someone adds a column to the
// store, forgets the migration (or vice versa), and the test keeps passing
// because it was never actually checking the SQL. So this test DERIVES the
// expected column set by parsing the committed migration FILES directly off
// disk, and fails loudly — with the actual offending column names — the
// moment `insertResponseUsage` writes something no COMMITTED migration
// defines. In short: it catches the store's code drifting ahead of the
// migration files on disk.
//
// WHAT THIS TEST DOES NOT CATCH
//
// On 2026-08-19, the migration adding `interaction_id` to
// `agent_realtime_response_usage` was committed and present on disk, but had
// not been APPLIED to the database before the sideband revision that started
// writing that column shipped. Every single `insertResponseUsage` call
// returned a PostgREST 400, and `#persistResponseUsage` (src/sideband.ts) —
// correctly, by design — swallows every failure so telemetry can never break
// a live call. The result: the table sat at zero rows in production with
// nothing louder than a `warn` log line, for as long as the drift lasted.
//
// This test reads migration files off disk, not the live database schema, so
// it would have PASSED throughout that exact incident — a committed-but-
// unapplied migration looks identical to an applied one from here. That gap
// is guarded elsewhere, not by this file: deploy ordering (the migration
// must land before the sideband revision that writes the column — see the
// DEPLOY ORDER note in the migration itself) plus the fail-loud
// `response_usage.persist_failed_first` / `response_usage.all_failed`
// logging that escalates a broken store instead of staying at `warn`.
//
// Also out of scope: `parseAlterTableAddColumns` below only recognizes
// `alter table ... add column`. An `alter table ... drop column` is handled
// too (see `parseAlterTableDropColumns`) so a dropped column is removed from
// the derived set rather than silently continuing to pass.
//
// Run from `services/pip-realtime-sideband/` (as `deno test -A` always is
// for this service — see README/CLAUDE.md): `Deno.readTextFile` below is
// CWD-relative, and `../../supabase/migrations/` from that directory is
// `<repo root>/supabase/migrations/`.

import { assert, assertEquals } from '@std/assert'
import { PostgrestStore } from '../src/store_postgrest.ts'
import type { ResponseUsageInsert } from '../src/store.ts'

const MIGRATIONS_DIR = '../../supabase/migrations/'
const TABLE = 'agent_realtime_response_usage'
const BASE_MIGRATION = '20260819090000_pip_realtime_response_usage.sql'

// ---------------------------------------------------------------------------
// Minimal, defensive SQL parsing. This is not a general-purpose SQL parser —
// it only needs to survive the shapes this repo's migrations actually use
// (see the two files it reads today), but it is written to fail LOUD (via the
// plausibility assertions in the test below) rather than silently returning
// an empty or partial set if the SQL shape ever drifts out from under it.
// ---------------------------------------------------------------------------

/**
 * Given `sql` and the index of an opening '(', returns the substring between
 * it and its matching ')', tracking nesting depth so inner parens (CHECK
 * constraints, REFERENCES, DEFAULT now()) don't terminate the scan early.
 */
function extractParenBlock(sql: string, openIndex: number): string {
  let depth = 0
  for (let i = openIndex; i < sql.length; i++) {
    if (sql[i] === '(') depth++
    else if (sql[i] === ')') {
      depth--
      if (depth === 0) return sql.slice(openIndex + 1, i)
    }
  }
  throw new Error('unbalanced parentheses while parsing a CREATE TABLE block')
}

/** Splits a CREATE TABLE body into its column/constraint clauses, respecting
 * nested parens so a clause like `check (total_tokens >= 0)` or
 * `references public.agent_realtime_sessions(id)` is never split mid-clause. */
function splitTopLevelClauses(block: string): string[] {
  const clauses: string[] = []
  let depth = 0
  let current = ''
  for (const ch of block) {
    if (ch === '(') depth++
    if (ch === ')') depth--
    if (ch === ',' && depth === 0) {
      clauses.push(current)
      current = ''
    } else {
      current += ch
    }
  }
  if (current.trim() !== '') clauses.push(current)
  return clauses
}

/** Table-level constraint keywords that start a clause with no column name. */
const CONSTRAINT_KEYWORDS = new Set([
  'primary',
  'unique',
  'check',
  'constraint',
  'foreign',
])

/** Parses the column names out of a `create table ... TABLE ( ... )` block. */
function parseCreateTableColumns(sql: string, table: string): string[] {
  const createRe = new RegExp(
    `create\\s+table\\s+if\\s+not\\s+exists\\s+public\\.${table}\\s*\\(`,
    'i',
  )
  const match = createRe.exec(sql)
  if (!match) return []
  const openIndex = match.index + match[0].length - 1
  const block = extractParenBlock(sql, openIndex)
  const columns: string[] = []
  for (const rawClause of splitTopLevelClauses(block)) {
    const clause = rawClause.trim()
    const identifierMatch = /^([a-z_][a-z0-9_]*)/i.exec(clause)
    if (!identifierMatch) continue
    const word = identifierMatch[1].toLowerCase()
    if (CONSTRAINT_KEYWORDS.has(word)) continue
    columns.push(word)
  }
  return columns
}

/** Parses every `alter table ... TABLE add column [if not exists] <name>`
 * naming the target table out of one migration file's full text. Tolerant of
 * whitespace/newlines and an optional `if not exists`. */
function parseAlterTableAddColumns(sql: string, table: string): string[] {
  const alterRe = new RegExp(
    `alter\\s+table\\s+(?:if\\s+exists\\s+)?public\\.${table}\\s+` +
      `add\\s+column\\s+(?:if\\s+not\\s+exists\\s+)?([a-z_][a-z0-9_]*)`,
    'gi',
  )
  return [...sql.matchAll(alterRe)].map((m) => m[1].toLowerCase())
}

/** Parses every `alter table ... TABLE drop column [if exists] <name>` naming
 * the target table out of one migration file's full text, mirroring
 * `parseAlterTableAddColumns`. A dropped column must fall OUT of the derived
 * "columns the migrations define" set — otherwise a column the code stopped
 * writing (or renamed) but that was later actually dropped from the table
 * would keep silently passing this contract. */
function parseAlterTableDropColumns(sql: string, table: string): string[] {
  const alterRe = new RegExp(
    `alter\\s+table\\s+(?:if\\s+exists\\s+)?public\\.${table}\\s+` +
      `drop\\s+column\\s+(?:if\\s+exists\\s+)?([a-z_][a-z0-9_]*)`,
    'gi',
  )
  return [...sql.matchAll(alterRe)].map((m) => m[1].toLowerCase())
}

async function loadMigrationColumns(): Promise<Set<string>> {
  const baseSql = await Deno.readTextFile(`${MIGRATIONS_DIR}${BASE_MIGRATION}`)
  const columns = new Set(parseCreateTableColumns(baseSql, TABLE))

  const entries: string[] = []
  for await (const entry of Deno.readDir(MIGRATIONS_DIR)) {
    if (entry.isFile && entry.name.endsWith('.sql')) entries.push(entry.name)
  }
  // Every migration OTHER than the base one is a candidate for a later `add
  // column` / `drop column`. Sorting IS load-bearing here (unlike a
  // pure-union of adds): a later migration's drop must be able to remove a
  // column an earlier migration added, and a later add must be able to
  // reintroduce a column an earlier migration dropped. Filenames in this repo
  // are timestamp-prefixed, so lexicographic order is chronological order.
  entries.sort()

  for (const name of entries) {
    if (name === BASE_MIGRATION) continue
    const sql = await Deno.readTextFile(`${MIGRATIONS_DIR}${name}`)
    for (const column of parseAlterTableAddColumns(sql, TABLE)) columns.add(column)
    for (const column of parseAlterTableDropColumns(sql, TABLE)) columns.delete(column)
  }

  return columns
}

// ---------------------------------------------------------------------------
// fakeFetch — same style as test/store_postgrest_test.ts, extended to also
// capture request headers so the idempotency `prefer` convention can be
// asserted below.
// ---------------------------------------------------------------------------

interface CapturedRequest {
  url: string
  method: string
  headers: Record<string, string>
  body: Record<string, unknown>
}

function fakeFetch(requests: CapturedRequest[]): typeof fetch {
  return (async (input, init) => {
    const url = typeof input === 'string' ? input : input.toString()
    const method = init?.method ?? 'GET'
    const headers: Record<string, string> = {}
    for (
      const [key, value] of Object.entries(init?.headers as Record<string, string> ?? {})
    ) {
      headers[key.toLowerCase()] = value
    }
    const body = typeof init?.body === 'string' ? JSON.parse(init.body) : {}
    requests.push({ url, method, headers, body })
    return new Response(JSON.stringify([]), { status: 200 })
  }) as typeof fetch
}

function buildStore(requests: CapturedRequest[]): PostgrestStore {
  return new PostgrestStore({
    supabaseUrl: 'https://example.test',
    serviceRoleKey: 'test-service-role-key',
    fetchImpl: fakeFetch(requests),
  })
}

function camelToSnake(key: string): string {
  return key.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`)
}

/** A fully-populated row: every field of `ResponseUsageInsert` gets a
 * distinct, non-default value so a field silently dropped from the POST body
 * builder (store_postgrest.ts) cannot hide behind a shared falsy default. */
const FULL_ROW: ResponseUsageInsert = {
  sessionId: 'sess_contract_1',
  responseId: 'resp_contract_1',
  interactionId: 'ia_contract_1',
  generation: 2,
  model: 'gpt-realtime-mini',
  status: 'completed',
  totalTokens: 500,
  inputTokens: 300,
  cachedInputTokens: 100,
  uncachedInputTokens: 200,
  inputTextTokens: 50,
  inputAudioTokens: 240,
  inputImageTokens: 10,
  cachedTextTokens: 40,
  cachedAudioTokens: 60,
  outputTokens: 200,
  outputTextTokens: 80,
  outputAudioTokens: 120,
  followedToolCall: true,
  toolNames: ['lookup_flock', 'get_user_scope'],
  ownerProfileId: 'profile_contract_1',
  tenantId: 'tenant_contract_1',
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

Deno.test(
  'parseAlterTableDropColumns finds a dropped column, tolerant of IF EXISTS and whitespace',
  () => {
    const sql = `
      alter table public.${TABLE}
        drop column if exists legacy_field;
      alter table public.${TABLE} drop column another_one;
    `
    assertEquals(
      parseAlterTableDropColumns(sql, TABLE),
      ['legacy_field', 'another_one'],
    )
  },
)

Deno.test(
  'a column added then later dropped is NOT in the derived set (drop column is honoured)',
  async () => {
    // A synthetic pair of migrations, applied in chronological (sorted
    // filename) order: one adds a column, a later one drops it again. Without
    // drop-column handling, the union-of-adds approach would keep it forever.
    const dir = await Deno.makeTempDir()
    const localBase = '20260101000000_base.sql'
    try {
      await Deno.writeTextFile(
        `${dir}/${localBase}`,
        `create table if not exists public.${TABLE} (\n` +
          `  session_id text not null,\n` +
          `  response_id text not null\n` +
          `);`,
      )
      await Deno.writeTextFile(
        `${dir}/20260102000000_add_scratch_column.sql`,
        `alter table public.${TABLE} add column scratch_field text;`,
      )
      await Deno.writeTextFile(
        `${dir}/20260103000000_drop_scratch_column.sql`,
        `alter table public.${TABLE} drop column if exists scratch_field;`,
      )

      const columns = new Set(
        parseCreateTableColumns(await Deno.readTextFile(`${dir}/${localBase}`), TABLE),
      )
      const entries: string[] = []
      for await (const entry of Deno.readDir(dir)) {
        if (entry.isFile && entry.name.endsWith('.sql')) entries.push(entry.name)
      }
      entries.sort()
      for (const name of entries) {
        if (name === localBase) continue
        const sql = await Deno.readTextFile(`${dir}/${name}`)
        for (const column of parseAlterTableAddColumns(sql, TABLE)) columns.add(column)
        for (const column of parseAlterTableDropColumns(sql, TABLE)) {
          columns.delete(column)
        }
      }

      assert(
        !columns.has('scratch_field'),
        `expected 'scratch_field' to be removed by the drop-column migration, ` +
          `got: [${[...columns].join(', ')}]`,
      )
      assert(columns.has('session_id'), 'unrelated base column must survive')
    } finally {
      await Deno.remove(dir, { recursive: true })
    }
  },
)

Deno.test(
  'the migration parser finds a plausible, non-vacuous column set (guards the parser itself)',
  async () => {
    const columns = await loadMigrationColumns()
    // A regex/paren-matching bug that silently returns nothing (or almost
    // nothing) must fail THIS assertion, not pass the drift check below by
    // vacuously having an empty "expected" set that everything trivially
    // satisfies. That is the specific failure mode this whole file exists to
    // prevent.
    assert(
      columns.size >= 20,
      `parsed only ${columns.size} columns from the migrations — parser is ` +
        `almost certainly broken (expected at least 20): [${[...columns].join(', ')}]`,
    )
    for (
      const anchor of ['session_id', 'response_id', 'total_tokens', 'interaction_id']
    ) {
      assert(
        columns.has(anchor),
        `expected known column "${anchor}" to be found by the migration parser; ` +
          `parsed set: [${[...columns].join(', ')}]`,
      )
    }
  },
)

Deno.test(
  'every column insertResponseUsage writes exists in the committed migrations',
  async () => {
    const columns = await loadMigrationColumns()
    const requests: CapturedRequest[] = []
    const store = buildStore(requests)

    await store.insertResponseUsage(FULL_ROW)

    assertEquals(requests.length, 1)
    const { body } = requests[0]
    const bodyKeys = Object.keys(body)
    const offending = bodyKeys.filter((key) => !columns.has(key))
    assert(
      offending.length === 0,
      `insertResponseUsage POSTed column(s) not defined by any migration: ` +
        `[${offending.join(', ')}]. Known migration columns: [${
          [...columns].join(', ')
        }]`,
    )
  },
)

Deno.test(
  'insertResponseUsage targets the right table and carries the ignore-duplicates idempotency prefer header',
  async () => {
    const requests: CapturedRequest[] = []
    const store = buildStore(requests)

    await store.insertResponseUsage(FULL_ROW)

    assertEquals(requests.length, 1)
    const { url, method, headers } = requests[0]
    assertEquals(method, 'POST')
    assert(
      url.startsWith(`https://example.test/rest/v1/${TABLE}`),
      `expected POST to /${TABLE}, got: ${url}`,
    )
    const prefer = headers['prefer'] ?? ''
    assert(
      prefer.includes('resolution=ignore-duplicates'),
      `expected the "resolution=ignore-duplicates" idempotency convention on the ` +
        `prefer header, got: "${prefer}"`,
    )
  },
)

Deno.test(
  'every field of the ResponseUsageInsert row reaches the POST body under its snake_case name',
  async () => {
    const requests: CapturedRequest[] = []
    const store = buildStore(requests)

    await store.insertResponseUsage(FULL_ROW)

    assertEquals(requests.length, 1)
    const { body } = requests[0]
    const dropped: string[] = []
    const mismatched: string[] = []
    for (const [key, value] of Object.entries(FULL_ROW)) {
      const snakeKey = camelToSnake(key)
      if (!(snakeKey in body)) {
        dropped.push(`${key} -> ${snakeKey}`)
        continue
      }
      if (JSON.stringify(body[snakeKey]) !== JSON.stringify(value)) {
        mismatched.push(
          `${key} -> ${snakeKey} (sent ${JSON.stringify(value)}, ` +
            `body has ${JSON.stringify(body[snakeKey])})`,
        )
      }
    }
    assert(
      dropped.length === 0,
      `ResponseUsageInsert field(s) missing from the POST body entirely: [${
        dropped.join(', ')
      }]`,
    )
    assert(
      mismatched.length === 0,
      `ResponseUsageInsert field(s) present but with a mismatched value: [${
        mismatched.join(', ')
      }]`,
    )
  },
)
