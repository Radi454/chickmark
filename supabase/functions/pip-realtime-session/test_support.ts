// Hand-rolled in-memory stand-in for the service-role Supabase client, shaped
// like the narrow query surface pip-realtime-session actually uses.
//
// Unlike the app door's fake, this one enforces the unique indexes the Realtime
// tables rely on for correctness — the partial unique index that makes the
// one-session invariant true under a race, unique(session_id, generation), and
// the global unique on openai_call_id. Without them a "concurrent starts cannot
// both win" test would pass against a fake that simply cannot fail.

export interface FakeDatabase {
  tables: Record<string, Record<string, unknown>[]>
  /** Tables whose operations must report a database error. */
  failing: Set<string>
  /**
   * Tables whose INSERTs must fail with a NON-unique error, leaving reads
   * working. Lets a test prove that a real insert failure surfaces as an error
   * rather than being dressed up as a 409 conflict.
   */
  failingInserts: Set<string>
}

export function createFakeDatabase(
  tables: Record<string, Record<string, unknown>[]> = {},
): FakeDatabase {
  return {
    tables,
    failing: new Set<string>(),
    failingInserts: new Set<string>(),
  }
}

const NON_TERMINAL_SESSION_STATES = new Set([
  'provisioning',
  'active',
  'ending',
])

interface Order {
  column: string
  ascending: boolean
}

class FakeQuery {
  private readonly equals: [string, unknown][] = []
  private readonly atLeast: [string, string][] = []
  private readonly anyOf: [string, readonly unknown[]][] = []
  private readonly orders: Order[] = []

  constructor(
    private readonly db: FakeDatabase,
    private readonly table: string,
  ) {}

  select(_columns: string): FakeQuery {
    return this
  }

  eq(column: string, value: unknown): FakeQuery {
    this.equals.push([column, value])
    return this
  }

  gte(column: string, value: unknown): FakeQuery {
    this.atLeast.push([column, String(value)])
    return this
  }

  in(column: string, values: readonly unknown[]): FakeQuery {
    this.anyOf.push([column, values])
    return this
  }

  order(column: string, options: { ascending: boolean }): FakeQuery {
    this.orders.push({ column, ascending: options.ascending })
    return this
  }

  limit(count: number) {
    if (this.failed()) return Promise.resolve(databaseError())
    return Promise.resolve({ data: this.rows().slice(0, count), error: null })
  }

  maybeSingle() {
    if (this.failed()) return Promise.resolve(databaseError())
    return Promise.resolve({ data: this.rows()[0] ?? null, error: null })
  }

  insert(values: unknown) {
    if (this.failed()) return Promise.resolve(databaseError())
    if (this.db.failingInserts.has(this.table)) {
      // 08006 (connection failure) — anything that is NOT a unique violation.
      return Promise.resolve(databaseError('connection failure', '08006'))
    }
    const rows = Array.isArray(values)
      ? values as Record<string, unknown>[]
      : [values as Record<string, unknown>]
    const target = this.tableRows()
    for (const row of rows) {
      const violation = uniqueViolation(this.table, target, row, null)
      if (violation) {
        return Promise.resolve(databaseError(violation, UNIQUE_VIOLATION))
      }
    }
    for (const row of rows) target.push({ ...row })
    return Promise.resolve({ data: null, error: null })
  }

  update(values: unknown) {
    return {
      eq: (column: string, value: unknown) => {
        if (this.failed()) return Promise.resolve(databaseError())
        const patch = values as Record<string, unknown>
        const target = this.tableRows()
        for (const row of target) {
          if (row[column] !== value) continue
          const merged = { ...row, ...patch }
          const violation = uniqueViolation(this.table, target, merged, row)
          if (violation) {
            return Promise.resolve(databaseError(violation, UNIQUE_VIOLATION))
          }
          Object.assign(row, patch)
        }
        return Promise.resolve({ data: null, error: null })
      },
    }
  }

  // PostgrestFilterBuilder is thenable; list queries are awaited directly.
  then<T>(
    resolve: (value: { data: unknown; error: unknown }) => T,
    reject?: (reason: unknown) => T,
  ): Promise<T> {
    const value = this.failed()
      ? databaseError()
      : { data: this.rows(), error: null }
    return Promise.resolve(value).then(resolve, reject)
  }

  private failed(): boolean {
    return this.db.failing.has(this.table)
  }

  private tableRows(): Record<string, unknown>[] {
    this.db.tables[this.table] ??= []
    return this.db.tables[this.table]
  }

  private rows(): Record<string, unknown>[] {
    const matched = this.tableRows().filter((row) =>
      this.equals.every(([column, value]) => sameValue(row[column], value)) &&
      this.atLeast.every(([column, value]) =>
        String(row[column] ?? '') >= value
      ) &&
      this.anyOf.every(([column, values]) =>
        values.some((value) => sameValue(row[column], value))
      )
    )
    const sorted = matched.slice()
    if (this.orders.length > 0) {
      sorted.sort((left, right) => {
        for (const order of this.orders) {
          const a = String(left[order.column] ?? '')
          const b = String(right[order.column] ?? '')
          if (a === b) continue
          const direction = a < b ? -1 : 1
          return order.ascending ? direction : -direction
        }
        return 0
      })
    }
    return sorted.map((row) => ({ ...row }))
  }
}

function sameValue(left: unknown, right: unknown): boolean {
  if (left === right) return true
  if (left === null || left === undefined) return false
  if (right === null || right === undefined) return false
  return String(left) === String(right)
}

/**
 * Returns a message when `candidate` would break a unique index on `table`.
 * `previous` is the pre-update row, excluded from the comparison so a no-op
 * update does not collide with itself.
 */
function uniqueViolation(
  table: string,
  rows: readonly Record<string, unknown>[],
  candidate: Record<string, unknown>,
  previous: Record<string, unknown> | null,
): string | null {
  const others = rows.filter((row) => row !== previous)

  const id = candidate.id
  if (id !== undefined && id !== null) {
    if (others.some((row) => sameValue(row.id, id))) {
      return 'duplicate key value violates unique constraint (id)'
    }
  }

  if (table === 'agent_realtime_sessions') {
    // idx_agent_realtime_sessions_one_active
    const owner = candidate.owner_profile_id
    const state = String(candidate.state ?? '')
    if (owner && NON_TERMINAL_SESSION_STATES.has(state)) {
      const clash = others.some((row) =>
        sameValue(row.owner_profile_id, owner) &&
        NON_TERMINAL_SESSION_STATES.has(String(row.state ?? ''))
      )
      if (clash) {
        return 'duplicate key value violates unique constraint ' +
          '(idx_agent_realtime_sessions_one_active)'
      }
    }
  }

  if (table === 'agent_realtime_calls') {
    const sessionId = candidate.session_id
    const generation = candidate.generation
    if (sessionId !== undefined && generation !== undefined) {
      const clash = others.some((row) =>
        sameValue(row.session_id, sessionId) &&
        sameValue(row.generation, generation)
      )
      if (clash) {
        return 'duplicate key value violates unique constraint ' +
          '(session_id, generation)'
      }
    }
    const callId = candidate.openai_call_id
    if (callId !== undefined && callId !== null) {
      if (others.some((row) => sameValue(row.openai_call_id, callId))) {
        return 'duplicate key value violates unique constraint (openai_call_id)'
      }
    }
  }

  if (table === 'agent_realtime_usage_seconds') {
    const clash = others.some((row) =>
      sameValue(row.session_id, candidate.session_id) &&
      sameValue(row.usage_date, candidate.usage_date)
    )
    if (clash) return 'duplicate key value violates primary key'
  }

  return null
}

function databaseError(message = 'fake database failure', code?: string) {
  return { data: null, error: code ? { message, code } : { message } }
}

/** SQLSTATE the real Postgres raises on a unique-index collision. */
const UNIQUE_VIOLATION = '23505'

export interface FakeRpcHandlers {
  [fn: string]: (
    args?: Record<string, unknown>,
  ) => { data: unknown; error: { message: string; code?: string } | null }
}

export function createFakeAdminClient(
  db: FakeDatabase,
  rpc: FakeRpcHandlers = {},
) {
  return {
    from(table: string) {
      return new FakeQuery(db, table)
    },
    rpc(fn: string, args?: Record<string, unknown>) {
      const handler = rpc[fn]
      if (!handler) {
        return Promise.resolve(databaseError(`unknown function ${fn}`, '42883'))
      }
      return Promise.resolve(handler(args))
    },
  }
}

export function sequentialIds(prefix: string): () => string {
  let counter = 0
  return () => {
    counter += 1
    return `${prefix}-${counter}`
  }
}
