// The catalogue crossing the deployment boundary, and the mutation
// classification that rides alongside it.
//
// WHY THIS TEST LIVES HERE
//
// Two facts about the tool catalogue are enforced in two different deployments
// and neither can see the other at runtime:
//
//   1. The MODEL-FACING definitions the sideband hands to the Realtime session
//      are rendered from `AGENT_TOOL_CONTRACT` and delivered as configuration.
//      Nothing at runtime can tell a stale rendering from a fresh one.
//
//   2. The broker's `MUTATION_TOOL_NAMES` decides how a claim settles when a
//      call ends without a trustworthy answer: a read that breaks halfway is
//      `failed` and replayable, a WRITE that breaks halfway is `indeterminate`
//      and never auto-replayed. The contract carries NO mutation flag, so that
//      list is hand-maintained. A new write tool added to the contract and
//      missed there would settle as `failed`, be replayed on the next
//      redelivery, and double-apply the write. That is silent data corruption.
//
// The broker keeps `MUTATION_TOOL_NAMES` module-private, so this test reads the
// broker's SOURCE rather than importing it. That is deliberate: the assertion
// has to fail when the broker's list drifts from the contract, and the only two
// places that can observe both trees at once are this suite and the broker's
// own — where the list would be checked against itself. Reading the source keeps
// the check honest across the boundary. If the regex below ever stops matching,
// the test fails loudly rather than passing vacuously.

import { assert, assertEquals } from '@std/assert'

import { AGENT_TOOL_CONTRACT } from '../../../supabase/functions/telegram-hatchery-agent/agent_tool_contract.ts'
import {
  renderRealtimeToolDefinitions,
  renderToolDefinitionsJson,
} from '../tools/render_tool_definitions.ts'
import {
  RENDERED_INSTRUCTION_VERSION,
  renderRealtimeInstructions,
} from '../tools/render_agent_instructions.ts'
import { loadConfig } from '../src/config.ts'
import { INTAKE_STAGED_TOOL_NAMES } from '../src/session_config.ts'

/**
 * Tools that can change durable state. Adding a tool to the contract without
 * adding it to exactly ONE of these two sets fails the first test below — which
 * is the entire point: the decision is forced, never defaulted.
 */
const MUTATING: ReadonlySet<string> = new Set([
  'propose_intake',
  'start_intake',
  'record_station_values',
  'create_station_summary',
  'confirm_station_summary',
  'submit_station_for_review',
  'pause_intake',
  'resume_intake',
  'cancel_intake',
  'answer_legacy_draft_question',
])

/**
 * Tools that answer a question and change no durable domain state.
 *
 * `select_audit_option` is here deliberately, not by oversight: it persists a
 * selection in the server-side CONVERSATION CONTEXT, which is re-derivable and
 * safe to re-apply, so replaying it cannot double-apply anything a user would
 * see. Every other entry is a pure read.
 */
const READ_ONLY: ReadonlySet<string> = new Set([
  'get_user_scope',
  'list_customers',
  'resolve_customer_flock',
  'get_customer_context',
  'list_customer_flocks',
  'list_customer_hatcheries',
  'list_customer_audits',
  'select_audit_option',
  'get_audit_summary',
  'get_selected_audit_breakouts',
  'get_breed_benchmark',
  'get_egg_breakout_benchmark',
  'get_operational_standards',
  'compare_selected_audit_to_benchmark',
  'get_flock_context',
  'query_station_records',
  'compare_station_metrics',
  'get_record_provenance',
  'list_applicable_stations',
  'load_station_schema',
  'get_intake_status',
  'list_legacy_draft_questions',
])

const BROKER_SOURCE_URL = new URL(
  '../../../supabase/functions/pip-realtime-tool-broker/index.ts',
  import.meta.url,
)

/** The broker's hand-maintained list, read from its source. */
async function brokerMutationToolNames(): Promise<Set<string>> {
  const source = await Deno.readTextFile(BROKER_SOURCE_URL)
  const block = /const MUTATION_TOOL_NAMES[^=]*=\s*new Set<[^>]*>\(\[([\s\S]*?)\]\)/
    .exec(source)
  assert(
    block,
    'MUTATION_TOOL_NAMES could not be located in the broker source. If it moved ' +
      'or changed shape, update this test — do not delete it.',
  )
  const names = [...block[1].matchAll(/'([a-z_]+)'/g)].map((match) => match[1])
  assert(names.length > 0, 'MUTATION_TOOL_NAMES parsed as empty')
  return new Set(names)
}

Deno.test('every tool in the contract is explicitly classified as mutating or not', () => {
  const unclassified: string[] = []
  const doubleClassified: string[] = []
  for (const entry of AGENT_TOOL_CONTRACT) {
    const mutating = MUTATING.has(entry.name)
    const readOnly = READ_ONLY.has(entry.name)
    if (!mutating && !readOnly) unclassified.push(entry.name)
    if (mutating && readOnly) doubleClassified.push(entry.name)
  }
  assertEquals(
    unclassified,
    [],
    'These contract tools are classified nowhere. Decide, for each, whether it ' +
      'can change durable state, then add it to MUTATING or READ_ONLY here AND ' +
      'to MUTATION_TOOL_NAMES in the broker if it mutates.',
  )
  assertEquals(doubleClassified, [], 'A tool cannot be both mutating and read-only.')

  // And nothing classified here may have vanished from the contract, or the
  // lists would slowly fill with names that no longer mean anything.
  const contractNames = new Set<string>(AGENT_TOOL_CONTRACT.map((entry) => entry.name))
  const stale = [...MUTATING, ...READ_ONLY].filter((name) => !contractNames.has(name))
  assertEquals(stale, [], 'Classified tools that are no longer in the contract.')
})

Deno.test("the broker's mutation list matches the classification exactly", async () => {
  const broker = await brokerMutationToolNames()

  const missingInBroker = [...MUTATING].filter((name) => !broker.has(name)).sort()
  assertEquals(
    missingInBroker,
    [],
    'These write tools are NOT in the broker MUTATION_TOOL_NAMES. A failure ' +
      'mid-write would settle as `failed` instead of `indeterminate`, and the ' +
      'call would be replayable — double-applying the write.',
  )

  const extraInBroker = [...broker].filter((name) => !MUTATING.has(name)).sort()
  assertEquals(
    extraInBroker,
    [],
    'The broker treats these as mutations but this suite classifies them as ' +
      'reads. One of the two is wrong.',
  )
})

Deno.test('the rendered definitions cover the whole contract, in the flat shape', () => {
  const definitions = renderRealtimeToolDefinitions()
  assertEquals(
    definitions.map((definition) => definition.name),
    AGENT_TOOL_CONTRACT.map((entry) => entry.name),
  )
  for (const definition of definitions) {
    assertEquals(definition.type, 'function')
    assert(definition.description.length > 0)
    // Flat, never `{type:'function', function:{...}}`.
    assertEquals(
      (definition as unknown as Record<string, unknown>).function,
      undefined,
    )
    assertEquals((definition.parameters as Record<string, unknown>).type, 'object')
  }
})

Deno.test('the rendered value is accepted by loadConfig as-is', () => {
  const env: Record<string, string> = {
    SUPABASE_URL: 'https://example.supabase.co',
    SUPABASE_SERVICE_ROLE_KEY: 'service-key',
    OPENAI_API_KEY: 'openai-key',
    PIP_REALTIME_TOOL_BROKER_URL:
      'https://example.supabase.co/functions/v1/pip-realtime-tool-broker',
    PIP_REALTIME_BROKER_SECRET: 'broker-secret',
    PIP_REALTIME_TOOL_DEFINITIONS: renderToolDefinitionsJson(),
    PIP_REALTIME_INSTRUCTIONS: renderRealtimeInstructions(),
    PIP_REALTIME_INSTRUCTIONS_VERSION: RENDERED_INSTRUCTION_VERSION,
  }
  const config = loadConfig((key) => env[key])
  assertEquals(config.toolDefinitions.length, AGENT_TOOL_CONTRACT.length)
  assertEquals(config.toolDefinitions[0].name, AGENT_TOOL_CONTRACT[0].name)
})

// `partitionToolCatalogue` deliberately TOLERATES a staged name that is absent
// from the deployed catalogue, so a sideband running against an older or newer
// rendering still boots instead of failing closed on version skew. That
// tolerance is right at runtime and useless at build time: a typo like
// `cancel_Intake` would stage nothing, cost nothing in CI, and quietly give
// back the entire saving while every test stayed green. This is the build-time
// half of that pair — the only place that can see both trees at once.
Deno.test('every staged intake tool name exists in the contract', () => {
  const known = new Set(AGENT_TOOL_CONTRACT.map((entry) => entry.name as string))
  const unknown = INTAKE_STAGED_TOOL_NAMES.filter((name) => !known.has(name))
  assertEquals(
    unknown,
    [],
    `staged tool names missing from AGENT_TOOL_CONTRACT: ${unknown.join(', ')}`,
  )
})

Deno.test('staging never withholds a tool the model needs before propose_intake', () => {
  // The gate's whole safety argument is that every staged tool requires an id
  // only `propose_intake` or `start_intake` can mint. Assert that structurally
  // rather than trusting the prose: each staged tool must REQUIRE either
  // `pendingActionId` or `intakeId`.
  const byName = new Map(
    AGENT_TOOL_CONTRACT.map((entry) => [entry.name as string, entry]),
  )
  for (const name of INTAKE_STAGED_TOOL_NAMES) {
    const required = byName.get(name)?.parameters.required ?? []
    assert(
      required.includes('pendingActionId') || required.includes('intakeId'),
      `${name} is staged but requires neither pendingActionId nor intakeId, so the model could legitimately need it before propose_intake`,
    )
  }
})
