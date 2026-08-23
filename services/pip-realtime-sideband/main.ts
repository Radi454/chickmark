// Cloud Run entry point.

import { resolveBindAuthority } from './src/authorization.ts'
import { loadConfig } from './src/config.ts'
import { errorShape, log } from './src/log.ts'
import { PostgrestStore } from './src/store_postgrest.ts'
import { SupabaseJwtVerifier } from './src/jwt.ts'
import { RealtimeServer } from './src/server.ts'
import { sha256Hex } from './src/sideband.ts'
import { partitionToolCatalogue } from './src/session_config.ts'
import { brokeredToolRegistry, pipRealtimeToolBrokerExecutor } from './src/tools.ts'
import type { SessionRow } from './src/store.ts'

// Configuration is validated before anything else binds a port: an invalid value
// must crash the revision at startup, where the deploy fails loudly, rather than
// at the first session.
const config = loadConfig()

const store = new PostgrestStore({
  supabaseUrl: config.supabaseUrl,
  serviceRoleKey: config.supabaseServiceRoleKey,
})

const verifier = new SupabaseJwtVerifier({ supabaseUrl: config.supabaseUrl })

// THE TOOL PATH.
//
// Voice exposes the same catalogue the text channels expose, and executes it
// through the same shared runtime, by calling exactly one endpoint: the
// `pip-realtime-tool-broker` edge function. That function — not this service —
// re-resolves authorization, enforces argument scope, executes the tool, and
// owns BOTH durable rows (`agent_tool_call_claims`, `agent_tool_events`). The
// registry below therefore declares `ledger: 'broker'`, and the coordinator
// writes neither table for these calls; both carry partial unique indexes on the
// Realtime key, so a second writer would raise rather than duplicate.
//
// The DEFINITIONS are not written here. They are rendered from the versioned
// `AGENT_TOOL_CONTRACT` and supplied as configuration
// (PIP_REALTIME_TOOL_DEFINITIONS) — see src/config.ts for why an import is not
// possible across the two deployments, and tools/render_tool_definitions.ts for
// the renderer that produces the value. An absent or malformed value fails
// startup: a voice session that silently exposes no tools looks healthy and is
// useless.
const registry = brokeredToolRegistry(
  config.toolDefinitions,
  pipRealtimeToolBrokerExecutor({
    url: config.toolBrokerUrl,
    brokerSecret: config.toolBrokerSecret,
  }),
)

/**
 * Authorization is resolved from the database on every bind. The access token
 * proves identity; approval status and customer scope are server-side facts that
 * can have changed since the session was provisioned. The resolution and the
 * fingerprint derivation live in src/authorization.ts and are kept
 * byte-identical to the provisioner's — the previous inline version drifted to
 * a legacy `role:customerId` string and every bind died as
 * `fingerprint_changed`.
 */
async function authorize(profileId: string, session: SessionRow) {
  const authority = await resolveBindAuthority({
    supabaseUrl: config.supabaseUrl,
    serviceRoleKey: config.supabaseServiceRoleKey,
    profileId,
  })
  return {
    authorized: authority.authorized &&
      (session.ownerStaffLinkId === null ||
        session.ownerStaffLinkId === authority.staffLinkId),
    fingerprint: authority.fingerprint,
  }
}

const server = new RealtimeServer({
  config,
  store,
  verifier,
  authorize,
  tools: registry.definitions,
  ownership: registry.ownership,
  instructions: config.instructions,
})

// LAST-RESORT GUARD. Deno terminates the process on an unhandled rejection,
// and this service holds many concurrent live calls on one instance — so a
// single missing `.catch` anywhere on a fire-and-forget path (event dispatch,
// a lease heartbeat, a telemetry write) would drop EVERY call on the
// instance, not just the one that failed. The individual call sites each
// handle their own errors; this exists because that guarantee is one edit away
// from being untrue at any time, and the blast radius of being wrong is the
// whole instance. Preventing the default is deliberate: a logged rejection is
// a bug to fix, not a reason to hang up on everybody mid-sentence.
globalThis.addEventListener('unhandledrejection', (event) => {
  event.preventDefault()
  log.error('process.unhandled_rejection', { detail: errorShape(event.reason) })
})

// Cloud Run's SIGTERM grace is a fixed 10 seconds. The handler must therefore
// finish a bounded handoff and exit; anything slower is the sweeper's job.
Deno.addSignalListener('SIGTERM', () => {
  log.info('sigterm.received')
  server.drainNow()
    .then((report) => {
      log.info('sigterm.drained', { duration_ms: report.durationMs })
      Deno.exit(0)
    })
    .catch(() => Deno.exit(1))
})

const port = Number(Deno.env.get('PORT') ?? '8080')
// Every session starts on the CORE catalogue and upgrades to the full one
// only after a successful `propose_intake` (see `INTAKE_STAGED_TOOL_NAMES`
// and `SidebandSession#maybeUpgradeToolCatalogue`). Computed here purely for
// this log line — the actual per-session partition happens again, from the
// same pure function, inside `SidebandSession`'s constructor — so a deployed
// revision's split is provable from its startup line without having to wait
// for a live session to prove it.
const toolCataloguePartition = partitionToolCatalogue(config.toolDefinitions)
// The catalogue travels across the deployment boundary as a rendered env var,
// and `AGENT_TOOL_CONTRACT_VERSION` does NOT move when only the model-facing
// PROJECTION of the contract changes — so a revision still running a stale
// rendering is otherwise indistinguishable from a fresh one, and silently gets
// none of the token saving. This digest of the deployed definitions is what
// makes that visible. To reproduce it for the catalogue this checkout would
// deploy (the digest is over the RE-SERIALISED array, not the raw file, so a
// plain `shasum` of the renderer's output will not match):
//
//   deno eval "const t = JSON.parse(await new Deno.Command('deno', { args: \
//     ['run','--allow-read','tools/render_tool_definitions.ts'] }).output() \
//     .then((o) => new TextDecoder().decode(o.stdout))); \
//     const d = await crypto.subtle.digest('SHA-256', \
//       new TextEncoder().encode(JSON.stringify(t))); \
//     console.log([...new Uint8Array(d)].map((b) => \
//       b.toString(16).padStart(2,'0')).join('').slice(0,16))"
const toolDefinitionsSha = (await sha256Hex(JSON.stringify(config.toolDefinitions)))
  .slice(0, 16)
// Never log the broker secret or the Supabase key. Counts, the contract
// version and the catalogue digest are enough to tell a bad deploy from a
// good one — the definitions themselves are never logged.
log.info('server.starting', {
  port,
  enabled: config.enabled,
  tool_count: registry.definitions.length,
  core_tool_count: toolCataloguePartition.core.length,
  full_tool_count: toolCataloguePartition.full.length,
  tool_contract_version: config.toolContractVersion,
  tool_definitions_sha256: toolDefinitionsSha,
  instruction_version: config.instructionVersion,
})
Deno.serve({ port }, (request) => server.handle(request))
