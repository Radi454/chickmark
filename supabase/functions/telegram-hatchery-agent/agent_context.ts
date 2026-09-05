// agent_context.ts — the shared conversation context loader and turn-slot
// allocator used by every door into the unified agent brain.
//
// Both doors (the Telegram webhook and the in-app chat function) used to carry
// their own copy of this: fetch the newest turns of the current context epoch,
// fetch the active intake session with a byte-identical twelve column select,
// then hand both to the runtime. The copies had already drifted — one door
// named its history limit, the other hardcoded 40 — so the logic lives here
// once, and the limit is one constant.
//
// Two things are deliberately NOT the same as the old inline code:
//
//   * History is ordered by `conversation_seq`, the never-resetting
//     chronological key added in 20260816120000_pip_realtime_v1_persistence.sql
//     (the migration is historical; the live-voice feature it was named for is
//     retired), not by `created_at`. Turns written inside the same millisecond
//     must still read back in the order they were allocated.
//   * Only `completion_status = 'finalized'` turns are loaded. A historical
//     turn left `pending` or `interrupted` by the retired live-voice channel
//     is durable evidence but is not model context.
//
// Summaries and memories are later checkpoints; this module stays a loader.
//
// Logging discipline: never log message text.

/** Newest turns pulled per request. Shared by both doors. */
export const AGENT_HISTORY_FETCH_LIMIT = 40

/** How many of those turns are replayed to the model, oldest first. */
export const AGENT_MODEL_HISTORY_TURNS = 20

interface ContextDatabaseResult<T> {
  data: T | null
  error: { message: string } | null
}

interface ContextDatabaseQuery {
  select(columns: string): ContextDatabaseQuery
  eq(column: string, value: unknown): ContextDatabaseQuery
  order(column: string, options: { ascending: boolean }): ContextDatabaseQuery
  limit(
    count: number,
  ): Promise<ContextDatabaseResult<Record<string, unknown>[]>>
}


export interface AgentContextClient {
  from(table: string): ContextDatabaseQuery
  /**
   * `public.allocate_agent_turn_slot` is a SECURITY DEFINER wrapper over the
   * real allocator in `chickmark_private`. The wrapper exists because PostgREST
   * only exposes `public` on this project, so a private-schema function is not
   * reachable over the REST API at all. Execute is granted to service_role
   * only, so this must be the door's admin client.
   */
  rpc(
    name: string,
    args: Record<string, unknown>,
  ): Promise<ContextDatabaseResult<unknown>>
}

export interface AgentContextTurn {
  id: string | null
  direction: string | null
  text: string | null
  turnIndex: number | null
  conversationSeq: number | null
  createdAt: string | null
}

export interface AgentContextModelTurn {
  role: 'user' | 'assistant'
  text: string
}

export interface AgentContextBundle {
  /** Newest-first, exactly as read back. */
  turns: AgentContextTurn[]
  /** Oldest-first and bounded, ready to hand to the runtime. */
  recentTurns: AgentContextModelTurn[]
  activeIntake: Record<string, unknown> | null
}

export interface AgentTurnSlot {
  conversationSeq: number
  turnIndex: number
}

/**
 * Loads the bounded model context for one conversation turn.
 *
 * Returns null when the history read fails — the doors map that to a 500. A
 * failed intake read is tolerated exactly as before: the turn still runs, just
 * without the intake session attached.
 */
export async function buildAgentContext(
  client: AgentContextClient,
  params: {
    conversationId: string
    contextEpoch: number
    /** Null skips the intake read entirely. */
    activeVisitId: string | null
    historyLimit?: number
    modelTurnLimit?: number
  },
): Promise<AgentContextBundle | null> {
  const historyLimit = params.historyLimit ?? AGENT_HISTORY_FETCH_LIMIT
  const historyResult = await client
    .from('agent_conversation_turns')
    .select(
      'id, direction, text, turn_index, conversation_seq, created_at',
    )
    .eq('conversation_id', params.conversationId)
    .eq('context_epoch', params.contextEpoch)
    .eq('completion_status', 'finalized')
    .order('conversation_seq', { ascending: false })
    .order('id', { ascending: false })
    .limit(historyLimit)
  if (historyResult.error) return null

  const turns = (historyResult.data ?? []).map((row): AgentContextTurn => ({
    id: nullableString(row.id),
    direction: nullableString(row.direction),
    text: nullableString(row.text),
    turnIndex: integerValue(row.turn_index),
    conversationSeq: integerValue(row.conversation_seq),
    createdAt: nullableString(row.created_at),
  }))

  const modelTurnLimit = params.modelTurnLimit ?? AGENT_MODEL_HISTORY_TURNS
  const recentTurns = turns
    .slice()
    .reverse()
    .flatMap((turn): AgentContextModelTurn[] => {
      const role = turn.direction === 'inbound'
        ? 'user' as const
        : turn.direction === 'outbound'
        ? 'assistant' as const
        : null
      return role && turn.text ? [{ role, text: turn.text }] : []
    })
    .slice(-modelTurnLimit)

  let activeIntake: Record<string, unknown> | null = null
  if (params.activeVisitId) {
    const activeResult = await client
      .from('agent_intake_sessions')
      .select(
        'id, visit_id, state, schema_key, schema_version, row_version, ' +
          'working_values_json, pending_clarification_json, summary_version, ' +
          'summary_snapshot_json, user_confirmed_at, updated_at',
      )
      .eq('visit_id', params.activeVisitId)
      .order('updated_at', { ascending: false })
      .order('id', { ascending: false })
      .limit(1)
    if (!activeResult.error) activeIntake = activeResult.data?.[0] ?? null
  }

  return { turns, recentTurns, activeIntake }
}

/**
 * Takes the next `conversation_seq` (and `turn_index`) for one turn.
 *
 * The allocator locks the conversation row and issues both keys from stored
 * counters, so two concurrent turns can never collide — which the old
 * client-side "max over the newest 40 rows" scan could not guarantee.
 *
 * Pass `turnIndexOverride` to reuse an inbound index on its paired outbound
 * reply, which is the convention both text doors follow. Pass null to allocate
 * an independent index.
 *
 * Returns null when the allocation fails; the doors map that to a 500.
 */
export async function allocateAgentTurnSlot(
  client: AgentContextClient,
  params: {
    conversationId: string
    contextEpoch: number
    direction: 'inbound' | 'outbound'
    turnIndexOverride?: number | null
  },
): Promise<AgentTurnSlot | null> {
  const result = await client
    .rpc('allocate_agent_turn_slot', {
      p_conversation_id: params.conversationId,
      p_context_epoch: params.contextEpoch,
      p_direction: params.direction,
      p_turn_index_override: params.turnIndexOverride ?? null,
    })
  if (result.error) return null
  const row = Array.isArray(result.data)
    ? result.data[0] as Record<string, unknown> | undefined
    : result.data as Record<string, unknown> | null
  if (!row) return null
  const conversationSeq = integerValue(row.conversation_seq)
  const turnIndex = integerValue(row.turn_index)
  if (conversationSeq === null || turnIndex === null) return null
  return { conversationSeq, turnIndex }
}

function nullableString(value: unknown): string | null {
  return typeof value === 'string' && value.trim().length > 0 ? value : null
}

function integerValue(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return Math.trunc(value)
  }
  if (typeof value === 'string' && value.trim().length > 0) {
    const parsed = Number(value)
    if (Number.isFinite(parsed)) return Math.trunc(parsed)
  }
  return null
}
