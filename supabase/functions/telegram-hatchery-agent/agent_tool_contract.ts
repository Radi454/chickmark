/**
 * Model-facing tool contract for the ChickMark agent.
 *
 * This file is the ONLY surface the model sees: stable tool names, their
 * descriptions, and their JSON-Schema parameters. Everything downstream —
 * `AGENT_TOOL_DEFINITIONS`, the runtime's known-tool set, the gateway's
 * argument validation — is derived from here, so there is exactly one source
 * of truth.
 *
 * The rule: this file changes only when a business capability changes. The
 * physical Supabase schema is free to evolve underneath it. Renaming a column
 * or reshaping a table must NOT move the contract.
 *
 *   Allowed without touching this file (storage-only change):
 *     `flock_audits.audit_date` is renamed to `flock_audits.recorded_on`, or
 *     egg-breakout counts are split out of `flock_audits` into a new
 *     `flock_audit_breakouts` table. `get_audit_summary` still takes no
 *     arguments and still answers the same question, so the contract and its
 *     fingerprint stay byte-identical; only the handler's SQL changes.
 *
 *   Requires a version bump (business capability change):
 *     `get_breed_benchmark` starts accepting a `flockAgeDays` alongside
 *     `ageWeek`, or a new `list_customer_incubators` tool is exposed. The
 *     model can now ask for something it could not ask for before, so
 *     `AGENT_TOOL_CONTRACT_VERSION` moves and the pinned snapshot in
 *     `agent_tool_contract_test.ts` is updated in the same commit.
 *
 * Note: `schemaKey` enumerates the generated station registry, so registering
 * a new station module does move the fingerprint. That is intentional — a new
 * station is a new business capability the model can name, not a storage
 * detail.
 */
import { type AgentToolName } from './agent_protocol.ts'
import { agentStationRegistry } from '../_shared/station_registry.generated.ts'

export const AGENT_TOOL_CONTRACT_VERSION = '1.3.0'

export const MAX_AGENT_READ_ROWS = 100

export type JsonType =
  | 'string'
  | 'integer'
  | 'number'
  | 'boolean'
  | 'object'
  | 'array'

export interface ArgumentRule {
  type: JsonType
  minLength?: number
  maxLength?: number
  minimum?: number
  maximum?: number
  enum?: readonly (string | number | boolean)[]
  pattern?: string
}

export interface ObjectArguments {
  type: 'object'
  properties: Readonly<Record<string, ArgumentRule>>
  required: readonly string[]
  additionalProperties: false
}

export interface AgentToolContractEntry {
  name: AgentToolName
  description: string
  parameters: ObjectArguments
}

const idRule: ArgumentRule = {
  type: 'string',
  minLength: 1,
  maxLength: 160,
}
const schemaKeyRule: ArgumentRule = {
  type: 'string',
  minLength: 1,
  maxLength: 120,
  enum: agentStationRegistry.stations.map((schema) => schema.schemaKey),
}
const measureKeyRule: ArgumentRule = {
  type: 'string',
  minLength: 1,
  maxLength: 120,
}
const dateRule: ArgumentRule = {
  type: 'string',
  pattern: '^\\d{4}-\\d{2}-\\d{2}$',
}
const limitRule: ArgumentRule = {
  type: 'integer',
  minimum: 1,
  maximum: MAX_AGENT_READ_ROWS,
}
const auditLimitRule: ArgumentRule = {
  type: 'integer',
  minimum: 1,
  maximum: 20,
}
const auditPositionRule: ArgumentRule = {
  type: 'integer',
  minimum: 1,
  maximum: 20,
}
const versionRule: ArgumentRule = {
  type: 'integer',
  minimum: 1,
  maximum: 1000,
}
const ageWeekRule: ArgumentRule = {
  type: 'integer',
  minimum: 1,
  maximum: 120,
}
const breedRule: ArgumentRule = {
  type: 'string',
  minLength: 1,
  maxLength: 60,
}
const metricsRule: ArgumentRule = {
  type: 'string',
  minLength: 1,
  maxLength: 120,
}

function entry(
  name: AgentToolName,
  description: string,
  properties: Record<string, ArgumentRule> = {},
  required: readonly string[] = [],
): AgentToolContractEntry {
  return {
    name,
    description,
    parameters: {
      type: 'object',
      properties,
      required,
      additionalProperties: false,
    },
  }
}

export const AGENT_TOOL_CONTRACT: readonly AgentToolContractEntry[] = Object
  .freeze([
    entry(
      'get_user_scope',
      'Return the customer access already enforced for this Telegram user.',
    ),
    entry(
      'list_customers',
      'List customers inside the server-enforced scope. Use this instead of guessing from raw customer IDs.',
    ),
    entry(
      'resolve_customer_flock',
      'Resolve an allowed customer name and optional flock name together using exact normalized names. Use this before ID-based tools when the user supplies names.',
      {
        customerName: idRule,
        flockName: idRule,
      },
      ['customerName'],
    ),
    entry(
      'get_customer_context',
      'Load an allowed customer context.',
      { customerId: idRule },
      ['customerId'],
    ),
    entry(
      'list_customer_flocks',
      'List flocks for an allowed customer.',
      { customerId: idRule, limit: limitRule },
      ['customerId'],
    ),
    entry(
      'list_customer_hatcheries',
      'List hatcheries for an allowed customer.',
      { customerId: idRule, limit: limitRule },
      ['customerId'],
    ),
    entry(
      'list_customer_audits',
      'List a bounded page of recent audit options for an allowed customer and optional flock so the user can choose one.',
      { customerId: idRule, flockId: idRule, limit: auditLimitRule },
      ['customerId'],
    ),
    entry(
      'select_audit_option',
      'Select one numbered audit from the latest persisted audit options in this conversation. Use position 1 for an affirmative confirmation after offering the only displayed option.',
      { position: auditPositionRule },
      ['position'],
    ),
    entry(
      'get_audit_summary',
      'Reload the verified summary of the audit already selected in the server conversation context. Never supply or reconstruct an audit ID.',
    ),
    entry(
      'get_selected_audit_breakouts',
      'Load allowlisted fresh, candled, and residue egg-breakout measurements for the latest persisted selected audit in this conversation.',
    ),
    entry(
      'get_flock_context',
      'Load one authorized flock and its operational context.',
      { flockId: idRule },
      ['flockId'],
    ),
    entry(
      'query_station_records',
      'Read allowlisted station records in a bounded date range.',
      {
        customerId: idRule,
        flockId: idRule,
        schemaKey: schemaKeyRule,
        schemaVersion: versionRule,
        fromDate: dateRule,
        toDate: dateRule,
        limit: limitRule,
      },
      ['customerId', 'schemaKey', 'schemaVersion', 'fromDate', 'toDate'],
    ),
    entry(
      'compare_station_metrics',
      'Compare deterministic station metrics from authorized records.',
      {
        customerId: idRule,
        flockId: idRule,
        schemaKey: schemaKeyRule,
        schemaVersion: versionRule,
        measureKey: measureKeyRule,
        fromDate: dateRule,
        toDate: dateRule,
      },
      [
        'customerId',
        'schemaKey',
        'schemaVersion',
        'measureKey',
        'fromDate',
        'toDate',
      ],
    ),
    entry(
      'get_record_provenance',
      'Load the source context and freshness of an authorized record.',
      {
        schemaKey: schemaKeyRule,
        schemaVersion: versionRule,
        recordId: idRule,
      },
      ['schemaKey', 'schemaVersion', 'recordId'],
    ),
    entry(
      'list_applicable_stations',
      'List station modules applicable to an authorized flock sector.',
      { customerId: idRule, flockId: idRule },
      ['customerId', 'flockId'],
    ),
    entry(
      'load_station_schema',
      'Load fields and validation for one versioned station module.',
      { schemaKey: schemaKeyRule, schemaVersion: versionRule },
      ['schemaKey', 'schemaVersion'],
    ),
    entry(
      'get_breed_benchmark',
      'Look up the published breed standard (hatchability, fertility, HOF, production, egg weight, chick weight) for one breed at one flock age in weeks. Always use this instead of stating a benchmark from memory. When the user asks for specific metrics, pass metrics as comma-separated keys from: production, hatchability, fertility, hof, egg_weight, chick_weight. Omit metrics only when the user explicitly wants the full standard.',
      { breed: breedRule, ageWeek: ageWeekRule, metrics: metricsRule },
      ['breed', 'ageWeek'],
    ),
    entry(
      'get_egg_breakout_benchmark',
      'Look up the published egg-breakout standard (infertile, early/mid/late dead, blood ring, black eye, external pip, cracked, contaminated) for one flock age in weeks. Always use this instead of stating a benchmark from memory. When the user asks for specific metrics, pass metrics as comma-separated keys from: infertile, early_24h, early_48h, blood_ring, black_eye, early_dead, mid_dead, late_dead, external_pip, cracked, contaminated. Omit metrics only when the user explicitly wants the full standard.',
      { ageWeek: ageWeekRule, metrics: metricsRule },
      ['ageWeek'],
    ),
    entry(
      'get_operational_standards',
      "Look up operational target ranges (temperature, humidity, airflow and similar) for a station. Global standards apply everywhere; a hatchery may override any of them. Pass hatcheryId to get that hatchery's effective standards.",
      {
        stationKey: measureKeyRule,
        sectorKey: measureKeyRule,
        hatcheryId: idRule,
      },
      [],
    ),
    entry(
      'compare_selected_audit_to_benchmark',
      "Compare the audit already selected in this conversation against the published breed and egg-breakout standards for that flock's breed and age. Returns actual, standard and delta per metric. Never supply or reconstruct an audit ID.",
    ),
    entry(
      'propose_intake',
      'Record a proposed data-entry action for user confirmation.',
      {
        customerId: idRule,
      },
      ['customerId'],
    ),
    entry(
      'start_intake',
      'Start intake only from a recently confirmed proposal.',
      {
        pendingActionId: idRule,
        schemaKey: schemaKeyRule,
        schemaVersion: versionRule,
        customerId: idRule,
        flockId: idRule,
        hatcheryId: idRule,
        auditDate: dateRule,
        layer: {
          type: 'string',
          enum: [
            'pool',
            'house',
            'setter',
            'hatcher',
            'setter_hatcher',
            'trolley',
            'tray',
          ],
        },
        houseIdentity: idRule,
        setterIdentity: idRule,
        hatcherIdentity: idRule,
      },
      [
        'pendingActionId',
        'schemaKey',
        'schemaVersion',
        'customerId',
        'flockId',
        'hatcheryId',
        'auditDate',
        'layer',
      ],
    ),
    entry(
      'record_station_values',
      'Validate and record explicit station values without finalizing them.',
      {
        intakeId: idRule,
        expectedRowVersion: versionRule,
        values: { type: 'array' },
      },
      ['intakeId', 'expectedRowVersion', 'values'],
    ),
    entry(
      'get_intake_status',
      'Return accepted values, missing fields, and unresolved clarifications.',
      { intakeId: idRule },
      ['intakeId'],
    ),
    entry(
      'create_station_summary',
      'Create one versioned summary after all required values are valid.',
      { intakeId: idRule, expectedRowVersion: versionRule },
      ['intakeId', 'expectedRowVersion'],
    ),
    entry(
      'confirm_station_summary',
      'Confirm the exact current station summary version.',
      {
        intakeId: idRule,
        expectedRowVersion: versionRule,
        summaryVersion: versionRule,
      },
      ['intakeId', 'expectedRowVersion', 'summaryVersion'],
    ),
    entry(
      'submit_station_for_review',
      'Submit a confirmed station intake for administrator review.',
      { intakeId: idRule, expectedRowVersion: versionRule },
      ['intakeId', 'expectedRowVersion'],
    ),
    entry(
      'pause_intake',
      'Pause an active intake.',
      { intakeId: idRule, expectedRowVersion: versionRule },
      [
        'intakeId',
        'expectedRowVersion',
      ],
    ),
    entry(
      'resume_intake',
      'Resume a paused intake.',
      { intakeId: idRule, expectedRowVersion: versionRule },
      [
        'intakeId',
        'expectedRowVersion',
      ],
    ),
    entry(
      'cancel_intake',
      'Cancel an intake.',
      { intakeId: idRule, expectedRowVersion: versionRule },
      ['intakeId', 'expectedRowVersion'],
    ),
    entry(
      'list_legacy_draft_questions',
      'List unresolved questions from an authorized legacy draft.',
      { submissionId: idRule },
      ['submissionId'],
    ),
    entry(
      'answer_legacy_draft_question',
      'Record an answer to one unresolved authorized legacy draft question.',
      {
        submissionId: idRule,
        questionId: idRule,
        answer: { type: 'string', minLength: 1, maxLength: 2000 },
      },
      ['submissionId', 'questionId', 'answer'],
    ),
  ])

/**
 * Stable FNV-1a 64-bit digest over the canonicalised contract: tools sorted by
 * name, object keys sorted recursively, array order preserved because
 * `required` and `enum` order is part of the model-facing surface. Any change
 * to a tool name, description, parameter, required flag or enum moves this.
 */
export function contractFingerprint(): string {
  const canonical = JSON.stringify(
    canonicalize(
      [...AGENT_TOOL_CONTRACT].sort((a, b) => a.name < b.name ? -1 : 1),
    ),
  )
  let hash = 0xcbf29ce484222325n
  const mask = 0xffffffffffffffffn
  for (const byte of new TextEncoder().encode(canonical)) {
    hash = (hash ^ BigInt(byte)) * 0x100000001b3n & mask
  }
  return hash.toString(16).padStart(16, '0')
}

function canonicalize(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalize)
  if (value === null || typeof value !== 'object') return value
  return Object.fromEntries(
    Object.entries(value as Record<string, unknown>)
      .sort(([a], [b]) => a < b ? -1 : 1)
      .map(([key, child]) => [key, canonicalize(child)]),
  )
}

/**
 * Tools where the `schemaKey` enum earns its keep on the model-facing
 * surface:
 *
 *   - `load_station_schema` is the discovery tool — the enum is what lets the
 *     model pick a valid key in the first place.
 *   - `start_intake` commits a write — a wrong key there is expensive, so the
 *     enum stays as a guardrail.
 *
 *   - `query_station_records` and `compare_station_metrics` are called COLD.
 *     The historical `inference-language` eval scenario (from the retired
 *     live-voice harness) had the user ask "did hatchability drop because of
 *     storage?" and expected both tools to fire with no prior
 *     `list_applicable_stations`/`load_station_schema` turn, so the model
 *     must name a station from the request alone. Measured
 *     live: dropping the enum from these two saves 262 input tokens per
 *     inference, but one invented key costs a rejected call plus a whole
 *     retry inference (~4,600 tokens), so the enum pays for itself if it
 *     prevents one bad key per ~18 inferences. It stays.
 *
 * `get_record_provenance` is the one tool that genuinely never needs it: it
 * requires a `recordId`, which only ever arrives in a `query_station_records`
 * result, so the `schemaKey` is always already in hand and repeating the
 * 18-key enum there is pure token cost with no tool-selection value.
 */
const SCHEMA_KEY_ENUM_TOOLS: ReadonlySet<AgentToolName> = new Set([
  'load_station_schema',
  'start_intake',
  'query_station_records',
  'compare_station_metrics',
])

/**
 * Projects one contract entry's parameters down to what the model needs to
 * pick and fill a tool call correctly. This is NOT a validation schema — the
 * server (`agent_tools.ts`'s `validArguments`) enforces the full
 * `AgentToolContractEntry.parameters` regardless of what the model was shown.
 *
 * Removed everywhere: `minLength`/`maxLength`. Pure length bounds; they carry
 * no tool-selection value and are re-enforced server-side either way.
 *
 * Removed only for `schemaKey` on tools outside `SCHEMA_KEY_ENUM_TOOLS`: the
 * 18-key enum. See `SCHEMA_KEY_ENUM_TOOLS` for which tools keep it and why.
 * Non-`schemaKey` enums (e.g. `start_intake.layer`) are always kept — they
 * are small and genuinely constrain model output.
 *
 * Kept everywhere: `type`, `pattern`, `minimum`, `maximum`, `required`,
 * `additionalProperties: false`.
 */
export function modelFacingParameters(
  entry: AgentToolContractEntry,
): ObjectArguments {
  const properties = Object.fromEntries(
    Object.entries(entry.parameters.properties).map((
      [propertyName, rule],
    ) => [propertyName, modelFacingRule(entry.name, propertyName, rule)]),
  )
  return {
    type: 'object',
    properties,
    required: entry.parameters.required,
    additionalProperties: false,
  }
}

function modelFacingRule(
  toolName: AgentToolName,
  propertyName: string,
  rule: ArgumentRule,
): ArgumentRule {
  const { minLength: _minLength, maxLength: _maxLength, ...rest } = rule
  const dropEnum = propertyName === 'schemaKey' &&
    rest.enum !== undefined &&
    !SCHEMA_KEY_ENUM_TOOLS.has(toolName)
  if (!dropEnum) return rest
  const { enum: _enum, ...withoutEnum } = rest
  return withoutEnum
}

/**
 * `AGENT_TOOL_CONTRACT`, projected through `modelFacingParameters`. With no
 * `names`, every tool is included, in contract order. With `names`, only
 * those tools are included — still in CONTRACT order (not `names` order),
 * because deterministic ordering is required for OpenAI prompt-cache
 * stability. An unknown name throws rather than being silently dropped.
 */
export function modelFacingContract(
  names?: readonly AgentToolName[],
): readonly AgentToolContractEntry[] {
  let wanted: ReadonlySet<AgentToolName> | null = null
  if (names !== undefined) {
    const known = new Set(AGENT_TOOL_CONTRACT.map((entry) => entry.name))
    for (const name of names) {
      if (!known.has(name)) {
        throw new Error(`modelFacingContract: unknown tool name "${name}"`)
      }
    }
    wanted = new Set(names)
  }
  return AGENT_TOOL_CONTRACT
    .filter((entry) => wanted === null || wanted.has(entry.name))
    .map((entry) => ({
      name: entry.name,
      description: entry.description,
      parameters: modelFacingParameters(entry),
    }))
}
