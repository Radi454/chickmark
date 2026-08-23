// Tool registry.
//
// The domain tools themselves (BMK lookups, flock reads, intake writes) live in
// the edge-function runtime and are shared across channels. This service's job
// is the Realtime CONTROL path: claiming, capping, executing and evidencing tool
// calls. It therefore takes its tool set by injection rather than hard-coding a
// second copy of the catalogue that could drift from the text channel's.
//
// Definitions must use the FLAT Realtime shape — `{type, name, description,
// parameters}` — not the nested Chat Completions `{type, function:{...}}`.

import { log } from './log.ts'
import type { RealtimeToolDefinition } from './session_config.ts'
import type { ToolExecutor, ToolLedgerOwnership, ToolOutcome } from './claims.ts'

/**
 * A registry names both what the model may call AND who owns the durable ledger
 * for those calls. The two travel together on purpose: wiring definitions
 * without saying who writes the claim is exactly how two writers happen.
 */
export interface ToolRegistry {
  readonly definitions: readonly RealtimeToolDefinition[]
  readonly ownership: ToolLedgerOwnership
}

export function emptyToolRegistry(): ToolRegistry {
  return { definitions: [], ownership: { ledger: 'sideband', executors: new Map() } }
}

/**
 * Concrete client for the `pip-realtime-tool-broker` edge function.
 *
 * That function is the least-privilege boundary around the shared agent
 * runtime: it authenticates THIS SERVICE with a shared secret, re-resolves the
 * caller's authority from the database, recomputes the authorization
 * fingerprint, verifies the generation, and only then executes the tool. Every
 * field below is therefore either a server-resolved fact this service already
 * holds, or a claim the broker re-checks — the client never gets to name the
 * scope its tool call runs under, and the fingerprint sent here is compared
 * against a freshly derived one rather than trusted.
 *
 * OWNERSHIP BOUNDARY. The broker owns the `agent_tool_call_claims` row and the
 * `agent_tool_events` evidence row for every call it executes; both tables carry
 * partial unique indexes on (realtime_session_id, realtime_generation, ...), so
 * a second writer for the same call id is a unique violation, not a duplicate
 * record. This executor must therefore only ever be reached through a registry
 * whose ownership is `{ledger: 'broker'}` — use `brokeredToolRegistry` below,
 * which is the only constructor that pairs the two.
 *
 * The per-interaction tool cap stays HERE, in InteractionTracker. The broker
 * deliberately enforces no cap of its own.
 */
/**
 * How long a single broker call may take before it is abandoned.
 *
 * THERE IS NO DEFAULT TIMEOUT ON `fetch`. Without this bound, a broker that
 * HANGS — a wedged PostgREST query, a half-open TCP connection where no RST
 * ever arrives — never settles the promise, and the damage is not confined to
 * the one call:
 *
 *   1. `#onOutputItemDone` blocks before it sends the `function_call_output`,
 *      so the provider's response chain stays open and the caller hears
 *      nothing;
 *   2. that handler runs on a serialized chain, so EVERY later tool call on
 *      the session queues behind the hung one forever — the session goes
 *      permanently mute to tool work while still reporting healthy.
 *
 * A hang is strictly worse than a failure, and this converts one into the
 * other. Sized above the slowest legitimate tool (the audit reader pages
 * through `MAX_SCANNED_AUDIT_ROWS`) and well below the dead air a caller will
 * sit through.
 */
export const BROKER_TIMEOUT_MS = 12_000

export function pipRealtimeToolBrokerExecutor(options: {
  url: string
  /** Never logged. Travels only in the request header, over TLS. */
  brokerSecret: string
  fetchImpl?: typeof fetch
  /** Overrides BROKER_TIMEOUT_MS. Test seam only. */
  timeoutMs?: number
}): ToolExecutor {
  const fetchImpl = options.fetchImpl ?? fetch
  const timeoutMs = options.timeoutMs ?? BROKER_TIMEOUT_MS
  return async (args, context): Promise<ToolOutcome> => {
    let response: Response
    // An owned controller rather than `AbortSignal.timeout` alone, so the
    // timer is cleared on the normal path and a long session does not
    // accumulate one pending timer per tool call.
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), timeoutMs)
    try {
      response = await fetchImpl(options.url, {
        method: 'POST',
        signal: controller.signal,
        headers: {
          'content-type': 'application/json',
          'x-pip-broker-secret': options.brokerSecret,
        },
        body: JSON.stringify({
          session_id: context.sessionId,
          generation: context.generation,
          tool_call_id: context.toolCallId,
          tool_name: context.toolName,
          arguments: args ?? {},
          interaction_id: context.interactionId,
          authorization_fingerprint: context.authorizationFingerprint,
        }),
      })
    } catch {
      // Unreachable OR unresponsive: DNS, TLS, connect timeout, or our own
      // abort above. The model is told the tool failed. Inventing a success
      // here would have the assistant report work that never happened.
      //
      // The two are reported separately because they mean different things:
      // nothing ran, versus something may still be running. A mutation that
      // timed out is NOT known not to have applied — the broker owns the claim
      // ledger, so a redelivery of the same call id replays rather than
      // re-executes.
      const timedOut = controller.signal.aborted
      log.warn('tool.broker_call_failed', {
        session_id: context.sessionId,
        generation: context.generation,
        interaction_id: context.interactionId,
        tool_name: context.toolName,
        reason: timedOut ? 'timeout' : 'unreachable',
      })
      return {
        status: 'failed',
        result: {
          ok: false,
          error: timedOut ? 'broker_timeout' : 'broker_unreachable',
        },
      }
    } finally {
      clearTimeout(timer)
    }

    const payload = await readJson(response)
    if (!response.ok) {
      // The broker's refusal codes are stable and safe to surface: they name a
      // control-plane decision, never anything about the user's data.
      const code = typeof payload?.code === 'string'
        ? payload.code
        : `broker_${response.status}`
      // A 5xx is the broker BREAKING; a 4xx is the broker REFUSING. Reporting a
      // breakage as a refusal would tell the model its request was the problem
      // and invite it to rephrase a request that was never the issue.
      const status = response.status >= 500 ? 'failed' : 'rejected'
      return { status, result: { ok: false, error: code } }
    }
    // A 200 whose body is not the agreed shape is a broken broker, not a
    // success. Defaulting to `succeeded` here is precisely how a tool that never
    // ran gets reported to the user as done.
    if (
      payload === null ||
      (payload.status !== 'succeeded' && payload.status !== 'rejected' &&
        payload.status !== 'failed')
    ) {
      return {
        status: 'failed',
        result: { ok: false, error: 'broker_malformed_response' },
      }
    }
    return {
      status: payload.status,
      result: payload.result ?? { ok: payload.status === 'succeeded' },
      duplicate: payload.disposition === 'duplicate',
    }
  }
}

async function readJson(
  response: Response,
): Promise<
  {
    status?: string
    result?: unknown
    code?: string
    disposition?: string
  } | null
> {
  try {
    return await response.json()
  } catch {
    return null
  }
}

/**
 * The ONLY way to build a registry around the broker: every definition maps to
 * the one broker executor, and the ledger is declared `broker` in the same
 * expression. Nothing can wire the broker executor under sideband ownership
 * without deliberately hand-building the union, which is the point.
 */
export function brokeredToolRegistry(
  definitions: readonly RealtimeToolDefinition[],
  executor: ToolExecutor,
): ToolRegistry {
  const executors = new Map<string, ToolExecutor>()
  for (const definition of definitions) executors.set(definition.name, executor)
  return { definitions, ownership: { ledger: 'broker', executors } }
}
