import { assert, assertEquals, assertThrows } from '@std/assert'

import type { AgentToolName } from './agent_protocol.ts'
import {
  AGENT_TOOL_CONTRACT,
  AGENT_TOOL_CONTRACT_VERSION,
  contractFingerprint,
  modelFacingContract,
  modelFacingParameters,
} from './agent_tool_contract.ts'
import { AGENT_TOOL_DEFINITIONS } from './agent_tools.ts'

const DRIFT = [
  'The model-facing tool contract moved.',
  'If you deliberately changed a tool name, description, parameter, required',
  'flag or enum, that is a business capability change: bump',
  'AGENT_TOOL_CONTRACT_VERSION in agent_tool_contract.ts and update this',
  'snapshot in the same commit.',
  'If you only changed storage — a renamed column, a reshaped or split table —',
  'revert it. The contract must not move for a storage change; fix the tool',
  'handler instead.',
].join(' ')

const STATION_SCHEMA_KEYS = [
  'chicks.pasgar',
  'egg.storage_environment',
  'egg.shell_temperature',
  'egg.upside_down',
  'egg.quality_uv',
  'egg.weights',
  'chicks.yfbm',
  'chicks.cvt',
  'chicks.postmortem',
  'chicks.culled_analysis',
  'chicks.weights',
  'hatch_analysis.fresh_breakout',
  'hatch_analysis.candled_breakout',
  'hatch_analysis.residue_breakout',
  'setters.environment',
  'setters.shell_temperature',
  'hatchers.environment',
  'hatchers.cvt',
]

interface ContractSnapshotEntry {
  name: string
  parameters: string[]
  required: string[]
  enums: Record<string, (string | number | boolean)[]>
}

const EXPECTED_CONTRACT: ContractSnapshotEntry[] = [
  {
    name: 'get_user_scope',
    parameters: [],
    required: [],
    enums: {},
  },
  {
    name: 'list_customers',
    parameters: [],
    required: [],
    enums: {},
  },
  {
    name: 'resolve_customer_flock',
    parameters: ['customerName', 'flockName'],
    required: ['customerName'],
    enums: {},
  },
  {
    name: 'get_customer_context',
    parameters: ['customerId'],
    required: ['customerId'],
    enums: {},
  },
  {
    name: 'list_customer_flocks',
    parameters: ['customerId', 'limit'],
    required: ['customerId'],
    enums: {},
  },
  {
    name: 'list_customer_hatcheries',
    parameters: ['customerId', 'limit'],
    required: ['customerId'],
    enums: {},
  },
  {
    name: 'list_customer_audits',
    parameters: ['customerId', 'flockId', 'limit'],
    required: ['customerId'],
    enums: {},
  },
  {
    name: 'select_audit_option',
    parameters: ['position'],
    required: ['position'],
    enums: {},
  },
  {
    name: 'get_audit_summary',
    parameters: [],
    required: [],
    enums: {},
  },
  {
    name: 'get_selected_audit_breakouts',
    parameters: [],
    required: [],
    enums: {},
  },
  {
    name: 'get_flock_context',
    parameters: ['flockId'],
    required: ['flockId'],
    enums: {},
  },
  {
    name: 'query_station_records',
    parameters: [
      'customerId',
      'flockId',
      'schemaKey',
      'schemaVersion',
      'fromDate',
      'toDate',
      'limit',
    ],
    required: [
      'customerId',
      'schemaKey',
      'schemaVersion',
      'fromDate',
      'toDate',
    ],
    enums: {
      schemaKey: STATION_SCHEMA_KEYS,
    },
  },
  {
    name: 'compare_station_metrics',
    parameters: [
      'customerId',
      'flockId',
      'schemaKey',
      'schemaVersion',
      'measureKey',
      'fromDate',
      'toDate',
    ],
    required: [
      'customerId',
      'schemaKey',
      'schemaVersion',
      'measureKey',
      'fromDate',
      'toDate',
    ],
    enums: {
      schemaKey: STATION_SCHEMA_KEYS,
    },
  },
  {
    name: 'get_record_provenance',
    parameters: ['schemaKey', 'schemaVersion', 'recordId'],
    required: ['schemaKey', 'schemaVersion', 'recordId'],
    enums: {
      schemaKey: STATION_SCHEMA_KEYS,
    },
  },
  {
    name: 'list_applicable_stations',
    parameters: ['customerId', 'flockId'],
    required: ['customerId', 'flockId'],
    enums: {},
  },
  {
    name: 'load_station_schema',
    parameters: ['schemaKey', 'schemaVersion'],
    required: ['schemaKey', 'schemaVersion'],
    enums: {
      schemaKey: STATION_SCHEMA_KEYS,
    },
  },
  {
    name: 'get_breed_benchmark',
    parameters: ['breed', 'ageWeek', 'metrics'],
    required: ['breed', 'ageWeek'],
    enums: {},
  },
  {
    name: 'get_egg_breakout_benchmark',
    parameters: ['ageWeek', 'metrics'],
    required: ['ageWeek'],
    enums: {},
  },
  {
    name: 'get_operational_standards',
    parameters: ['stationKey', 'sectorKey', 'hatcheryId'],
    required: [],
    enums: {},
  },
  {
    name: 'compare_selected_audit_to_benchmark',
    parameters: [],
    required: [],
    enums: {},
  },
  {
    name: 'propose_intake',
    parameters: ['customerId'],
    required: ['customerId'],
    enums: {},
  },
  {
    name: 'start_intake',
    parameters: [
      'pendingActionId',
      'schemaKey',
      'schemaVersion',
      'customerId',
      'flockId',
      'hatcheryId',
      'auditDate',
      'layer',
      'houseIdentity',
      'setterIdentity',
      'hatcherIdentity',
    ],
    required: [
      'pendingActionId',
      'schemaKey',
      'schemaVersion',
      'customerId',
      'flockId',
      'hatcheryId',
      'auditDate',
      'layer',
    ],
    enums: {
      schemaKey: STATION_SCHEMA_KEYS,
      layer: [
        'pool',
        'house',
        'setter',
        'hatcher',
        'setter_hatcher',
        'trolley',
        'tray',
      ],
    },
  },
  {
    name: 'record_station_values',
    parameters: ['intakeId', 'expectedRowVersion', 'values'],
    required: ['intakeId', 'expectedRowVersion', 'values'],
    enums: {},
  },
  {
    name: 'get_intake_status',
    parameters: ['intakeId'],
    required: ['intakeId'],
    enums: {},
  },
  {
    name: 'create_station_summary',
    parameters: ['intakeId', 'expectedRowVersion'],
    required: ['intakeId', 'expectedRowVersion'],
    enums: {},
  },
  {
    name: 'confirm_station_summary',
    parameters: ['intakeId', 'expectedRowVersion', 'summaryVersion'],
    required: ['intakeId', 'expectedRowVersion', 'summaryVersion'],
    enums: {},
  },
  {
    name: 'submit_station_for_review',
    parameters: ['intakeId', 'expectedRowVersion'],
    required: ['intakeId', 'expectedRowVersion'],
    enums: {},
  },
  {
    name: 'pause_intake',
    parameters: ['intakeId', 'expectedRowVersion'],
    required: ['intakeId', 'expectedRowVersion'],
    enums: {},
  },
  {
    name: 'resume_intake',
    parameters: ['intakeId', 'expectedRowVersion'],
    required: ['intakeId', 'expectedRowVersion'],
    enums: {},
  },
  {
    name: 'cancel_intake',
    parameters: ['intakeId', 'expectedRowVersion'],
    required: ['intakeId', 'expectedRowVersion'],
    enums: {},
  },
  {
    name: 'list_legacy_draft_questions',
    parameters: ['submissionId'],
    required: ['submissionId'],
    enums: {},
  },
  {
    name: 'answer_legacy_draft_question',
    parameters: ['submissionId', 'questionId', 'answer'],
    required: ['submissionId', 'questionId', 'answer'],
    enums: {},
  },
]

Deno.test('model-facing tool contract matches the pinned snapshot', () => {
  const actual = AGENT_TOOL_CONTRACT.map((tool) => ({
    name: tool.name as string,
    parameters: Object.keys(tool.parameters.properties),
    required: [...tool.parameters.required],
    enums: Object.fromEntries(
      Object.entries(tool.parameters.properties)
        .filter(([, rule]) => rule.enum !== undefined)
        .map(([key, rule]) => [key, [...(rule.enum ?? [])]]),
    ),
  }))
  assertEquals(actual, EXPECTED_CONTRACT, DRIFT)
})

Deno.test('contract fingerprint is pinned', () => {
  assertEquals(AGENT_TOOL_CONTRACT_VERSION, '1.3.0', DRIFT)
  assertEquals(contractFingerprint(), '77ee6867300c5277', DRIFT)
})

Deno.test('every contract parameter is a closed object schema', () => {
  for (const tool of AGENT_TOOL_CONTRACT) {
    assertEquals(tool.parameters.type, 'object', tool.name)
    assertEquals(tool.parameters.additionalProperties, false, tool.name)
    for (const required of tool.parameters.required) {
      assertEquals(
        required in tool.parameters.properties,
        true,
        `${tool.name} requires an undeclared parameter ${required}`,
      )
    }
  }
})

Deno.test('tool definitions are derived from the contract and stay flat', () => {
  assertEquals(
    AGENT_TOOL_DEFINITIONS.map((tool) => tool.name),
    AGENT_TOOL_CONTRACT.map((tool) => tool.name),
    DRIFT,
  )
  for (const [index, definition] of AGENT_TOOL_DEFINITIONS.entries()) {
    const contract = AGENT_TOOL_CONTRACT[index]
    assertEquals(definition.description, contract.description, DRIFT)
    assertEquals(definition.parameters, contract.parameters, DRIFT)
    assertEquals(
      Object.keys(definition).sort(),
      ['description', 'name', 'parameters', 'type'],
      'Tool definitions must stay FLAT — {type, name, description, parameters}. ' +
        'The nested Chat-Completions form {type, function:{...}} is not the ' +
        'Responses-API shape the provider adapters were verified against.',
    )
    assertEquals(definition.type, 'function')
    assertEquals(
      Object.keys(definition).includes('function'),
      false,
      'Tool definitions must not carry a nested `function` object.',
    )
  }
})

// The enum is kept wherever the model may have to NAME a station without a
// prior discovery turn. `query_station_records`/`compare_station_metrics` are
// called cold by the `inference-language` eval scenario, so they keep it.
// `get_record_provenance` is the only schemaKey tool that structurally cannot
// be called cold — it requires a `recordId`, which only arrives inside a
// `query_station_records` result, so the key is always already in hand.
const SCHEMA_KEY_TOOLS_KEEPING_ENUM: AgentToolName[] = [
  'load_station_schema',
  'start_intake',
  'query_station_records',
  'compare_station_metrics',
]
const SCHEMA_KEY_TOOLS_LOSING_ENUM: AgentToolName[] = [
  'get_record_provenance',
]

Deno.test('modelFacingContract() covers every tool, in contract order, as valid JSON Schema', () => {
  const projected = modelFacingContract()
  assertEquals(
    projected.map((tool) => tool.name),
    AGENT_TOOL_CONTRACT.map((tool) => tool.name),
    'modelFacingContract() must include every contract tool in contract order',
  )
  for (const [index, tool] of projected.entries()) {
    const original = AGENT_TOOL_CONTRACT[index]
    assertEquals(tool.name, original.name)
    assertEquals(tool.description, original.description)
    assertEquals(tool.parameters.type, 'object', tool.name)
    assertEquals(tool.parameters.additionalProperties, false, tool.name)
    assertEquals(
      tool.parameters.required,
      original.parameters.required,
      tool.name,
    )
    assertEquals(
      Object.keys(tool.parameters.properties),
      Object.keys(original.parameters.properties),
      tool.name,
    )
    for (const required of tool.parameters.required) {
      assertEquals(
        required in tool.parameters.properties,
        true,
        `${tool.name} requires an undeclared parameter ${required}`,
      )
    }
  }
})

Deno.test('modelFacingContract() never carries minLength or maxLength', () => {
  for (const tool of modelFacingContract()) {
    for (const [key, rule] of Object.entries(tool.parameters.properties)) {
      assertEquals(
        'minLength' in rule,
        false,
        `${tool.name}.${key} still has minLength`,
      )
      assertEquals(
        'maxLength' in rule,
        false,
        `${tool.name}.${key} still has maxLength`,
      )
    }
  }
})

Deno.test('modelFacingContract() keeps minimum, maximum and pattern where the contract has them', () => {
  const original = new Map(AGENT_TOOL_CONTRACT.map((tool) => [tool.name, tool]))
  for (const tool of modelFacingContract()) {
    const source = original.get(tool.name)!
    for (const [key, rule] of Object.entries(tool.parameters.properties)) {
      const sourceRule = source.parameters.properties[key]
      assertEquals(rule.minimum, sourceRule.minimum, `${tool.name}.${key}`)
      assertEquals(rule.maximum, sourceRule.maximum, `${tool.name}.${key}`)
      assertEquals(rule.pattern, sourceRule.pattern, `${tool.name}.${key}`)
      assertEquals(rule.type, sourceRule.type, `${tool.name}.${key}`)
    }
  }
})

Deno.test('modelFacingContract() keeps the full schemaKey enum on every tool that can be called cold', () => {
  const byName = new Map(modelFacingContract().map((tool) => [tool.name, tool]))
  for (const name of SCHEMA_KEY_TOOLS_KEEPING_ENUM) {
    const rule = byName.get(name)?.parameters.properties.schemaKey
    assertEquals(rule?.enum, STATION_SCHEMA_KEYS, name)
  }
  for (const name of SCHEMA_KEY_TOOLS_LOSING_ENUM) {
    const rule = byName.get(name)?.parameters.properties.schemaKey
    assertEquals('enum' in (rule ?? {}), false, name)
    // Everything else about the property must survive.
    assertEquals(rule?.type, 'string', name)
  }
})

Deno.test("modelFacingContract() keeps start_intake's layer enum — it is small and not schemaKey", () => {
  const startIntake = modelFacingContract().find((tool) =>
    tool.name === 'start_intake'
  )
  assertEquals(startIntake?.parameters.properties.layer.enum, [
    'pool',
    'house',
    'setter',
    'hatcher',
    'setter_hatcher',
    'trolley',
    'tray',
  ])
})

Deno.test('modelFacingContract(names) filters to the requested tools but preserves CONTRACT order', () => {
  const requested: AgentToolName[] = [
    'start_intake',
    'get_user_scope',
    'load_station_schema',
  ]
  const projected = modelFacingContract(requested)
  assertEquals(
    projected.map((tool) => tool.name),
    ['get_user_scope', 'load_station_schema', 'start_intake'],
    'filtered result must follow AGENT_TOOL_CONTRACT order, not the names[] order',
  )
})

Deno.test('modelFacingContract(names) throws on an unknown tool name', () => {
  assertThrows(
    () =>
      modelFacingContract(
        ['nope'] as unknown as readonly AgentToolName[],
      ),
    Error,
  )
})

Deno.test('modelFacingParameters() leaves AGENT_TOOL_CONTRACT itself untouched', () => {
  const before = JSON.stringify(AGENT_TOOL_CONTRACT)
  for (const tool of AGENT_TOOL_CONTRACT) {
    modelFacingParameters(tool)
  }
  const after = JSON.stringify(AGENT_TOOL_CONTRACT)
  assertEquals(
    after,
    before,
    'projecting must never mutate the source contract',
  )
  assertEquals(AGENT_TOOL_CONTRACT_VERSION, '1.3.0')
  assertEquals(contractFingerprint(), '77ee6867300c5277')
})

Deno.test('AGENT_TOOL_DEFINITIONS (the validation surface) is unaffected by the model-facing projection', () => {
  // This is the load-bearing guarantee behind the whole split: the object
  // `executeAgentTool` validates against still mirrors AGENT_TOOL_CONTRACT
  // exactly, byte for byte, regardless of what gets rendered to a model.
  for (const [index, definition] of AGENT_TOOL_DEFINITIONS.entries()) {
    assertEquals(definition.parameters, AGENT_TOOL_CONTRACT[index].parameters)
  }
  assert(
    JSON.stringify(AGENT_TOOL_DEFINITIONS.map((d) => d.parameters)).includes(
      '"minLength"',
    ),
    'validation definitions must still carry minLength',
  )
})
