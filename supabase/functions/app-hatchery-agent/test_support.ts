// Hand-rolled in-memory stand-in for the service-role Supabase client, shaped
// like the narrow query surface the app agent door actually uses.

export interface FakeDatabase {
  tables: Record<string, Record<string, unknown>[]>
  /**
   * Tables whose next operation must report a database error. The allocator
   * function name works here too, to exercise a failed turn-slot allocation.
   */
  failing: Set<string>
  /** Every allocate_agent_turn_slot call, in order, for assertions. */
  turnSlotCalls: Record<string, unknown>[]
  /** Server-side allocator counters, keyed by conversation id. */
  turnCounters: Map<string, TurnCounters>
}

interface TurnCounters {
  nextSeq: number
  epoch: number
  nextInbound: number
  nextOutbound: number
}

export function createFakeDatabase(
  tables: Record<string, Record<string, unknown>[]> = {},
): FakeDatabase {
  return {
    tables,
    failing: new Set<string>(),
    turnSlotCalls: [],
    turnCounters: new Map<string, TurnCounters>(),
  }
}

interface Order {
  column: string
  ascending: boolean
}

class FakeQuery {
  private readonly equals: [string, unknown][] = []
  private readonly atLeast: [string, string][] = []
  private readonly likes: [string, RegExp][] = []
  private readonly ins: [string, unknown[]][] = []
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

  // Only the subset actually used by the app door: a single trailing '%'
  // (prefix match), which is all `handleConversations` needs.
  like(column: string, pattern: string): FakeQuery {
    const escaped = pattern
      .replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
      .replace(/%$/, '.*')
    this.likes.push([column, new RegExp(`^${escaped}$`)])
    return this
  }

  in(column: string, values: unknown[]): FakeQuery {
    this.ins.push([column, values])
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
    const rows = Array.isArray(values)
      ? values as Record<string, unknown>[]
      : [values as Record<string, unknown>]
    const target = this.tableRows()
    for (const row of rows) {
      if (violatesUnique(target, row)) {
        return Promise.resolve(databaseError('duplicate key'))
      }
    }
    for (const row of rows) target.push({ ...row })
    return Promise.resolve({ data: null, error: null })
  }

  update(values: unknown) {
    return {
      eq: (column: string, value: unknown) => {
        if (this.failed()) return Promise.resolve(databaseError())
        for (const row of this.tableRows()) {
          if (row[column] === value) {
            Object.assign(row, values as Record<string, unknown>)
          }
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
    if (!this.db.failing.has(this.table)) return false
    return true
  }

  private tableRows(): Record<string, unknown>[] {
    this.db.tables[this.table] ??= []
    return this.db.tables[this.table]
  }

  private rows(): Record<string, unknown>[] {
    const matched = this.tableRows().filter((row) =>
      this.equals.every(([column, value]) => row[column] === value) &&
      this.atLeast.every(([column, value]) =>
        String(row[column] ?? '') >= value
      ) &&
      this.likes.every(([column, pattern]) =>
        pattern.test(String(row[column] ?? ''))
      ) &&
      this.ins.every(([column, values]) => values.includes(row[column]))
    )
    const sorted = matched.slice()
    if (this.orders.length > 0) {
      sorted.sort((left, right) => {
        for (const order of this.orders) {
          const a = left[order.column]
          const b = right[order.column]
          // conversation_seq and turn_index are integers; string compare would
          // put 10 before 9.
          const direction = typeof a === 'number' && typeof b === 'number'
            ? (a === b ? 0 : a < b ? -1 : 1)
            : compareText(a, b)
          if (direction === 0) continue
          return order.ascending ? direction : -direction
        }
        return 0
      })
    }
    return sorted.map((row) => ({ ...row }))
  }
}

function violatesUnique(
  rows: readonly Record<string, unknown>[],
  candidate: Record<string, unknown>,
): boolean {
  const updateId = candidate.telegram_update_id
  if (typeof updateId === 'string' && updateId.length > 0) {
    if (rows.some((row) => row.telegram_update_id === updateId)) return true
  }
  const id = candidate.id
  if (id !== undefined && id !== null) {
    if (rows.some((row) => row.id === id)) return true
  }
  return false
}

function compareText(left: unknown, right: unknown): number {
  const a = String(left ?? '')
  const b = String(right ?? '')
  return a === b ? 0 : a < b ? -1 : 1
}

function databaseError(message = 'fake database failure') {
  return { data: null, error: { message } }
}

export function createFakeAdminClient(db: FakeDatabase) {
  return {
    from(table: string) {
      return new FakeQuery(db, table)
    },
    // The allocator is reached through the public SECURITY DEFINER wrapper,
    // because PostgREST exposes only `public` on this project.
    rpc(fn: string, args: Record<string, unknown>) {
      if (fn !== 'allocate_agent_turn_slot') {
        throw new Error(`unexpected function ${fn}`)
      }
      db.turnSlotCalls.push({ ...args })
      if (db.failing.has(fn)) return Promise.resolve(databaseError())
      return Promise.resolve({
        data: [allocateTurnSlot(db, args)],
        error: null,
      })
    },
  }
}

// Mirrors chickmark_private.allocate_agent_turn_slot: authoritative counters
// held per conversation, seeded once from the rows that already exist, and
// turn_index counters that restart when the context epoch advances.
function allocateTurnSlot(
  db: FakeDatabase,
  args: Record<string, unknown>,
): Record<string, unknown> {
  const conversationId = String(args.p_conversation_id)
  const epoch = Number(args.p_context_epoch)
  const direction = String(args.p_direction)
  const override = args.p_turn_index_override
  const counters = turnCounters(db, conversationId, epoch)
  if (counters.epoch !== epoch) {
    counters.epoch = epoch
    counters.nextInbound = 1
    counters.nextOutbound = 1
  }
  let turnIndex: number
  if (typeof override === 'number') {
    turnIndex = override
    if (direction === 'inbound') {
      counters.nextInbound = Math.max(counters.nextInbound, turnIndex + 1)
    } else {
      counters.nextOutbound = Math.max(counters.nextOutbound, turnIndex + 1)
    }
  } else if (direction === 'inbound') {
    turnIndex = counters.nextInbound
    counters.nextInbound += 1
  } else {
    turnIndex = counters.nextOutbound
    counters.nextOutbound += 1
  }
  const conversationSeq = counters.nextSeq
  counters.nextSeq += 1
  return { conversation_seq: conversationSeq, turn_index: turnIndex }
}

function turnCounters(
  db: FakeDatabase,
  conversationId: string,
  epoch: number,
): TurnCounters {
  const existing = db.turnCounters.get(conversationId)
  if (existing) return existing
  const rows = (db.tables.agent_conversation_turns ?? []).filter(
    (row) => row.conversation_id === conversationId,
  )
  const seeded: TurnCounters = {
    nextSeq: highest(rows, 'conversation_seq') + 1,
    epoch,
    nextInbound: highest(
      rows.filter((row) =>
        row.direction === 'inbound' && Number(row.context_epoch) === epoch
      ),
      'turn_index',
    ) + 1,
    nextOutbound: highest(
      rows.filter((row) =>
        row.direction === 'outbound' && Number(row.context_epoch) === epoch
      ),
      'turn_index',
    ) + 1,
  }
  db.turnCounters.set(conversationId, seeded)
  return seeded
}

function highest(
  rows: readonly Record<string, unknown>[],
  column: string,
): number {
  return rows.reduce((latest, row) => {
    const value = Number(row[column])
    return Number.isFinite(value) ? Math.max(latest, value) : latest
  }, 0)
}

export function sequentialIds(prefix: string): () => string {
  let counter = 0
  return () => {
    counter += 1
    return `${prefix}-${counter}`
  }
}
