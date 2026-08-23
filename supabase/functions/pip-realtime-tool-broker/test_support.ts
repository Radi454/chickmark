// In-memory stand-in for the service-role Supabase client, shaped like the
// narrow query surface pip-realtime-tool-broker actually uses.
//
// Like the sibling fake in pip-realtime-session, this one ENFORCES the real
// unique indexes rather than being a permissive bag of rows. The broker's whole
// correctness argument rests on two of them:
//
//   * idx_agent_tool_call_claims_realtime_key
//       unique(realtime_session_id, realtime_generation, openai_tool_call_id)
//   * idx_agent_tool_events_realtime_call
//       unique(realtime_session_id, realtime_generation, tool_call_id)
//   * idx_agent_tool_events_realtime_sequence
//       unique(realtime_session_id, realtime_generation, tool_sequence)
//
// It also enforces the `agent_tool_events` immutability trigger: an UPDATE or
// DELETE against that table throws, exactly as Postgres would. A fake that
// silently allowed the update would let "evidence is written once" pass while
// the deployed function corrected rows.

export interface FakeDatabase {
  tables: Record<string, Record<string, unknown>[]>
  /** Tables whose operations must report a database error. */
  failing: Set<string>
  /** Tables whose INSERTs must fail with a NON-unique error. */
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

/** SQLSTATE Postgres raises on a unique-index collision. */
const UNIQUE_VIOLATION = '23505'

interface Order {
  column: string
  ascending: boolean
}

class FakeQuery {
  private readonly equals: [string, unknown][] = []
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
        if (this.table === 'agent_tool_events') {
          // The agent_tool_events_immutable trigger raises on UPDATE.
          throw new Error(
            'agent_tool_events rows are immutable (trigger raised on UPDATE)',
          )
        }
        if (this.failed()) return Promise.resolve(databaseError())
        const patch = values as Record<string, unknown>
        const target = this.tableRows()
        for (const row of target) {
          if (!sameValue(row[column], value)) continue
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
      this.equals.every(([column, value]) => sameValue(row[column], value))
    )
    const sorted = matched.slice()
    if (this.orders.length > 0) {
      sorted.sort((left, right) => {
        for (const order of this.orders) {
          const a = left[order.column]
          const b = right[order.column]
          const direction = compare(a, b)
          if (direction === 0) continue
          return order.ascending ? direction : -direction
        }
        return 0
      })
    }
    return sorted.map((row) => ({ ...row }))
  }
}

/** Numeric columns must sort numerically: tool_sequence 10 is above 9, not below. */
function compare(left: unknown, right: unknown): number {
  if (typeof left === 'number' && typeof right === 'number') {
    return left === right ? 0 : left < right ? -1 : 1
  }
  const a = String(left ?? '')
  const b = String(right ?? '')
  return a === b ? 0 : a < b ? -1 : 1
}

function sameValue(left: unknown, right: unknown): boolean {
  if (left === right) return true
  if (left === null || left === undefined) return false
  if (right === null || right === undefined) return false
  return String(left) === String(right)
}

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

  if (table === 'agent_tool_call_claims') {
    // idx_agent_tool_call_claims_realtime_key (partial: session id not null)
    const sessionId = candidate.realtime_session_id
    if (sessionId !== undefined && sessionId !== null) {
      const clash = others.some((row) =>
        sameValue(row.realtime_session_id, sessionId) &&
        sameValue(row.realtime_generation, candidate.realtime_generation) &&
        sameValue(row.openai_tool_call_id, candidate.openai_tool_call_id)
      )
      if (clash) {
        return 'duplicate key value violates unique constraint ' +
          '(idx_agent_tool_call_claims_realtime_key)'
      }
    }
  }

  if (table === 'agent_tool_events') {
    const sessionId = candidate.realtime_session_id
    if (sessionId !== undefined && sessionId !== null) {
      const callClash = others.some((row) =>
        sameValue(row.realtime_session_id, sessionId) &&
        sameValue(row.realtime_generation, candidate.realtime_generation) &&
        sameValue(row.tool_call_id, candidate.tool_call_id)
      )
      if (callClash) {
        return 'duplicate key value violates unique constraint ' +
          '(idx_agent_tool_events_realtime_call)'
      }
      const sequenceClash = others.some((row) =>
        sameValue(row.realtime_session_id, sessionId) &&
        sameValue(row.realtime_generation, candidate.realtime_generation) &&
        sameValue(row.tool_sequence, candidate.tool_sequence)
      )
      if (sequenceClash) {
        return 'duplicate key value violates unique constraint ' +
          '(idx_agent_tool_events_realtime_sequence)'
      }
    }
    // tool_sequence is NOT NULL.
    if (
      candidate.tool_sequence === null || candidate.tool_sequence === undefined
    ) {
      return 'null value in column "tool_sequence" violates not-null constraint'
    }
    // agent_tool_events_attribution_check
    if (
      (candidate.conversation_turn_id === null ||
        candidate.conversation_turn_id === undefined) &&
      (sessionId === null || sessionId === undefined)
    ) {
      return 'new row violates check constraint ' +
        '"agent_tool_events_attribution_check"'
    }
  }

  return null
}

function databaseError(message = 'fake database failure', code?: string) {
  return { data: null, error: code ? { message, code } : { message } }
}

export function createFakeAdminClient(db: FakeDatabase) {
  return {
    from(table: string) {
      return new FakeQuery(db, table)
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
