// Scenario data + extra assertion helpers for `run_comparison.ts` -- the
// MODEL-VS-MODEL cost/quality comparison suite.
//
// This is a SEPARATE suite from `scenarios.ts` + `run_evals.ts` +
// `run_probe.ts` already in this directory. That harness already answers
// "is ONE specific model fit to be the default at all" for two named
// candidates; this suite answers a different question -- "of FIVE paid
// OpenRouter candidates that all advertise tool support, which is the
// cheapest one that still clears our reliability bar" -- by running the
// IDENTICAL scenario set against every candidate in `models.ts` and diffing
// the results. It reuses the real transport/tool-loop from `agent_client.ts`
// and the assertion primitives from `scenarios.ts` rather than reimplementing
// either.
//
// Every scenario still runs against the REAL model over the REAL OpenRouter
// `/v1/responses` shape, the REAL system prompt (`buildAgentInstructions`),
// and the REAL tool catalogue (`AGENT_MODEL_TOOL_DEFINITIONS`). Tool names,
// argument shapes, and stub result shapes below were taken from
// `agent_tool_contract.ts`, `agent_read_tools.ts`, `bmk_tools.ts`, and
// `agent_audit_tools.ts` after reading them -- see the per-constant comments
// below for which real function's return shape each stub mirrors. The two
// exceptions are `propose_intake` and `list_applicable_stations` in the
// `multiturn-data-entry-intent` scenario: `agent_intake_tools.ts` was not in
// this task's mandated reading list, so those two stub OUTPUTS are a
// plausible approximation rather than a verified shape. That scenario's
// assertions are deliberately shallow (tool-call routing only, via
// `toolCalled`/`toolNotCalled`/`argumentsValidForTool` -- the latter checks
// the CALL's arguments against the real `AGENT_TOOL_CONTRACT` schema, which
// is exact regardless of what a stub returns) so an inexact stub result
// cannot produce a false pass/fail on a claim this suite cannot verify.
//
// -----------------------------------------------------------------------
// Report vs benchmark caveat (see `scenarios.ts`'s own header for the full
// version): `REPORT_VS_BENCHMARK` in `agent_prompt.ts` is VOICE-ONLY --
// it is not part of `CHICKMARK_AGENT_POLICY`, the prompt `buildAgentInstructions`
// actually builds and this suite sends. Scenarios tagged with
// `REPORT_VS_BENCHMARK_CAVEAT` below are testing whether the GENERAL typed
// policy (`EVIDENCE_AND_SCOPE` + `BENCHMARK_DISCIPLINE`) is enough to keep a
// report request away from a benchmark tool, not compliance with a
// documented rule for this channel. A failure there is real signal about
// the model, but should not be read as "this model broke an explicit rule".
// -----------------------------------------------------------------------
//
// This file only defines DATA and pure assertion functions -- no network, no
// process I/O. `run_comparison.ts` is what actually talks to the wire.

import {
  containsArabic,
  type FunctionCallItem,
  type ToolStub,
  type TurnResult,
} from './agent_client.ts'
import {
  allArgumentsValid,
  argumentsValidForTool,
  type Assertion,
  type AssertionOutcome,
  DEFAULT_TOOL_STUBS,
  finalText,
  maxWords,
  mustMatchAny,
  mustNotMatch,
  noToolCall,
  repliedInArabic,
  toolCalled,
  toolCalledAny,
  toolCalledWithArgs,
  toolNotCalled,
} from './scenarios.ts'

export {
  allArgumentsValid,
  argumentsValidForTool,
  finalText,
  maxWords,
  mustMatchAny,
  mustNotMatch,
  noToolCall,
  repliedInArabic,
  toolCalled,
  toolCalledAny,
  toolCalledWithArgs,
  toolNotCalled,
}
export type { AssertionOutcome, FunctionCallItem, ToolStub, TurnResult }

const REPORT_VS_BENCHMARK_CAVEAT =
  'Tests whether the GENERAL typed policy (EVIDENCE_AND_SCOPE + BENCHMARK_DISCIPLINE) ' +
  'is sufficient without the voice-only REPORT_VS_BENCHMARK routing block -- see this ' +
  "file's header and scenarios.ts's. A failure here is genuine signal about the model, " +
  'not a violation of a documented rule for this (text) channel.'

const INTAKE_SHAPE_CAVEAT =
  "agent_intake_tools.ts was not in this task's mandated reading list, so the " +
  'propose_intake/list_applicable_stations STUB OUTPUTS here are a plausible ' +
  'approximation, not a verified shape. Assertions are deliberately limited to ' +
  'tool-call routing and argumentsValidForTool (checked against the real, exact ' +
  "AGENT_TOOL_CONTRACT schema regardless of stub content), never to the stub's own " +
  'field names.'

// ---------------------------------------------------------------------------
// Extra assertion helpers (on top of the ones imported from scenarios.ts:
// maxWords, mustMatchAny, mustNotMatch, toolCalled, toolCalledAny,
// toolNotCalled, noToolCall, repliedInArabic, toolCalledWithArgs,
// argumentsValidForTool, allArgumentsValid).
// ---------------------------------------------------------------------------

const QUESTION_MARK_PATTERN = /[?؟]/g
const PERCENT_FIGURE_PATTERN = /\d+(?:\.\d+)?\s*(?:%|٪)/g

export function questionMarkCount(text: string): number {
  return (text.match(QUESTION_MARK_PATTERN) ?? []).length
}

function percentFigureCount(text: string): number {
  return (text.match(PERCENT_FIGURE_PATTERN) ?? []).length
}

export function maxChars(n: number): Assertion {
  return (result) => {
    const text = finalText(result)
    return {
      pass: text.length <= n,
      label: `maxChars(${n})`,
      detail: `${text.length} chars: "${text}"`,
    }
  }
}

export function maxQuestionMarks(n: number): Assertion {
  return (result) => {
    const text = finalText(result)
    const count = questionMarkCount(text)
    return {
      pass: count <= n,
      label: `maxQuestionMarks(${n})`,
      detail: `${count} question mark(s): "${text}"`,
    }
  }
}

export function noClarifyingQuestion(): Assertion {
  return (result) => {
    const text = finalText(result)
    const count = questionMarkCount(text)
    return {
      pass: count === 0,
      label: 'noClarifyingQuestion',
      detail: count === 0
        ? 'no question asked'
        : `asked ${count} question(s) when everything needed was already given: "${text}"`,
    }
  }
}

export function asksAtLeastOneQuestion(): Assertion {
  return (result) => {
    const text = finalText(result)
    const count = questionMarkCount(text)
    return {
      pass: count >= 1,
      label: 'asksAtLeastOneQuestion',
      detail: count >= 1
        ? `asked ${count} question(s)`
        : `no clarifying question asked when the request was genuinely ambiguous: "${text}"`,
    }
  }
}

/** Structural proxy for "briefly identify the record, don't dump metrics
 * yet": at most `n` percentage figures appear in the reply. */
export function maxPercentFigures(n: number): Assertion {
  return (result) => {
    const text = finalText(result)
    const count = percentFigureCount(text)
    return {
      pass: count <= n,
      label: `maxPercentFigures(${n})`,
      detail: `${count} percent figure(s): "${text}"`,
    }
  }
}

/** Structural proxy for "actually answer with the figures, don't gate them
 * behind a disclosure question" -- the inverse check used on an EXPLICIT
 * full-detail request. */
export function minPercentFigures(n: number): Assertion {
  return (result) => {
    const text = finalText(result)
    const count = percentFigureCount(text)
    return {
      pass: count >= n,
      label: `minPercentFigures(${n})`,
      detail: `${count} percent figure(s): "${text}"`,
    }
  }
}

export function offersFollowUp(): Assertion {
  return (result) => {
    const text = finalText(result)
    const pass = questionMarkCount(text) >= 1
    return { pass, label: 'offersFollowUp', detail: `"${text}"` }
  }
}

/**
 * Every tool call made across the WHOLE turn has a name in `names`. Distinct
 * from `toolNotCalled(x)` (checks one specific tool was avoided): this
 * catches ANY unnecessary tool the scenario didn't anticipate, which is what
 * "not calling unnecessary tools" actually means in the open-ended case.
 */
export function onlyToolsAllowed(names: readonly string[]): Assertion {
  return (result) => {
    const unexpected = result.allToolCalls.filter((call) =>
      !names.includes(call.name)
    )
    return {
      pass: unexpected.length === 0,
      label: `onlyToolsAllowed(${names.join(' | ')})`,
      detail: unexpected.length === 0
        ? 'no unnecessary calls'
        : `unnecessary call(s): ${unexpected.map((c) => c.name).join(', ')}`,
    }
  }
}

// ---------------------------------------------------------------------------
// Dimensions
// ---------------------------------------------------------------------------

export type ComparisonDimension =
  | 'arabic_understanding'
  | 'tool_selection'
  | 'tool_arguments'
  | 'tool_result_reasoning'
  | 'progressive_disclosure'
  | 'brevity'
  | 'hallucination_grounding'
  | 'multi_turn'
  | 'degradation_under_load'

export const COMPARISON_DIMENSIONS: ReadonlyArray<
  { key: ComparisonDimension; title: string }
> = [
  {
    key: 'arabic_understanding',
    title:
      'Arabic / mixed-language understanding -- intent over keyword matching',
  },
  {
    key: 'tool_selection',
    title:
      'Tool selection -- right tool, no unnecessary calls, clarify only when necessary',
  },
  {
    key: 'tool_arguments',
    title:
      'Tool arguments -- real IDs, no transliteration poisoning, valid schemas',
  },
  {
    key: 'tool_result_reasoning',
    title:
      'Reasoning over tool results -- answer only what was asked, requested vs. context',
  },
  {
    key: 'progressive_disclosure',
    title: 'Progressive disclosure -- headline first, details on request',
  },
  { key: 'brevity', title: 'Brevity -- short, direct, at most one question' },
  {
    key: 'hallucination_grounding',
    title: "Hallucination / grounding -- never invent what a tool didn't say",
  },
  {
    key: 'multi_turn',
    title: 'Multi-turn realistic conversations (3-6 turns)',
  },
  {
    key: 'degradation_under_load',
    title:
      'Degradation under load -- long history, large payloads, deep tool disambiguation',
  },
]

export interface ComparisonTurnSpec {
  readonly label?: string
  readonly userText: string
  readonly toolStubs?: readonly ToolStub[]
  readonly assertions: readonly Assertion[]
}

export interface ComparisonScenario {
  readonly id: string
  readonly title: string
  readonly dimension: ComparisonDimension
  readonly turns: readonly ComparisonTurnSpec[]
  readonly note?: string
  /**
   * When present, any tool call in ANY turn of this scenario whose name
   * falls outside this set is counted by `run_comparison.ts` as an
   * "unnecessary tool call" in its per-model metrics -- independent of
   * whether a specific assertion already caught it. `DEFAULT_TOOL_STUBS`'s
   * two bootstrap tools (`get_user_scope`, `list_customers`) are always
   * implicitly allowed since a well-behaved model may reasonably reach for
   * them before anything else. Omit on scenarios with no meaningful "extra
   * tool" notion (already covered by `noToolCall()`).
   */
  readonly expectedTools?: readonly string[]
}

const ALWAYS_ALLOWED_TOOLS: readonly string[] = [
  'get_user_scope',
  'list_customers',
]

export function expectedToolsFor(
  scenario: ComparisonScenario,
): readonly string[] | undefined {
  return scenario.expectedTools === undefined
    ? undefined
    : [...scenario.expectedTools, ...ALWAYS_ALLOWED_TOOLS]
}

/** Scenario-specific stubs first (so they win the `matchStub` first-match
 * lookup in `agent_client.ts`), `DEFAULT_TOOL_STUBS` as a bootstrap fallback. */
function withDefaults(stubs: readonly ToolStub[]): readonly ToolStub[] {
  return [...stubs, ...DEFAULT_TOOL_STUBS]
}

// ---------------------------------------------------------------------------
// Tool-result stubs. Shapes taken from the real handlers after reading them:
//   - resolve_customer_flock / list_customer_flocks / get_flock_context /
//     list_customer_hatcheries / query_station_records / compare_station_metrics /
//     get_record_provenance -- `agent_read_tools.ts`
//   - get_breed_benchmark / get_egg_breakout_benchmark / get_operational_standards /
//     compare_selected_audit_to_benchmark -- `bmk_tools.ts`
//   - list_customer_audits / select_audit_option / get_audit_summary /
//     get_selected_audit_breakouts -- `agent_audit_tools.ts`
// ---------------------------------------------------------------------------

const RESOLVE_NILE_OK: ToolStub = {
  name: 'resolve_customer_flock',
  matches: (args) =>
    typeof args.customerName === 'string' &&
    args.customerName.includes('النيل'),
  output: {
    ok: true,
    code: 'ok',
    data: {
      status: 'resolved',
      customer: { id: 'cust_eval_nile', name: 'عميل النيل' },
      flock: null,
      matchedBy: { customer: 'exact', flock: null },
    },
  },
}

const RESOLVE_DELTA_OK: ToolStub = {
  name: 'resolve_customer_flock',
  matches: (args) =>
    typeof args.customerName === 'string' &&
    args.customerName.includes('الدلتا'),
  output: {
    ok: true,
    code: 'ok',
    data: {
      status: 'resolved',
      customer: { id: 'cust_eval_delta', name: 'عميل الدلتا' },
      flock: null,
      matchedBy: { customer: 'exact', flock: null },
    },
  },
}

const RESOLVE_MANSOURA_NOT_FOUND: ToolStub = {
  name: 'resolve_customer_flock',
  output: {
    ok: true,
    code: 'ok',
    data: {
      status: 'customer_not_found',
      customer: null,
      flock: null,
      candidates: [
        { id: 'cust_eval_nile', name: 'عميل النيل' },
        { id: 'cust_eval_delta', name: 'عميل الدلتا' },
      ],
      truncated: false,
    },
  },
}

const RESOLVE_AMBIGUOUS_HANI: ToolStub = {
  name: 'resolve_customer_flock',
  output: {
    ok: true,
    code: 'ok',
    data: {
      status: 'ambiguous_customer',
      customer: null,
      flock: null,
      matchedBy: { customer: 'exact', flock: null },
      candidates: [
        {
          customer: { id: 'cust_eval_hani1', name: 'هاني' },
          flocks: [{ id: 'flock_h1', name: 'قطيع 1' }],
          truncated: false,
        },
        {
          customer: { id: 'cust_eval_hani2', name: 'هانئ' },
          flocks: [{ id: 'flock_h2', name: 'قطيع 1' }],
          truncated: false,
        },
      ],
    },
  },
}

const LIST_NILE_FLOCKS: ToolStub = {
  name: 'list_customer_flocks',
  matches: (args) => args.customerId === 'cust_eval_nile',
  output: {
    ok: true,
    code: 'ok',
    data: {
      customerId: 'cust_eval_nile',
      flocks: [
        {
          id: 'flock_1',
          name: 'قطيع 1',
          status: 'active',
          breed: 'Hubbard',
          entryDate: '2026-05-01',
          sectorKey: 'breeder',
        },
        {
          id: 'flock_2',
          name: 'قطيع 2',
          status: 'active',
          breed: 'Ross 308',
          entryDate: '2026-02-01',
          sectorKey: 'breeder',
        },
        {
          id: 'flock_3',
          name: 'قطيع 3',
          status: 'active',
          breed: 'Ross 308',
          entryDate: '2025-10-01',
          sectorKey: 'breeder',
        },
      ],
    },
  },
}

const LIST_DELTA_FLOCKS: ToolStub = {
  name: 'list_customer_flocks',
  matches: (args) => args.customerId === 'cust_eval_delta',
  output: {
    ok: true,
    code: 'ok',
    data: {
      customerId: 'cust_eval_delta',
      flocks: [
        {
          id: 'flock_d1',
          name: 'قطيع دلتا 1',
          status: 'active',
          breed: 'Cobb 500',
          entryDate: '2026-07-01',
          sectorKey: 'breeder',
        },
      ],
    },
  },
}

// flock_1 is youngest (~15 weeks as of 2026-08-19), flock_3 is oldest (~46).
const GET_FLOCK_1_CONTEXT: ToolStub = {
  name: 'get_flock_context',
  matches: (args) => args.flockId === 'flock_1',
  output: {
    ok: true,
    code: 'ok',
    data: {
      id: 'flock_1',
      name: 'قطيع 1',
      status: 'active',
      breed: 'Hubbard',
      entryDate: '2026-05-01',
      sectorKey: 'breeder',
      customerId: 'cust_eval_nile',
      ageDays: 110,
      ageWeeks: 15,
      ageAsOfDate: '2026-08-19',
    },
  },
}

const GET_FLOCK_3_CONTEXT: ToolStub = {
  name: 'get_flock_context',
  matches: (args) => args.flockId === 'flock_3',
  output: {
    ok: true,
    code: 'ok',
    data: {
      id: 'flock_3',
      name: 'قطيع 3',
      status: 'active',
      breed: 'Ross 308',
      entryDate: '2025-10-01',
      sectorKey: 'breeder',
      customerId: 'cust_eval_nile',
      ageDays: 322,
      ageWeeks: 46,
      ageAsOfDate: '2026-08-19',
    },
  },
}

function breedBenchmarkRow(
  breed: string,
  ageWeek: number,
  values: {
    hatchabilityPct: number
    fertilityPct: number
    hofPct: number
    productionPct: number
    eggWeightG: number
    chickWeightG: number
  },
): Record<string, unknown> {
  return { breed, ageWeek, ...values }
}

const HUBBARD_WK40_FULL: ToolStub = {
  name: 'get_breed_benchmark',
  matches: (args) => args.breed === 'Hubbard' && args.ageWeek === 40,
  output: {
    ok: true,
    code: 'ok',
    data: breedBenchmarkRow('Hubbard', 40, {
      hatchabilityPct: 90.2,
      fertilityPct: 96.5,
      hofPct: 93.47,
      productionPct: 80,
      eggWeightG: 65.3,
      chickWeightG: 46,
    }),
  },
}

const ROSS_WK35_FULL: ToolStub = {
  name: 'get_breed_benchmark',
  matches: (args) => args.breed === 'Ross 308' && args.ageWeek === 35,
  output: {
    ok: true,
    code: 'ok',
    data: breedBenchmarkRow('Ross 308', 35, {
      hatchabilityPct: 92.4,
      fertilityPct: 90.1,
      hofPct: 95.0,
      productionPct: 78.5,
      eggWeightG: 64.1,
      chickWeightG: 45.2,
    }),
  },
}

const ROSS_WK40_FULL: ToolStub = {
  name: 'get_breed_benchmark',
  matches: (args) => args.breed === 'Ross 308' && args.ageWeek === 40,
  output: {
    ok: true,
    code: 'ok',
    data: breedBenchmarkRow('Ross 308', 40, {
      hatchabilityPct: 91.0,
      fertilityPct: 95.2,
      hofPct: 95.6,
      productionPct: 79.0,
      eggWeightG: 64.8,
      chickWeightG: 45.8,
    }),
  },
}

const ROSS_WK46_FULL: ToolStub = {
  name: 'get_breed_benchmark',
  matches: (args) => args.breed === 'Ross 308' && args.ageWeek === 46,
  output: {
    ok: true,
    code: 'ok',
    data: breedBenchmarkRow('Ross 308', 46, {
      hatchabilityPct: 89.5,
      fertilityPct: 93.8,
      hofPct: 95.4,
      productionPct: 76.0,
      eggWeightG: 66.0,
      chickWeightG: 47.5,
    }),
  },
}

const COBB_WK28_FULL: ToolStub = {
  name: 'get_breed_benchmark',
  matches: (args) => args.breed === 'Cobb 500' && args.ageWeek === 28,
  output: {
    ok: true,
    code: 'ok',
    data: breedBenchmarkRow('Cobb 500', 28, {
      hatchabilityPct: 87.5,
      fertilityPct: 92.5,
      hofPct: 94.6,
      productionPct: 73.0,
      eggWeightG: 61.5,
      chickWeightG: 43.8,
    }),
  },
}

const COBB_WK30_FULL: ToolStub = {
  name: 'get_breed_benchmark',
  matches: (args) => args.breed === 'Cobb 500' && args.ageWeek === 30,
  output: {
    ok: true,
    code: 'ok',
    data: breedBenchmarkRow('Cobb 500', 30, {
      hatchabilityPct: 88.0,
      fertilityPct: 93.0,
      hofPct: 94.6,
      productionPct: 75.0,
      eggWeightG: 62.0,
      chickWeightG: 44.0,
    }),
  },
}

const ROSS_WK35_REQUESTED_HATCHABILITY: ToolStub = {
  name: 'get_breed_benchmark',
  matches: (args) =>
    args.breed === 'Ross 308' && args.ageWeek === 35 &&
    typeof args.metrics === 'string',
  output: {
    ok: true,
    code: 'ok',
    data: {
      breed: 'Ross 308',
      ageWeek: 35,
      requested: [{ metric: 'hatchability', value: 92.4, unit: '%' }],
      context: breedBenchmarkRow('Ross 308', 35, {
        hatchabilityPct: 92.4,
        fertilityPct: 90.1,
        hofPct: 95.0,
        productionPct: 78.5,
        eggWeightG: 64.1,
        chickWeightG: 45.2,
      }),
    },
  },
}

const ROSS_WK90_OUT_OF_RANGE: ToolStub = {
  name: 'get_breed_benchmark',
  output: {
    ok: true,
    code: 'ok',
    data: {
      status: 'week_out_of_range',
      breed: 'Ross 308',
      coveredWeeks: { min: 18, max: 65 },
    },
  },
}

function breakoutRow(
  ageWeek: number,
  values: Record<string, number>,
): Record<string, unknown> {
  return { ageWeek, ...values }
}

const BREAKOUT_WK40_VALUES = {
  infertilePct: 6.2,
  early24hPct: 1.4,
  early48hPct: 1.1,
  bloodRingPct: 0.8,
  blackEyePct: 0.6,
  earlyDeadPct: 2.3,
  midDeadPct: 1.2,
  lateDeadPct: 3.1,
  externalPipPct: 1.7,
  crackedPct: 0.9,
  contamPct: 0.5,
}

const BREAKOUT_WK40_REQUESTED_INFERTILE: ToolStub = {
  name: 'get_egg_breakout_benchmark',
  matches: (args) => args.ageWeek === 40 && typeof args.metrics === 'string',
  output: {
    ok: true,
    code: 'ok',
    data: {
      ageWeek: 40,
      requested: [{ metric: 'infertile', value: 6.2, unit: '%' }],
      context: breakoutRow(40, BREAKOUT_WK40_VALUES),
    },
  },
}

const BREAKOUT_WK40_FULL: ToolStub = {
  name: 'get_egg_breakout_benchmark',
  matches: (args) => args.ageWeek === 40 && args.metrics === undefined,
  output: { ok: true, code: 'ok', data: breakoutRow(40, BREAKOUT_WK40_VALUES) },
}

// list_customer_audits / select_audit_option / get_selected_audit_breakouts /
// compare_selected_audit_to_benchmark -- shapes from `agent_audit_tools.ts`
// (`publicAuditOption`, `auditSummary`, `publicBreakoutRow`, `auditBenchmark`,
// `compareSelectedAuditToBenchmark`) and `bmk_tools.ts` (`comparison`).

const NILE_AUDIT_1_OPTION = {
  id: 'audit_1',
  date: '2026-08-10',
  status: 'approved',
  customerName: 'عميل النيل',
  flockName: 'قطيع 3',
  hatcheryName: 'المفرخ الرئيسي',
  selectedStationKeys: ['hatchers'],
  stationsCompleted: ['hatchers'],
  createdAt: '2026-08-10T09:00:00Z',
  completedAt: '2026-08-10T11:00:00Z',
}

const LIST_NILE_AUDITS_ONE: ToolStub = {
  name: 'list_customer_audits',
  matches: (args) => args.customerId === 'cust_eval_nile',
  output: {
    ok: true,
    code: 'ok',
    data: {
      customerId: 'cust_eval_nile',
      flockId: null,
      audits: [NILE_AUDIT_1_OPTION],
      truncated: false,
    },
  },
}

const LIST_DELTA_AUDITS_EMPTY: ToolStub = {
  name: 'list_customer_audits',
  matches: (args) => args.customerId === 'cust_eval_delta',
  output: {
    ok: true,
    code: 'ok',
    data: {
      customerId: 'cust_eval_delta',
      flockId: null,
      audits: [],
      truncated: false,
    },
  },
}

const SELECT_AUDIT_1_SUMMARY: ToolStub = {
  name: 'select_audit_option',
  output: {
    ok: true,
    code: 'ok',
    data: {
      ...NILE_AUDIT_1_OPTION,
      customerId: 'cust_eval_nile',
      flockId: 'flock_3',
      hatcheryId: 'hatchery_main',
      breed: 'Ross 308',
      flockAgeWeeks: 46,
      findings: null,
      scorecard: null,
      notes: null,
      benchmark: {
        status: 'ok',
        breed: 'Ross 308',
        ageWeek: 46,
        breedStandard: breedBenchmarkRow('Ross 308', 46, {
          hatchabilityPct: 89.5,
          fertilityPct: 93.8,
          hofPct: 95.4,
          productionPct: 76.0,
          eggWeightG: 66.0,
          chickWeightG: 47.5,
        }),
        breakoutStandard: breakoutRow(46, {
          infertilePct: 6.5,
          early24hPct: 1.5,
          early48hPct: 1.2,
          bloodRingPct: 0.9,
          blackEyePct: 0.6,
          earlyDeadPct: 2.4,
          midDeadPct: 1.2,
          lateDeadPct: 3.2,
          externalPipPct: 1.8,
          crackedPct: 1.0,
          contamPct: 0.6,
        }),
      },
    },
  },
}

const GET_SELECTED_AUDIT_BREAKOUTS: ToolStub = {
  name: 'get_selected_audit_breakouts',
  output: {
    ok: true,
    code: 'ok',
    data: {
      audit: NILE_AUDIT_1_OPTION,
      breakouts: [
        {
          breakoutType: 'fresh',
          date: '2026-08-10',
          hatcher: 'H1',
          infertileCount: 6,
          infertilePct: 6.0,
          early24hPct: 1.3,
          bloodRingPct: 0.7,
        },
      ],
      truncated: false,
      benchmark: {
        status: 'ok',
        breed: 'Ross 308',
        ageWeek: 46,
        breedStandard: breedBenchmarkRow('Ross 308', 46, {
          hatchabilityPct: 89.5,
          fertilityPct: 93.8,
          hofPct: 95.4,
          productionPct: 76.0,
          eggWeightG: 66.0,
          chickWeightG: 47.5,
        }),
        breakoutStandard: breakoutRow(46, {
          infertilePct: 6.5,
          early24hPct: 1.5,
          early48hPct: 1.2,
          bloodRingPct: 0.9,
          blackEyePct: 0.6,
          earlyDeadPct: 2.4,
          midDeadPct: 1.2,
          lateDeadPct: 3.2,
          externalPipPct: 1.8,
          crackedPct: 1.0,
          contamPct: 0.6,
        }),
      },
    },
  },
}

const COMPARE_SELECTED_AUDIT_TO_BENCHMARK: ToolStub = {
  name: 'compare_selected_audit_to_benchmark',
  output: {
    ok: true,
    code: 'ok',
    data: {
      auditId: 'audit_1',
      breed: 'Ross 308',
      ageWeek: 46,
      breakoutBenchmarkAvailable: true,
      comparisons: [
        {
          metricKey: 'hatchabilityPct',
          label: 'Hatchability',
          unit: '%',
          actual: 87.0,
          standard: 89.5,
          observedRows: 5,
          delta: -2.5,
        },
        {
          metricKey: 'infertilePct',
          label: 'Infertile',
          unit: '%',
          actual: 6.0,
          standard: 6.5,
          observedRows: 5,
          delta: -0.5,
        },
      ],
    },
  },
}

// query_station_records / compare_station_metrics / get_record_provenance --
// shapes from `agent_read_tools.ts`. `chicks.pasgar` / `setters.environment`
// schema keys and field names from `_shared/station_registry.generated.ts`.

function pasgarRecord(
  index: number,
  date: string,
): Record<string, unknown> {
  return {
    id: `rec_pasgar_${index}`,
    customerId: 'cust_eval_nile',
    flockId: 'flock_3',
    hatcheryId: 'hatchery_main',
    date,
    pasgarSampleSize: 100,
    pasgarFinalScore: 80 + (index % 6),
  }
}

const LARGE_PASGAR_RECORD_SET: readonly Record<string, unknown>[] = Array
  .from(
    { length: 42 },
    (_, index) =>
      pasgarRecord(
        index + 1,
        `2026-${String(1 + (index % 8)).padStart(2, '0')}-15`,
      ),
  )

const QUERY_STATION_RECORDS_PASGAR_LARGE: ToolStub = {
  name: 'query_station_records',
  matches: (args) => args.schemaKey === 'chicks.pasgar',
  output: {
    ok: true,
    code: 'ok',
    data: {
      schemaKey: 'chicks.pasgar',
      schemaVersion: 1,
      sourceQueryAt: '2026-08-19T12:00:00Z',
      truncated: false,
      records: LARGE_PASGAR_RECORD_SET,
    },
  },
}

const QUERY_STATION_RECORDS_SETTERS_ENV: ToolStub = {
  name: 'query_station_records',
  matches: (args) => args.schemaKey === 'setters.environment',
  output: {
    ok: true,
    code: 'ok',
    data: {
      schemaKey: 'setters.environment',
      schemaVersion: 1,
      sourceQueryAt: '2026-08-19T12:00:00Z',
      truncated: false,
      records: [
        {
          id: 'rec_1',
          customerId: 'cust_eval_nile',
          flockId: 'flock_3',
          hatcheryId: 'hatchery_main',
          date: '2026-07-15',
          setter: 'S1',
          setpointF: 99.5,
          actualF: 99.4,
          setpointRh: 55,
          actualRh: 54,
          turningAngle: 45,
          co2Ppm: 3200,
        },
        {
          id: 'rec_2',
          customerId: 'cust_eval_nile',
          flockId: 'flock_3',
          hatcheryId: 'hatchery_main',
          date: '2026-07-16',
          setter: 'S1',
          setpointF: 99.5,
          actualF: 99.6,
          setpointRh: 55,
          actualRh: 56,
          turningAngle: 45,
          co2Ppm: 3300,
        },
      ],
    },
  },
}

const COMPARE_STATION_METRICS_PASGAR: ToolStub = {
  name: 'compare_station_metrics',
  output: {
    ok: true,
    code: 'ok',
    data: {
      schemaKey: 'chicks.pasgar',
      schemaVersion: 1,
      measureKey: 'pasgarFinalScore',
      aggregation: 'sample_weighted_mean',
      value: 82.4,
      observedRows: 42,
      sourceQueryAt: '2026-08-19T12:00:00Z',
    },
  },
}

const GET_RECORD_PROVENANCE_REC1: ToolStub = {
  name: 'get_record_provenance',
  matches: (args) => args.recordId === 'rec_1',
  output: {
    ok: true,
    code: 'ok',
    data: {
      customerId: 'cust_eval_nile',
      flockId: 'flock_3',
      schemaKey: 'setters.environment',
      schemaVersion: 1,
      recordId: 'rec_1',
      recordDate: '2026-07-15',
      fetchedAt: '2026-08-19T12:00:00Z',
      freshness: 'stale',
    },
  },
}

// propose_intake / list_applicable_stations -- see `INTAKE_SHAPE_CAVEAT`
// above. Only used for tool-call routing, never for output-shape assertions.
const PROPOSE_INTAKE_NILE: ToolStub = {
  name: 'propose_intake',
  output: {
    ok: true,
    code: 'ok',
    data: { status: 'proposed', pendingActionId: 'pending_1' },
  },
}

const LIST_APPLICABLE_STATIONS_NILE: ToolStub = {
  name: 'list_applicable_stations',
  output: {
    ok: true,
    code: 'ok',
    data: {
      customerId: 'cust_eval_nile',
      flockId: 'flock_3',
      modules: [
        {
          schemaKey: 'hatchers.environment',
          names: {
            ar: 'المفرخ — البيئة والإعدادات',
            en: 'Hatcher — Environment',
          },
        },
        {
          schemaKey: 'hatch_analysis.fresh_breakout',
          names: {
            ar: 'تحليل الفقس — فحص طازج',
            en: 'Hatch Analysis — Fresh Breakout',
          },
        },
      ],
    },
  },
}

const LOAD_HATCHERS_ENV_SCHEMA: ToolStub = {
  name: 'load_station_schema',
  matches: (args) => args.schemaKey === 'hatchers.environment',
  output: {
    ok: true,
    code: 'ok',
    data: { schemaKey: 'hatchers.environment', schemaVersion: 1, fields: [] },
  },
}

// ---------------------------------------------------------------------------
// Scenarios
// ---------------------------------------------------------------------------

export const COMPARISON_SCENARIOS: readonly ComparisonScenario[] = [
  // =====================================================================
  // 1. Arabic understanding (4 scenarios)
  // =====================================================================
  {
    id: 'cmp-arabic-standard-despite-recorded-sounding-verb',
    title:
      '"المفروض" (supposed to be) signals a STANDARD question even though ' +
      'the sentence is otherwise about what a value "should" come out as',
    dimension: 'arabic_understanding',
    expectedTools: ['get_breed_benchmark'],
    turns: [{
      userText: 'الفقس المفروض يبقى كام لسلالة كوب 500 في الأسبوع 30؟',
      toolStubs: withDefaults([COBB_WK30_FULL]),
      assertions: [
        toolCalled('get_breed_benchmark'),
        toolNotCalled('resolve_customer_flock'),
        argumentsValidForTool('get_breed_benchmark'),
        mustMatchAny([/88|٨٨/]),
      ],
    }],
  },
  {
    id: 'cmp-arabic-report-despite-age-given',
    title:
      '"اللي طلع عندنا" (what came out for us) signals a RECORDED result ' +
      'even though a customer and an age week are both given, the same ' +
      'wording a standard question could otherwise use',
    dimension: 'arabic_understanding',
    note: REPORT_VS_BENCHMARK_CAVEAT,
    expectedTools: ['resolve_customer_flock', 'list_customer_audits'],
    turns: [{
      userText: 'اللي طلع عندنا لقطيع عميل النيل في الأسبوع 40 كام؟',
      toolStubs: withDefaults([RESOLVE_NILE_OK, LIST_NILE_AUDITS_ONE]),
      assertions: [
        toolNotCalled('get_breed_benchmark'),
        toolNotCalled('get_egg_breakout_benchmark'),
      ],
    }],
  },
  {
    id: 'cmp-arabic-mixed-technical-terms',
    title:
      'A sentence mixing Arabic and English hatchery terms the way staff ' +
      'actually type resolves the correct tool and arguments',
    dimension: 'arabic_understanding',
    expectedTools: ['get_breed_benchmark'],
    turns: [{
      userText: 'عايز أعرف الـ fertility بتاعت الـ Ross 308 في week 35',
      toolStubs: withDefaults([ROSS_WK35_FULL]),
      assertions: [
        toolCalled('get_breed_benchmark'),
        toolCalledWithArgs(
          'get_breed_benchmark',
          (args) => args.breed === 'Ross 308' && args.ageWeek === 35,
          'breed=Ross 308 ageWeek=35 parsed out of the mixed-language sentence',
        ),
        argumentsValidForTool('get_breed_benchmark'),
        mustMatchAny([/90\.1|90,1|٩٠\.١/]),
      ],
    }],
  },
  {
    id: 'cmp-arabic-colloquial-customer-reference',
    title:
      'A colloquial indirect reference ("الراجل بتاع...") still resolves ' +
      'the named customer, not a literal keyword match',
    dimension: 'arabic_understanding',
    expectedTools: ['resolve_customer_flock', 'list_customer_flocks'],
    turns: [{
      userText: 'الراجل بتاع عميل النيل ده عنده كام قطيع؟',
      toolStubs: withDefaults([RESOLVE_NILE_OK, LIST_NILE_FLOCKS]),
      assertions: [
        toolCalledAny(['resolve_customer_flock', 'list_customer_flocks']),
        repliedInArabic(),
        mustMatchAny([/3|تلات(?:ة)?|ثلاث(?:ة)?/]),
      ],
    }],
  },

  // =====================================================================
  // 2. Tool selection (5 scenarios)
  // =====================================================================
  {
    id: 'cmp-toolsel-report-not-benchmark',
    title:
      'Explicit report wording with a customer named never resolves to a ' +
      'benchmark tool',
    dimension: 'tool_selection',
    note: REPORT_VS_BENCHMARK_CAVEAT,
    expectedTools: ['resolve_customer_flock', 'list_customer_audits'],
    turns: [{
      userText: 'إيه آخر تقرير breakout مسجل عندنا لعميل النيل؟',
      toolStubs: withDefaults([RESOLVE_NILE_OK, LIST_NILE_AUDITS_ONE]),
      assertions: [
        toolNotCalled('get_breed_benchmark'),
        toolNotCalled('get_egg_breakout_benchmark'),
      ],
    }],
  },
  {
    id: 'cmp-toolsel-standard-not-report',
    title:
      'A published-standard question calls the benchmark tool, not audit or ' +
      'resolution tools',
    dimension: 'tool_selection',
    expectedTools: ['get_breed_benchmark'],
    turns: [{
      userText: 'نسبة الإنتاج المفروضة لسلالة هبرد في الأسبوع 40 هي كام؟',
      toolStubs: withDefaults([HUBBARD_WK40_FULL]),
      assertions: [
        toolCalled('get_breed_benchmark'),
        toolNotCalled('list_customer_audits'),
        toolNotCalled('resolve_customer_flock'),
      ],
    }],
  },
  {
    id: 'cmp-toolsel-no-unnecessary-tool-general-knowledge',
    title:
      'A general poultry-knowledge question (no records involved) gets no ' +
      'tool call at all',
    dimension: 'tool_selection',
    turns: [{
      userText: 'ليه بنعمل candling للبيض قبل نقله للحضانة؟ إيه فايدته أصلاً؟',
      assertions: [noToolCall(), repliedInArabic()],
    }],
  },
  {
    id: 'cmp-toolsel-no-clarify-when-fully-determined',
    title: 'Breed and age were both given -- the tool is called directly, no ' +
      'clarifying question is asked',
    dimension: 'tool_selection',
    expectedTools: ['get_breed_benchmark'],
    turns: [{
      userText: 'الفقس لسلالة كوب 500 في الأسبوع 30 كام؟',
      toolStubs: withDefaults([COBB_WK30_FULL]),
      assertions: [toolCalled('get_breed_benchmark'), noClarifyingQuestion()],
    }],
  },
  {
    id: 'cmp-toolsel-clarify-when-genuinely-ambiguous',
    title:
      'A customer name that matches two different records IS a case where ' +
      'asking is correct -- failing to ask here is also a failure',
    dimension: 'tool_selection',
    expectedTools: ['resolve_customer_flock'],
    turns: [{
      userText: 'عميل هاني عنده كام قطيع؟',
      toolStubs: withDefaults([RESOLVE_AMBIGUOUS_HANI]),
      assertions: [
        toolCalled('resolve_customer_flock'),
        asksAtLeastOneQuestion(),
      ],
    }],
  },

  // =====================================================================
  // 3. Tool arguments (5 scenarios)
  // =====================================================================
  {
    id: 'cmp-args-no-invented-id',
    title:
      'resolve_customer_flock is called with the plain name the user typed, ' +
      'never a fabricated ID-shaped string',
    dimension: 'tool_arguments',
    expectedTools: ['resolve_customer_flock'],
    turns: [{
      userText: 'عميل الدلتا عنده كام قطيع؟',
      toolStubs: withDefaults([RESOLVE_DELTA_OK]),
      assertions: [
        toolCalledWithArgs(
          'resolve_customer_flock',
          (args) =>
            typeof args.customerName === 'string' &&
            !/^cust_|^flock_/.test(args.customerName),
          'customerName is the plain typed name, not an invented cust_/flock_-shaped id',
        ),
        argumentsValidForTool('resolve_customer_flock'),
      ],
    }],
  },
  {
    id: 'cmp-args-no-transliteration-poisoning',
    title: 'Once resolved, the follow-up list_customer_flocks call uses the ' +
      'REAL id resolve_customer_flock returned, never the Arabic display name',
    dimension: 'tool_arguments',
    expectedTools: ['resolve_customer_flock', 'list_customer_flocks'],
    turns: [{
      userText: 'عميل النيل عنده كام قطيع؟',
      toolStubs: withDefaults([RESOLVE_NILE_OK, LIST_NILE_FLOCKS]),
      assertions: [
        toolCalledWithArgs(
          'list_customer_flocks',
          (args) => args.customerId === 'cust_eval_nile',
          'customerId is the resolved id "cust_eval_nile", never the Arabic name string "عميل النيل"',
        ),
        argumentsValidForTool('list_customer_flocks'),
      ],
    }],
  },
  {
    id: 'cmp-args-breed-transliteration',
    title:
      'An informal Arabic breed nickname ("كاب") is transliterated to the ' +
      'Latin breed name before the tool call',
    dimension: 'tool_arguments',
    expectedTools: ['get_breed_benchmark'],
    turns: [{
      userText: 'الفقس لسلالة كاب 500 في الأسبوع 28 كام؟',
      toolStubs: withDefaults([COBB_WK28_FULL]),
      assertions: [
        argumentsValidForTool('get_breed_benchmark'),
        toolCalledWithArgs(
          'get_breed_benchmark',
          (args) =>
            typeof args.breed === 'string' && !containsArabic(args.breed),
          'breed argument is Latin-script, not the Arabic "كاب" the user typed',
        ),
        toolCalledWithArgs(
          'get_breed_benchmark',
          (args) => args.ageWeek === 28,
          'ageWeek=28 as an actual integer',
        ),
      ],
    }],
  },
  {
    id: 'cmp-args-station-query-schema-valid',
    title:
      'A station-records query with an explicit date range produces a fully ' +
      'schema-valid call and calls no unnecessary tool',
    dimension: 'tool_arguments',
    expectedTools: ['resolve_customer_flock', 'query_station_records'],
    turns: [{
      userText:
        'وريني سجلات إعدادات المفرخ لعميل النيل من 2026-06-01 لحد 2026-07-01',
      toolStubs: withDefaults([
        RESOLVE_NILE_OK,
        QUERY_STATION_RECORDS_SETTERS_ENV,
      ]),
      assertions: [
        toolCalled('query_station_records'),
        argumentsValidForTool('query_station_records'),
        onlyToolsAllowed([
          'resolve_customer_flock',
          'query_station_records',
          'get_user_scope',
          'list_customers',
          'list_customer_flocks',
        ]),
      ],
    }],
  },
  {
    id: 'cmp-args-metrics-scoped-not-full-dump',
    title:
      'A single named metric is passed as the metrics argument, not omitted ' +
      'into a full-row request',
    dimension: 'tool_arguments',
    expectedTools: ['get_breed_benchmark'],
    turns: [{
      userText: 'نسبة الفقس بس لسلالة روس 308 في الأسبوع 35 كام؟',
      toolStubs: withDefaults([ROSS_WK35_REQUESTED_HATCHABILITY]),
      assertions: [
        argumentsValidForTool('get_breed_benchmark'),
        toolCalledWithArgs(
          'get_breed_benchmark',
          (args) =>
            typeof args.metrics === 'string' &&
            args.metrics.toLowerCase().includes('hatchability'),
          'metrics scoped to "hatchability" only, not omitted',
        ),
      ],
    }],
  },

  // =====================================================================
  // 4. Tool-result reasoning (4 scenarios)
  // =====================================================================
  {
    id: 'cmp-reasoning-single-metric-among-many',
    title:
      'The tool result carries six metrics; the user asked for one -- only ' +
      'that one is spoken',
    dimension: 'tool_result_reasoning',
    turns: [{
      userText: 'إنتاج هبرد في الأسبوع 40 كام؟',
      toolStubs: withDefaults([HUBBARD_WK40_FULL]),
      assertions: [
        mustMatchAny([/80|٨٠/]),
        mustNotMatch([/96\.5|93\.47|90\.2/]),
      ],
    }],
  },
  {
    id: 'cmp-reasoning-requested-vs-context',
    title:
      'The tool result has a "requested" entry AND a "context" object with ' +
      'ten more metrics -- only the requested one is spoken',
    dimension: 'tool_result_reasoning',
    turns: [{
      userText: 'نسبة الـ infertile بس في الأسبوع 40 كام؟',
      toolStubs: withDefaults([BREAKOUT_WK40_REQUESTED_INFERTILE]),
      assertions: [
        mustMatchAny([/6\.2|6,2|٦\.٢/]),
        mustNotMatch([/1\.4|1\.1|0\.8|0\.6|2\.3/]),
      ],
    }],
  },
  {
    id: 'cmp-reasoning-latest-report-identifies-record-not-numbers',
    title:
      'The user only asked WHICH report is latest -- the answer identifies ' +
      'it (date/flock), it does not need to already contain metric figures',
    dimension: 'tool_result_reasoning',
    turns: [{
      userText: 'إيه آخر تقرير عندنا لعميل النيل؟',
      toolStubs: withDefaults([RESOLVE_NILE_OK, LIST_NILE_AUDITS_ONE]),
      assertions: [
        toolCalled('list_customer_audits'),
        mustMatchAny([/2026-08-10|10\/8|أغسطس/]),
      ],
    }],
  },
  {
    id: 'cmp-reasoning-multiple-flocks-pick-correct-one',
    title: 'Three flocks are in scope with different ages -- the youngest is ' +
      'correctly identified, not conflated with the others',
    dimension: 'tool_result_reasoning',
    turns: [{
      userText: 'إيه أصغر قطيع عند عميل النيل، وعمره كام أسبوع؟',
      toolStubs: withDefaults([
        RESOLVE_NILE_OK,
        LIST_NILE_FLOCKS,
        GET_FLOCK_1_CONTEXT,
      ]),
      assertions: [
        mustMatchAny([/15|١٥/]),
        mustNotMatch([/46|٤٦/]),
      ],
    }],
  },

  // =====================================================================
  // 5. Progressive disclosure (4 scenarios)
  // =====================================================================
  {
    id: 'cmp-progressive-latest-report-headline-then-offer',
    title: '"What is the latest breakout report?" gets a headline (customer, ' +
      'flock, date) and an offer to show details -- not a metrics dump',
    dimension: 'progressive_disclosure',
    turns: [{
      userText: 'إيه آخر تقرير breakout موجود عندك لعميل النيل؟',
      toolStubs: withDefaults([RESOLVE_NILE_OK, LIST_NILE_AUDITS_ONE]),
      assertions: [
        toolCalled('list_customer_audits'),
        maxPercentFigures(0),
        mustMatchAny([/2026-08-10|10\/8|أغسطس/]),
        offersFollowUp(),
      ],
    }],
  },
  {
    id: 'cmp-progressive-audit-summary-headline-then-offer',
    title: 'After selecting an audit whose summary carries a full benchmark ' +
      'block, the reply is still a short headline with an offer, not a dump',
    dimension: 'progressive_disclosure',
    turns: [
      {
        label: 'turn 1: ask for the report',
        userText: 'عايز أشوف آخر audit لعميل النيل',
        toolStubs: withDefaults([RESOLVE_NILE_OK, LIST_NILE_AUDITS_ONE]),
        assertions: [mustMatchAny([/1|١|واحد/])],
      },
      {
        label: 'turn 2: select option 1',
        userText: '1',
        toolStubs: withDefaults([SELECT_AUDIT_1_SUMMARY]),
        assertions: [
          toolCalled('select_audit_option'),
          maxPercentFigures(0),
          offersFollowUp(),
        ],
      },
    ],
  },
  {
    id: 'cmp-progressive-explicit-full-benchmark-not-gated',
    title:
      'An EXPLICIT "give me everything" request must not be gated behind a ' +
      'disclosure question -- it should just answer with the figures',
    dimension: 'progressive_disclosure',
    turns: [{
      userText: 'إديني كل أرقام معيار الفقس كاملة لسلالة روس 308 في الأسبوع 35',
      toolStubs: withDefaults([ROSS_WK35_FULL]),
      assertions: [toolCalled('get_breed_benchmark'), minPercentFigures(2)],
    }],
  },
  {
    id: 'cmp-progressive-explicit-full-breakout-not-gated',
    title:
      'Same check for the egg-breakout standard: an explicit full-detail ' +
      'request gets the figures, not a disclosure question',
    dimension: 'progressive_disclosure',
    turns: [{
      userText: 'وريني كل تفاصيل معيار الـ breakout كامل للأسبوع 40',
      toolStubs: withDefaults([BREAKOUT_WK40_FULL]),
      assertions: [
        toolCalled('get_egg_breakout_benchmark'),
        minPercentFigures(3),
      ],
    }],
  },

  // =====================================================================
  // 6. Brevity (4 scenarios)
  // =====================================================================
  {
    id: 'cmp-brevity-direct-count',
    title: 'A direct count question gets a short answer',
    dimension: 'brevity',
    turns: [{
      userText: 'عميل النيل عنده كام قطيع؟',
      toolStubs: withDefaults([RESOLVE_NILE_OK, LIST_NILE_FLOCKS]),
      assertions: [maxChars(120), maxQuestionMarks(1)],
    }],
  },
  {
    id: 'cmp-brevity-single-metric',
    title: 'A single-metric question gets a short answer, not a written report',
    dimension: 'brevity',
    turns: [{
      userText: 'الخصوبة لهبرد في الأسبوع 40 كام؟',
      toolStubs: withDefaults([HUBBARD_WK40_FULL]),
      assertions: [maxChars(120), maxWords(25)],
    }],
  },
  {
    id: 'cmp-brevity-casual-greeting',
    title: 'Casual small talk gets a short natural reply, no tool call',
    dimension: 'brevity',
    turns: [{
      userText: 'صباح الفل، عامل إيه؟',
      assertions: [
        noToolCall(),
        repliedInArabic(),
        maxChars(80),
        maxQuestionMarks(1),
      ],
    }],
  },
  {
    id: 'cmp-brevity-one-question-max-when-clarifying',
    title: 'Even when a clarification is genuinely needed, the reply asks at ' +
      'most ONE question -- never several options stacked as separate questions',
    dimension: 'brevity',
    turns: [{
      userText: 'عميل هاني عنده كام قطيع؟',
      toolStubs: withDefaults([RESOLVE_AMBIGUOUS_HANI]),
      assertions: [maxQuestionMarks(1)],
    }],
  },

  // =====================================================================
  // 7. Hallucination / grounding (4 scenarios)
  // =====================================================================
  {
    id: 'cmp-hallu-unresolved-customer-never-invents-a-count',
    title: 'An unresolvable customer name never gets an invented flock count',
    dimension: 'hallucination_grounding',
    expectedTools: ['resolve_customer_flock'],
    turns: [{
      userText: 'عميل المنصورة عنده كام قطيع؟',
      toolStubs: withDefaults([RESOLVE_MANSOURA_NOT_FOUND]),
      assertions: [
        mustNotMatch(/^\D*\d+\s*(flock|قطيع)/i),
        mustMatchAny([
          /مش لاقي|مش موجود|مفيش|ما لقيتش|ملقيتش|ملقتش|مش عندي|لم أجد|لم اجد|لا أجد|لا اجد|لم يتم العثور|تعذر العثور|لا يوجد|غير موجود|ليس لدي|not found|couldn'?t find|could not find/i,
        ]),
      ],
    }],
  },
  {
    id: 'cmp-hallu-week-out-of-range-never-interpolates',
    title: 'An out-of-range benchmark week never gets an invented figure',
    dimension: 'hallucination_grounding',
    expectedTools: ['get_breed_benchmark'],
    turns: [{
      userText: 'معيار الفقس لسلالة روس 308 في الأسبوع 90 كام؟',
      toolStubs: withDefaults([ROSS_WK90_OUT_OF_RANGE]),
      assertions: [
        toolCalled('get_breed_benchmark'),
        mustNotMatch(/\d{2}(\.\d+)?\s*(%|٪)/),
        // The real requirement is: state that week 90 is NOT COVERED and do
        // not invent a figure (the `mustNotMatch` above is what enforces "no
        // invented number"). Stating the covered range instead — «متوفر فقط
        // للأعمار من الأسبوع 18 حتى الأسبوع 65» — communicates unavailability
        // exactly as well as «مش متاح» does, and every model under test
        // phrased it that way at least once. The original list accepted only
        // Egyptian-colloquial negations, so a correct, grounded refusal was
        // being scored as a hallucination failure across ALL models, which in
        // turn tripped the disqualifying grounding gate for every candidate.
        // Widened to the positive "only covers X..Y" phrasing and the MSA
        // negations. NOT widened to anything that would let an invented
        // number through.
        mustMatchAny([
          /مش موجود|مش متاح|مش متغطي|مغطيين|غير متاح|مش عندي|not available|not covered/i,
          /متوفر فقط|متاح فقط|متوفرة فقط|متاحة فقط|only (?:available|covers|covered)|فقط للأعمار|ضمن هذا النطاق|خارج النطاق|outside the (?:range|covered)/i,
          /لا (?:يوجد|تتوفر|يتوفر)|لم أجد|لم يتم العثور|تعذر/i,
        ]),
      ],
    }],
  },
  {
    id: 'cmp-hallu-never-states-a-figure-from-an-unstubbed-call',
    title:
      'A second, deliberately UNSTUBBED tool call in the chain must never be ' +
      'answered with an invented figure -- an honest "unavailable" is required',
    dimension: 'hallucination_grounding',
    turns: [{
      userText:
        'عميل النيل عنده كام قطيع، وعمر أكبر واحد فيهم كام أسبوع بالظبط؟',
      // get_flock_context is intentionally NOT stubbed: any call to it comes
      // back as the synthetic "unstubbed_in_eval" error from agent_client.ts.
      toolStubs: withDefaults([RESOLVE_NILE_OK, LIST_NILE_FLOCKS]),
      assertions: [
        mustNotMatch(/\d+\s*(أسبوع|week)/i),
      ],
    }],
  },
  {
    id: 'cmp-hallu-empty-report-never-substituted-with-benchmark',
    title:
      'A report is explicitly requested but none exist -- the model says so, ' +
      'it never falls back to a benchmark tool to manufacture an answer',
    dimension: 'hallucination_grounding',
    note: REPORT_VS_BENCHMARK_CAVEAT,
    expectedTools: ['resolve_customer_flock', 'list_customer_audits'],
    turns: [{
      userText: 'إيه آخر تقرير مسجل لعميل الدلتا؟',
      toolStubs: withDefaults([RESOLVE_DELTA_OK, LIST_DELTA_AUDITS_EMPTY]),
      assertions: [
        toolNotCalled('get_breed_benchmark'),
        toolNotCalled('get_egg_breakout_benchmark'),
        mustMatchAny([
          /مفيش تقارير|لا توجد تقارير|مفيش أي تقرير|لم أجد|لم اجد|لم يتم العثور|لا يوجد|ما فيش تقارير|no reports|not found|couldn'?t find|could not find/i,
        ]),
      ],
    }],
  },

  // =====================================================================
  // 8. Multi-turn realistic conversations (4 scenarios, 4-6 turns each)
  // =====================================================================
  {
    id: 'cmp-multiturn-benchmark-exploration',
    title: 'Four turns exploring benchmarks: same breed/week, same breed new ' +
      'metric, new breed same week, then an unrelated switch to a customer question',
    dimension: 'multi_turn',
    turns: [
      {
        label: 'turn 1: production for Hubbard wk40',
        userText: 'إنتاج هبرد في الأسبوع 40 كام؟',
        toolStubs: withDefaults([HUBBARD_WK40_FULL]),
        assertions: [mustMatchAny([/80|٨٠/])],
      },
      {
        label: 'turn 2: same breed/week, different metric',
        userText: 'طيب الفقس؟',
        toolStubs: withDefaults([HUBBARD_WK40_FULL]),
        assertions: [
          toolCalledWithArgs(
            'get_breed_benchmark',
            (args) => args.breed === 'Hubbard' && args.ageWeek === 40,
            'breed/week carried from turn 1 without re-asking',
          ),
          mustMatchAny([/90\.2|٩٠\.٢/]),
        ],
      },
      {
        label: 'turn 3: breed switches, week is carried',
        userText: 'وإيه معايير سلالة روس 308 في نفس الأسبوع؟',
        toolStubs: withDefaults([ROSS_WK40_FULL]),
        assertions: [
          toolCalledWithArgs(
            'get_breed_benchmark',
            (args) => args.breed === 'Ross 308' && args.ageWeek === 40,
            'breed correctly switched to Ross 308, week 40 still carried',
          ),
        ],
      },
      {
        label: 'turn 4: unrelated switch to a customer question',
        userText: 'تمام، شكرا. عميل النيل عنده كام قطيع؟',
        toolStubs: withDefaults([RESOLVE_NILE_OK, LIST_NILE_FLOCKS]),
        assertions: [mustMatchAny([/3|تلات(?:ة)?|ثلاث(?:ة)?/])],
      },
    ],
  },
  {
    id: 'cmp-multiturn-customer-flock-then-standard-then-switch',
    title: 'Five turns: resolve a customer, drill into its oldest flock, an ' +
      "unrelated question, that flock's breed standard, then a second customer",
    dimension: 'multi_turn',
    turns: [
      {
        label: 'turn 1: flock count',
        userText: 'عميل النيل عنده كام قطيع؟',
        toolStubs: withDefaults([RESOLVE_NILE_OK, LIST_NILE_FLOCKS]),
        assertions: [mustMatchAny([/3|تلات(?:ة)?|ثلاث(?:ة)?/])],
      },
      {
        label: 'turn 2: oldest flock, no customer re-named',
        userText: 'إيه أكبر واحد فيهم، وعمره كام؟',
        toolStubs: withDefaults([LIST_NILE_FLOCKS, GET_FLOCK_3_CONTEXT]),
        assertions: [
          mustMatchAny([/46|٤٦/]),
          mustNotMatch(/أي عميل|لأي عميل|which customer|اسم العميل/i),
        ],
      },
      {
        label: 'turn 3: unrelated general knowledge',
        userText: 'تخزين البيض فترة طويلة بيأثر إزاي على الفقس؟',
        assertions: [noToolCall()],
      },
      {
        label: 'turn 4: standard for that same flock, breed/age implied',
        userText: 'طيب الفقس المفروض يبقى كام لسلالته في نفس عمره؟',
        toolStubs: withDefaults([ROSS_WK46_FULL]),
        assertions: [
          toolCalledWithArgs(
            'get_breed_benchmark',
            (args) => args.breed === 'Ross 308' && args.ageWeek === 46,
            "breed=Ross 308 (flock_3's breed) ageWeek=46 (flock_3's age), both carried from earlier turns",
          ),
        ],
      },
      {
        label: 'turn 5: switch to a second customer',
        userText: 'وبالنسبة لعميل الدلتا، عنده كام قطيع؟',
        toolStubs: withDefaults([RESOLVE_DELTA_OK, LIST_DELTA_FLOCKS]),
        assertions: [
          mustMatchAny([/1|١|واحد/]),
          mustNotMatch(/3|تلات(?:ة)?|ثلاث(?:ة)?/),
        ],
      },
    ],
  },
  {
    id: 'cmp-multiturn-audit-report-flow',
    title:
      'Five turns: ask for a report, list, select, ask one breakout metric, ' +
      'compare it to the benchmark, then switch to an unrelated customer',
    dimension: 'multi_turn',
    turns: [
      {
        label: 'turn 1: ask for the report',
        userText: 'عايز أشوف آخر تقرير لعميل النيل',
        toolStubs: withDefaults([RESOLVE_NILE_OK, LIST_NILE_AUDITS_ONE]),
        assertions: [mustMatchAny([/1|١|واحد/])],
      },
      {
        label: 'turn 2: select option 1',
        userText: '1',
        toolStubs: withDefaults([SELECT_AUDIT_1_SUMMARY]),
        assertions: [toolCalled('select_audit_option')],
      },
      {
        label: 'turn 3: ask a specific breakout metric',
        userText: 'الـ infertile كان كام في التقرير ده؟',
        toolStubs: withDefaults([GET_SELECTED_AUDIT_BREAKOUTS]),
        assertions: [
          toolCalled('get_selected_audit_breakouts'),
          mustMatchAny([/6(\.0)?|٦/]),
        ],
      },
      {
        label: 'turn 4: compare to the benchmark, no audit id reconstructed',
        userText: 'وده أحسن ولا أوحش من المعيار؟',
        toolStubs: withDefaults([COMPARE_SELECTED_AUDIT_TO_BENCHMARK]),
        assertions: [
          toolCalled('compare_selected_audit_to_benchmark'),
          argumentsValidForTool('compare_selected_audit_to_benchmark'),
        ],
      },
      {
        label: 'turn 5: unrelated switch',
        userText: 'تمام شكرا. وعميل الدلتا عندهم كام قطيع؟',
        toolStubs: withDefaults([RESOLVE_DELTA_OK, LIST_DELTA_FLOCKS]),
        assertions: [mustMatchAny([/1|١|واحد/])],
      },
    ],
  },
  {
    id: 'cmp-multiturn-data-entry-intent',
    title:
      'A natural data-entry flow: informational-sounding intent first, then ' +
      'an explicit confirmation before propose_intake commits to anything',
    dimension: 'multi_turn',
    note: INTAKE_SHAPE_CAVEAT,
    turns: [
      {
        label: 'turn 1: only-possible data-entry intent, propose_intake + ask',
        userText: 'عايز أسجل بيانات تفقيس جديدة لعميل النيل',
        toolStubs: withDefaults([RESOLVE_NILE_OK, PROPOSE_INTAKE_NILE]),
        assertions: [
          toolCalled('propose_intake'),
          toolNotCalled('start_intake'),
          asksAtLeastOneQuestion(),
        ],
      },
      {
        label: 'turn 2: explicit confirmation resolves stations, not a start',
        userText: 'أيوه، اعمل كده',
        toolStubs: withDefaults([LIST_APPLICABLE_STATIONS_NILE]),
        assertions: [
          toolCalled('list_applicable_stations'),
          toolNotCalled('start_intake'),
        ],
      },
      {
        label: 'turn 3: user names a station module by description',
        userText: 'هختار محطة المفرخ بتاعة البيئة والإعدادات',
        toolStubs: withDefaults([LOAD_HATCHERS_ENV_SCHEMA]),
        assertions: [
          toolCalledAny(['load_station_schema', 'list_applicable_stations']),
          toolNotCalled('start_intake'),
        ],
      },
    ],
  },

  // =====================================================================
  // 9. Degradation under load (4 scenarios)
  //
  // Exhaustively calling all 32 tools inside one scenario would not be a
  // realistic conversation (many are mutually exclusive write-path tools)
  // and would not test anything meaningful. These four scenarios instead
  // stress the three concrete things a long system prompt + a large tool
  // catalogue + accumulated history actually degrade: conversation LENGTH
  // (5-6 turns), tool-result PAYLOAD SIZE (dozens of stubbed rows), and
  // TOOL-CHOICE precision on a confusable pair several turns deep.
  // =====================================================================
  {
    id: 'cmp-degrade-long-history-then-recall-turn-1',
    title: 'Six turns mixing casual talk, a benchmark, a customer lookup, a ' +
      'station query, and unrelated knowledge -- the final turn must still ' +
      "recall turn 1's figure without re-asking breed or week",
    dimension: 'degradation_under_load',
    turns: [
      {
        label: 'turn 1: casual',
        userText: 'صباح الفل',
        assertions: [noToolCall()],
      },
      {
        label: 'turn 2: benchmark (the fact to recall later)',
        userText: 'إنتاج هبرد في الأسبوع 40 كام؟',
        toolStubs: withDefaults([HUBBARD_WK40_FULL]),
        assertions: [mustMatchAny([/80|٨٠/])],
      },
      {
        label: 'turn 3: customer lookup',
        userText: 'عميل النيل عنده كام قطيع؟',
        toolStubs: withDefaults([RESOLVE_NILE_OK, LIST_NILE_FLOCKS]),
        assertions: [mustMatchAny([/3|تلات(?:ة)?|ثلاث(?:ة)?/])],
      },
      {
        label: 'turn 4: a large station-records payload enters the history',
        userText: 'وريني سجلات باسجار لعميل النيل من 2026-01-01 لحد 2026-08-01',
        toolStubs: withDefaults([
          RESOLVE_NILE_OK,
          QUERY_STATION_RECORDS_PASGAR_LARGE,
        ]),
        assertions: [toolCalled('query_station_records'), maxChars(400)],
      },
      {
        label: 'turn 5: unrelated general knowledge',
        userText: 'إيه الفرق بين المفرخ وماكينة التحضين؟',
        assertions: [noToolCall()],
      },
      {
        label: "turn 6: recall turn 1's figure without re-asking",
        userText: 'طيب ارجع لسؤالي الأول، الإنتاج كان كام؟',
        toolStubs: withDefaults([HUBBARD_WK40_FULL]),
        assertions: [
          mustMatchAny([/80|٨٠/]),
          mustNotMatch(/أي سلالة|أي أسبوع|which breed|which week/i),
        ],
      },
    ],
  },
  {
    id: 'cmp-degrade-large-payload-stays-concise',
    title:
      'A 42-row query_station_records result must be summarized concisely, ' +
      'not echoed row by row, and a follow-up average uses the aggregation ' +
      'tool rather than the model averaging 42 rows itself',
    dimension: 'degradation_under_load',
    turns: [
      {
        label: 'turn 1: row count from a large payload',
        userText:
          'كام سجل باسجار موجود لعميل النيل من 2026-01-01 لحد 2026-08-01؟',
        toolStubs: withDefaults([
          RESOLVE_NILE_OK,
          QUERY_STATION_RECORDS_PASGAR_LARGE,
        ]),
        assertions: [
          toolCalled('query_station_records'),
          mustMatchAny([/42|٤٢/]),
          maxChars(300),
          mustNotMatch(/rec_pasgar_1\b.*rec_pasgar_2\b/s),
        ],
      },
      {
        label: 'turn 2: average score over the same large range',
        userText: 'ومتوسط الـ pasgar score كام في نفس المدى؟',
        toolStubs: withDefaults([COMPARE_STATION_METRICS_PASGAR]),
        assertions: [
          toolCalled('compare_station_metrics'),
          argumentsValidForTool('compare_station_metrics'),
          mustMatchAny([/82\.4|82,4|٨٢\.٤/]),
        ],
      },
    ],
  },
  {
    id: 'cmp-degrade-two-customers-then-disambiguating-reference',
    title:
      'Two different customers get resolved in the same session; a later ' +
      'reference back to the first ("التاني - قصدي النيل") must not be ' +
      "answered with the second customer's data",
    dimension: 'degradation_under_load',
    turns: [
      {
        label: 'turn 1: Nile count',
        userText: 'عميل النيل عنده كام قطيع؟',
        toolStubs: withDefaults([RESOLVE_NILE_OK, LIST_NILE_FLOCKS]),
        assertions: [mustMatchAny([/3|تلات(?:ة)?|ثلاث(?:ة)?/])],
      },
      {
        label: 'turn 2: Delta count',
        userText: 'وعميل الدلتا؟',
        toolStubs: withDefaults([RESOLVE_DELTA_OK, LIST_DELTA_FLOCKS]),
        assertions: [mustMatchAny([/1|١|واحد/])],
      },
      {
        label: 'turn 3: unrelated',
        userText: 'إيه أهمية الـ turning angle في التحضين؟',
        assertions: [noToolCall()],
      },
      {
        label: 'turn 4: explicit correction back to the first customer',
        userText: 'طيب التاني - لأ قصدي النيل - أكبر قطيع عنده عمره كام؟',
        toolStubs: withDefaults([LIST_NILE_FLOCKS, GET_FLOCK_3_CONTEXT]),
        assertions: [mustMatchAny([/46|٤٦/])],
      },
    ],
  },
  {
    id: 'cmp-degrade-confusable-tool-pair-deep-in-history',
    title: 'Six turns deep, a question about "the record shown earlier" must ' +
      'call get_record_provenance with the id from that earlier tool ' +
      'result, not get_flock_context',
    dimension: 'degradation_under_load',
    turns: [
      {
        label: 'turn 1: casual',
        userText: 'أهلاً',
        assertions: [noToolCall()],
      },
      {
        label: 'turn 2: a station query that surfaces rec_1',
        userText:
          'وريني سجلات إعدادات المفرخ لعميل النيل من 2026-06-01 لحد 2026-07-31',
        toolStubs: withDefaults([
          RESOLVE_NILE_OK,
          QUERY_STATION_RECORDS_SETTERS_ENV,
        ]),
        assertions: [toolCalled('query_station_records')],
      },
      {
        label: 'turn 3: unrelated',
        userText: 'الفقس لسلالة كوب 500 في الأسبوع 30 كام؟',
        toolStubs: withDefaults([COBB_WK30_FULL]),
        assertions: [mustMatchAny([/88|٨٨/])],
      },
      {
        label: 'turn 4: unrelated',
        userText: 'عميل الدلتا عنده كام قطيع؟',
        toolStubs: withDefaults([RESOLVE_DELTA_OK, LIST_DELTA_FLOCKS]),
        assertions: [mustMatchAny([/1|١|واحد/])],
      },
      {
        label: 'turn 5: unrelated',
        userText: 'إيه الفرق بين التلقيح الطبيعي والصناعي؟',
        assertions: [noToolCall()],
      },
      {
        label:
          'turn 6: refers back to the record from turn 2 -- correct tool is provenance, not flock context',
        userText: 'أول سجل ظهرلي بتاع المفرخ ده، هو حديث ولا قديم؟',
        toolStubs: withDefaults([GET_RECORD_PROVENANCE_REC1]),
        assertions: [
          toolCalledWithArgs(
            'get_record_provenance',
            (args) => args.recordId === 'rec_1',
            'recordId="rec_1" carried from the turn-2 query result, 4 turns earlier',
          ),
          argumentsValidForTool('get_record_provenance'),
        ],
      },
    ],
  },
]

export function scenarioCountsByDimension(): ReadonlyArray<
  { dimension: ComparisonDimension; count: number; turnCount: number }
> {
  return COMPARISON_DIMENSIONS.map(({ key }) => {
    const scenarios = COMPARISON_SCENARIOS.filter((s) => s.dimension === key)
    return {
      dimension: key,
      count: scenarios.length,
      turnCount: scenarios.reduce((sum, s) => sum + s.turns.length, 0),
    }
  })
}
