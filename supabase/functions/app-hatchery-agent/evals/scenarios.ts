// Scenario data + assertion helpers for `run_evals.ts` -- the ChickMark
// text-agent model-acceptance suite.
//
// Every scenario runs against the REAL model over the REAL OpenRouter
// `/v1/responses` shape (see `agent_client.ts`), using the REAL system
// prompt (`buildAgentInstructions`) and the REAL tool catalogue
// (`AGENT_MODEL_TOOL_DEFINITIONS`). Tool names, argument shapes, and result
// shapes below were taken from `agent_tool_contract.ts`, `agent_read_tools.ts`
// and `bmk_tools.ts` after reading them -- nothing here invents a tool name
// or a result shape.
//
// This file only defines DATA and pure assertion functions -- no network, no
// process I/O. `run_evals.ts` is what actually talks to the wire.
//
// -----------------------------------------------------------------------
// A note on "report vs benchmark" (see the `report_vs_benchmark` scenarios):
// the voice-only `CHICKMARK_REALTIME_POLICY` carries an explicit
// "Report vs benchmark routing" section (`REPORT_VS_BENCHMARK` in
// `agent_prompt.ts`) that draws this distinction in so many words. The TEXT
// policy this harness actually exercises -- `CHICKMARK_AGENT_POLICY`, built
// by `buildAgentInstructions` -- does NOT include that section (see the
// comment directly above `CHICKMARK_REALTIME_POLICY` in `agent_prompt.ts`:
// "voice-only... adds two voice-only sections"). The typed policy only has
// the general `EVIDENCE_AND_SCOPE` audit-history rule and
// `BENCHMARK_DISCIPLINE`'s "never state a benchmark from memory". So this
// dimension is a genuinely open question for the text agent: it tests
// whether the general rules are enough to keep a report request away from a
// benchmark tool, not whether the model followed an explicit routing rule
// that (for this channel) does not exist.
// -----------------------------------------------------------------------

import {
  type AgentModelInputItem,
  containsArabic,
  type FunctionCallItem,
  type ToolStub,
  type TurnResult,
  validateToolArguments,
  wordCount,
} from './agent_client.ts'

// ---------------------------------------------------------------------------
// Assertions
// ---------------------------------------------------------------------------

export interface AssertionOutcome {
  readonly pass: boolean
  readonly label: string
  readonly detail?: string
}

export type Assertion = (result: TurnResult) => AssertionOutcome

export function finalText(result: TurnResult): string {
  return result.finalReply
}

/**
 * Normalizes reply text before REGEX MATCHING only (never before display).
 *
 * Models legitimately vary in surface form in ways that have nothing to do
 * with whether the answer is correct, and matching raw text punished correct
 * answers in the 2026-08-19 model comparison:
 *   - Arabic-Indic / Eastern-Arabic digits vs ASCII (٤٢ vs 42)
 *   - Unicode hyphens inside dates (U+2010..U+2015, notably the non-breaking
 *     U+2011 that several models emit in `2026\u20111\u201101`)
 *   - Markdown emphasis wrapped around figures (`**82.4**`)
 *   - Curly quotes around quoted customer names
 *   - Arabic presentation variants: tatweel, and alef hamza forms
 * Normalizing these is NOT loosening the assertion: the semantic content the
 * assertion tests for is identical either way.
 */
export function normalizeForMatch(text: string): string {
  let out = text
  // Arabic-Indic (U+0660..0669) and Eastern Arabic-Indic (U+06F0..06F9) digits.
  out = out.replace(
    /[\u0660-\u0669]/g,
    (d) => String(d.charCodeAt(0) - 0x0660),
  )
  out = out.replace(
    /[\u06F0-\u06F9]/g,
    (d) => String(d.charCodeAt(0) - 0x06F0),
  )
  // Unicode dashes -> ASCII hyphen.
  out = out.replace(/[\u2010-\u2015\u2212]/g, '-')
  // Curly quotes -> ASCII.
  out = out.replace(/[\u2018\u2019\u201B]/g, "'").replace(
    /[\u201C\u201D\u201F]/g,
    '"',
  )
  // Markdown emphasis.
  out = out.replace(/\*\*/g, '').replace(/(?<!\S)\*(?!\S)/g, '')
  // Arabic tatweel and alef hamza variants.
  out = out.replace(/\u0640/g, '').replace(/[\u0623\u0625\u0622]/g, '\u0627')
  return out
}

export function maxWords(n: number): Assertion {
  return (result) => {
    const text = finalText(result)
    const count = wordCount(text)
    return {
      pass: count <= n,
      label: `maxWords(${n})`,
      detail: `${count} words: "${text}"`,
    }
  }
}

export function mustMatchAny(patterns: readonly RegExp[]): Assertion {
  return (result) => {
    const text = finalText(result)
    const probe = normalizeForMatch(text)
    const pass = patterns.some((pattern) => pattern.test(probe))
    return {
      pass,
      label: `mustMatchAny(${patterns.map((p) => p.source).join(' | ')})`,
      detail: `"${text}"`,
    }
  }
}

export function mustNotMatch(patterns: RegExp | readonly RegExp[]): Assertion {
  const list: readonly RegExp[] = Array.isArray(patterns)
    ? patterns
    : [patterns as RegExp]
  return (result) => {
    const text = finalText(result)
    const probe = normalizeForMatch(text)
    const hit = list.find((pattern) => pattern.test(probe))
    return {
      pass: !hit,
      label: `mustNotMatch(${list.map((p) => p.source).join(' | ')})`,
      detail: hit ? `matched ${hit.source} in "${text}"` : `"${text}"`,
    }
  }
}

export function toolCalled(name: string): Assertion {
  return (result) => ({
    pass: result.allToolCalls.some((call) => call.name === name),
    label: `toolCalled(${name})`,
    detail: `calls made: ${
      result.allToolCalls.map((c) => c.name).join(', ') || 'none'
    }`,
  })
}

export function toolCalledAny(names: readonly string[]): Assertion {
  return (result) => ({
    pass: result.allToolCalls.some((call) => names.includes(call.name)),
    label: `toolCalledAny(${names.join(' | ')})`,
    detail: `calls made: ${
      result.allToolCalls.map((c) => c.name).join(', ') || 'none'
    }`,
  })
}

export function toolNotCalled(name: string): Assertion {
  return (result) => ({
    pass: !result.allToolCalls.some((call) => call.name === name),
    label: `toolNotCalled(${name})`,
    detail: `calls made: ${
      result.allToolCalls.map((c) => c.name).join(', ') || 'none'
    }`,
  })
}

export function noToolCall(): Assertion {
  return (result) => ({
    pass: result.allToolCalls.length === 0,
    label: 'noToolCall',
    detail: `calls made: ${
      result.allToolCalls.map((c) => c.name).join(', ') || 'none'
    }`,
  })
}

export function repliedInArabic(): Assertion {
  return (result) => {
    const text = finalText(result)
    return {
      pass: containsArabic(text),
      label: 'repliedInArabic',
      detail: `"${text}"`,
    }
  }
}

export function transportOk(): Assertion {
  return (result) => ({
    pass: result.status !== 'transport_error',
    label: 'transportOk',
    detail: result.status === 'transport_error'
      ? `${result.transportKind ?? 'unknown'}: ${result.transportDetail ?? ''}`
      : 'ok',
  })
}

/**
 * A call to `name` exists AND its parsed arguments satisfy `predicate`.
 * Used for multi-step chains where the second call must use a value the
 * first call's stubbed result produced (e.g. an `id` handed back by
 * `resolve_customer_flock`), and for "did not carry the wrong argument
 * forward" checks.
 */
export function toolCalledWithArgs(
  name: string,
  predicate: (args: Record<string, unknown>) => boolean,
  description: string,
): Assertion {
  return (result) => {
    const calls = result.allToolCalls.filter((call) => call.name === name)
    const pass = calls.some((call) => predicate(call.arguments))
    return {
      pass,
      label: `toolCalledWithArgs(${name}, ${description})`,
      detail: calls.length === 0
        ? `${name} was not called at all`
        : `args seen: ${
          calls.map((c) => JSON.stringify(c.arguments)).join(' | ')
        }`,
    }
  }
}

/**
 * Mechanically validates EVERY call to `name` against the real declared
 * schema in `AGENT_TOOL_CONTRACT` (required fields present, correct types,
 * no invented fields) via `validateToolArguments`. Fails if `name` was never
 * called, since "the arguments were correct" is vacuous otherwise.
 */
export function argumentsValidForTool(name: string): Assertion {
  return (result) => {
    const calls = result.allToolCalls.filter((call) => call.name === name)
    if (calls.length === 0) {
      return {
        pass: false,
        label: `argumentsValidForTool(${name})`,
        detail: `${name} was not called`,
      }
    }
    const problems = calls.flatMap((call) => {
      const validation = validateToolArguments(name, call.arguments)
      return validation.problems.map((problem) =>
        `${JSON.stringify(call.arguments)}: ${problem}`
      )
    })
    return {
      pass: problems.length === 0,
      label: `argumentsValidForTool(${name})`,
      detail: problems.length === 0 ? 'all calls valid' : problems.join('; '),
    }
  }
}

/**
 * Mechanically validates the ARGUMENTS OF EVERY TOOL CALL made in the turn,
 * regardless of name -- the run_probe.ts "structured arguments" capability
 * check uses this broader form; run_evals.ts scenarios mostly use the
 * narrower `argumentsValidForTool` instead so a failure names which tool.
 */
export function allArgumentsValid(): Assertion {
  return (result) => {
    const problems = result.allToolCalls.flatMap((call) => {
      const validation = validateToolArguments(call.name, call.arguments)
      return validation.problems.map((problem) =>
        `${call.name} ${JSON.stringify(call.arguments)}: ${problem}`
      )
    })
    return {
      pass: result.allToolCalls.length > 0 && problems.length === 0,
      label: 'allArgumentsValid',
      detail: result.allToolCalls.length === 0
        ? 'no tool calls made'
        : (problems.length === 0 ? 'all calls valid' : problems.join('; ')),
    }
  }
}

/**
 * No assistant text appears before the FIRST function_call in the FIRST
 * round that contains one -- i.e. no "let me check" preamble, and no leak of
 * tool/database mechanics into that preamble if one is spoken at all.
 */
export function noMechanicsLeakBeforeToolCall(): Assertion {
  return (result) => {
    const round = result.rounds.find((r) => r.functionCalls.length > 0)
    if (!round) {
      return {
        pass: false,
        label: 'noMechanicsLeakBeforeToolCall',
        detail: 'no tool call found in any round',
      }
    }
    const preamble = round.preambleBeforeFirstToolCall
    const leaks =
      /resolve_customer_flock|list_customer|get_breed_benchmark|get_egg_breakout|tool call|أداة|قاعدة بيانات|database/i
        .test(preamble)
    return {
      pass: !leaks,
      label: 'noMechanicsLeakBeforeToolCall',
      detail: preamble ? `preamble: "${preamble}"` : 'no preamble',
    }
  }
}

// ---------------------------------------------------------------------------
// Scenario / tool-stub data
// ---------------------------------------------------------------------------

export type Dimension =
  | 'tool_selection'
  | 'report_vs_benchmark'
  | 'context_retention'
  | 'multi_step_tool_use'
  | 'no_repeated_clarification'
  | 'arabic_understanding'
  | 'concise_synthesis'
  | 'missing_data_honesty'
  | 'tool_argument_correctness'

export const DIMENSIONS: ReadonlyArray<{ key: Dimension; title: string }> = [
  {
    key: 'tool_selection',
    title: 'Correct tool selection (not a plausible neighbour)',
  },
  { key: 'report_vs_benchmark', title: 'Report vs benchmark routing' },
  { key: 'context_retention', title: 'Context retention across turns' },
  { key: 'multi_step_tool_use', title: 'Multi-step tool use' },
  { key: 'no_repeated_clarification', title: 'No repeated clarification' },
  { key: 'arabic_understanding', title: 'Arabic understanding' },
  { key: 'concise_synthesis', title: 'Concise synthesis (length ceiling)' },
  {
    key: 'missing_data_honesty',
    title: 'Missing-data honesty (no invented numbers)',
  },
  { key: 'tool_argument_correctness', title: 'Tool argument correctness' },
]

export interface EvalTurnSpec {
  readonly label?: string
  readonly userText: string
  readonly toolStubs?: readonly ToolStub[]
  readonly assertions: readonly Assertion[]
}

export interface EvalScenario {
  readonly id: string
  readonly title: string
  readonly dimension: Dimension
  readonly turns: readonly EvalTurnSpec[]
  readonly note?: string
}

/**
 * Fallback stubs for bootstrap tools the model may reasonably call before
 * anything else, applied UNDER (never overriding) a turn's own `toolStubs`.
 * `buildAgentInstructions` embeds `accessRole`/`allowedCustomerCount` in the
 * trusted-context JSON already, so a well-behaved model rarely needs
 * `get_user_scope`, but a scenario that never scripted it would otherwise
 * fail on scope-discovery starvation instead of the behavior it means to
 * test.
 */
export const DEFAULT_TOOL_STUBS: readonly ToolStub[] = [
  {
    name: 'get_user_scope',
    output: {
      ok: true,
      code: 'ok',
      data: { accessRole: 'admin', allowedCustomerCount: 2 },
    },
  },
  {
    name: 'list_customers',
    output: {
      ok: true,
      code: 'ok',
      data: {
        customers: [
          { id: 'cust_eval_nile', name: 'عميل النيل' },
          { id: 'cust_eval_delta', name: 'عميل الدلتا' },
        ],
        truncated: false,
      },
    },
  },
]

// Real result shapes, taken from `agent_read_tools.ts` (resolveCustomerFlock,
// listCustomerFlocks) and `bmk_tools.ts` (resolveBreedBenchmark /
// resolveEggBreakoutBenchmark) after reading them.

const RESOLVE_NILE_OK: ToolStub = {
  name: 'resolve_customer_flock',
  output: {
    ok: true,
    code: 'ok',
    data: {
      status: 'ok',
      customer: { id: 'cust_eval_nile', name: 'عميل النيل' },
      flock: null,
    },
  },
}

const RESOLVE_NILE_NOT_FOUND: ToolStub = {
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

const LIST_NILE_FLOCKS: ToolStub = {
  name: 'list_customer_flocks',
  output: {
    ok: true,
    code: 'ok',
    data: {
      flocks: [
        { id: 'flock_1', name: 'قطيع 1', ageWeeks: 20 },
        { id: 'flock_2', name: 'قطيع 2', ageWeeks: 32 },
        { id: 'flock_3', name: 'قطيع 3', ageWeeks: 46 },
      ],
      truncated: false,
    },
  },
}

const GET_FLOCK_3_CONTEXT: ToolStub = {
  name: 'get_flock_context',
  output: {
    ok: true,
    code: 'ok',
    data: { id: 'flock_3', name: 'قطيع 3', ageWeeks: 46 },
  },
}

const HUBBARD_WK40_FULL: ToolStub = {
  name: 'get_breed_benchmark',
  output: {
    ok: true,
    code: 'ok',
    data: {
      breed: 'Hubbard',
      ageWeek: 40,
      hatchabilityPct: 90.2,
      fertilityPct: 96.5,
      hofPct: 93.47,
      productionPct: 80,
      eggWeightG: 65.3,
      chickWeightG: 46,
      unavailable: [],
    },
  },
}

const ROSS_WK35_FULL: ToolStub = {
  name: 'get_breed_benchmark',
  output: {
    ok: true,
    code: 'ok',
    data: {
      breed: 'Ross 308',
      ageWeek: 35,
      hatchabilityPct: 92.4,
      fertilityPct: 90.1,
      hofPct: 95.0,
      productionPct: 78.5,
      eggWeightG: 64.1,
      chickWeightG: 45.2,
      unavailable: [],
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

const BREAKOUT_WK40_INFERTILE_ONLY: ToolStub = {
  name: 'get_egg_breakout_benchmark',
  output: {
    ok: true,
    code: 'ok',
    data: {
      ageWeek: 40,
      requested: [{ metric: 'infertile', value: 6.2, unit: '%' }],
      unavailable: [],
      context: {
        ageWeek: 40,
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
      },
    },
  },
}

const LIST_NILE_AUDITS_ONE: ToolStub = {
  name: 'list_customer_audits',
  output: {
    ok: true,
    code: 'ok',
    data: {
      customerId: 'cust_eval_nile',
      flockId: null,
      audits: [
        {
          id: 'audit_1',
          date: '2026-08-10',
          status: 'approved',
          customerName: 'عميل النيل',
          flockName: 'قطيع 3',
          hatcheryName: 'المفرخ الرئيسي',
          selectedStationKeys: ['hatcher'],
          stationsCompleted: ['hatcher'],
        },
      ],
      truncated: false,
    },
  },
}

// ---------------------------------------------------------------------------
// Scenarios -- at least two cases per dimension, per the task.
// ---------------------------------------------------------------------------

export const SCENARIOS: readonly EvalScenario[] = [
  // -------------------------------------------------------------------
  // 1. Correct tool selection
  // -------------------------------------------------------------------
  {
    id: 'tool-selection-flock-count',
    title:
      'Flock-count question calls the customer/flock tools, not a benchmark tool',
    dimension: 'tool_selection',
    turns: [{
      userText: 'عميل النيل عنده كام flock؟',
      toolStubs: [RESOLVE_NILE_OK, LIST_NILE_FLOCKS],
      assertions: [
        toolCalledAny(['resolve_customer_flock', 'list_customer_flocks']),
        toolNotCalled('get_breed_benchmark'),
        toolNotCalled('get_egg_breakout_benchmark'),
        mustMatchAny([/3|تلات(?:ة)?|ثلاث(?:ة)?/]),
      ],
    }],
  },
  {
    id: 'tool-selection-breed-benchmark',
    title:
      'Breed-standard question calls get_breed_benchmark, not the age-only breakout table or audit tools',
    dimension: 'tool_selection',
    turns: [{
      userText: 'إيه معيار الفقس لسلالة هبرد في الأسبوع 40؟',
      toolStubs: [HUBBARD_WK40_FULL],
      assertions: [
        toolCalled('get_breed_benchmark'),
        toolNotCalled('get_egg_breakout_benchmark'),
        toolNotCalled('list_customer_audits'),
      ],
    }],
  },

  // -------------------------------------------------------------------
  // 2. Report vs benchmark routing (see the file-header note: the TEXT
  // policy carries no explicit routing block for this -- these scenarios
  // test whether the general rules are enough on their own).
  // -------------------------------------------------------------------
  {
    id: 'report-vs-benchmark-report-wording',
    title:
      'An explicit report/history request never resolves to a benchmark tool',
    dimension: 'report_vs_benchmark',
    note:
      'Uses list_customer_audits/resolve_customer_flock stubs so the model can ' +
      'pursue the report path; the only hard requirement is that no benchmark tool ' +
      'is ever called for a request this explicit about wanting a recorded report.',
    turns: [{
      userText: 'إيه آخر تقرير breakout مسجل عندنا لعميل النيل؟',
      toolStubs: [RESOLVE_NILE_OK, LIST_NILE_AUDITS_ONE],
      assertions: [
        toolNotCalled('get_breed_benchmark'),
        toolNotCalled('get_egg_breakout_benchmark'),
      ],
    }],
  },
  {
    id: 'report-vs-benchmark-standard-wording',
    title:
      'A published-standard question (age + breed, no recorded-data wording) calls the benchmark tool, not audit tools',
    dimension: 'report_vs_benchmark',
    turns: [{
      userText: 'معيار الفقس لسلالة روس 308 في الأسبوع 35 كام؟',
      toolStubs: [ROSS_WK35_FULL],
      assertions: [
        toolCalled('get_breed_benchmark'),
        toolNotCalled('list_customer_audits'),
        toolNotCalled('select_audit_option'),
      ],
    }],
  },

  // -------------------------------------------------------------------
  // 3. Context retention across turns
  // -------------------------------------------------------------------
  {
    id: 'context-retention-flock-followup',
    title:
      "A same-session follow-up reuses turn 1's resolved customer without re-asking",
    dimension: 'context_retention',
    turns: [
      {
        label: 'turn 1: flock count',
        userText: 'عميل النيل عنده كام flock؟',
        toolStubs: [RESOLVE_NILE_OK, LIST_NILE_FLOCKS],
        assertions: [mustMatchAny([/3|تلات(?:ة)?|ثلاث(?:ة)?/])],
      },
      {
        label: 'turn 2: unrelated general knowledge',
        userText: 'تخزين البيض فترة طويلة بيأثر إزاي على الفقس؟',
        assertions: [noToolCall()],
      },
      {
        label:
          'turn 3: follow-up referring back to turn 1, no customer named again',
        userText: 'طيب أكبر واحد فيهم عمره كام؟',
        toolStubs: [LIST_NILE_FLOCKS, GET_FLOCK_3_CONTEXT],
        assertions: [
          mustMatchAny([/46|٤٦/]),
          mustNotMatch(/أي عميل|لأي عميل|which customer|اسم العميل/i),
        ],
      },
    ],
  },
  {
    id: 'context-retention-benchmark-followup',
    title:
      "A same-session follow-up reuses turn 1's breed and age without re-asking",
    dimension: 'context_retention',
    turns: [
      {
        label: 'turn 1: production for Hubbard wk40',
        userText: 'إنتاج هبرد في الأسبوع 40 كام؟',
        toolStubs: [HUBBARD_WK40_FULL],
        assertions: [mustMatchAny([/80|٨٠/])],
      },
      {
        label: 'turn 2: unrelated',
        userText: 'إيه الفرق بين التلقيح الطبيعي والصناعي؟',
        assertions: [noToolCall()],
      },
      {
        label: 'turn 3: same breed/week implied, asks for a different metric',
        userText: 'طيب الخصوبة كام؟',
        toolStubs: [HUBBARD_WK40_FULL],
        assertions: [
          toolCalledWithArgs(
            'get_breed_benchmark',
            (args) => args.breed === 'Hubbard' && args.ageWeek === 40,
            'breed=Hubbard ageWeek=40 (carried from turn 1, not re-asked)',
          ),
          mustNotMatch(/أي سلالة|أي أسبوع|which breed|which week/i),
          mustMatchAny([/96\.5|96,5|96٫5|٩٦\.٥|٩٦٫٥/]),
        ],
      },
    ],
  },

  // -------------------------------------------------------------------
  // 4. Multi-step tool use (single turn, tool A then tool B using A's result)
  // -------------------------------------------------------------------
  {
    id: 'multi-step-resolve-then-list',
    title:
      "resolve_customer_flock's returned customer id is used in a follow-up list_customer_flocks call",
    dimension: 'multi_step_tool_use',
    turns: [{
      userText: 'عميل النيل عنده كام flock واكبر واحد فيهم عمره كام؟',
      toolStubs: [RESOLVE_NILE_OK, LIST_NILE_FLOCKS],
      assertions: [
        toolCalled('resolve_customer_flock'),
        toolCalledWithArgs(
          'list_customer_flocks',
          (args) => args.customerId === 'cust_eval_nile',
          'customerId=cust_eval_nile (the id resolve_customer_flock returned)',
        ),
        mustMatchAny([/46|٤٦/]),
      ],
    }],
  },
  {
    id: 'multi-step-list-then-select-audit',
    title:
      'A numbered audit choice calls select_audit_option after list_customer_audits presented the options',
    dimension: 'multi_step_tool_use',
    turns: [
      {
        label: 'turn 1: ask for audit history',
        userText: 'عايز أشوف آخر audit لعميل النيل',
        toolStubs: [RESOLVE_NILE_OK, LIST_NILE_AUDITS_ONE],
        assertions: [mustMatchAny([/1|١|واحد|الأول/])],
      },
      {
        label: 'turn 2: select option 1',
        userText: '1',
        toolStubs: [{
          name: 'select_audit_option',
          output: {
            ok: true,
            code: 'ok',
            data: {
              id: 'audit_1',
              date: '2026-08-10',
              status: 'approved',
              customerName: 'عميل النيل',
              flockName: 'قطيع 3',
              hatcheryName: 'المفرخ الرئيسي',
            },
          },
        }],
        assertions: [toolCalled('select_audit_option')],
      },
    ],
  },

  // -------------------------------------------------------------------
  // 5. No repeated clarification (everything needed was already supplied)
  // -------------------------------------------------------------------
  {
    id: 'no-reclarify-breed-and-week-given',
    title:
      'Breed and age were both given in one message -- the tool is called directly, nothing is re-asked',
    dimension: 'no_repeated_clarification',
    turns: [{
      userText: 'الفقس لسلالة روس 308 في الأسبوع 35 كام؟',
      toolStubs: [ROSS_WK35_FULL],
      assertions: [
        toolCalled('get_breed_benchmark'),
        mustNotMatch(/أي سلالة|أي أسبوع|which breed|which week|تقصد إيه/i),
      ],
    }],
  },
  {
    id: 'no-reclarify-breakout-is-age-only',
    title:
      "The egg-breakout standard is age-only -- the model doesn't ask for a breed it never needed",
    dimension: 'no_repeated_clarification',
    turns: [{
      userText: 'نسبة الـ infertile المفروض تكون كام في الأسبوع 40؟',
      toolStubs: [BREAKOUT_WK40_INFERTILE_ONLY],
      assertions: [
        toolCalled('get_egg_breakout_benchmark'),
        mustNotMatch(/سلالة|breed/i),
        mustMatchAny([/6\.2|6,2|6٫2|٦\.٢|٦٫٢/]),
      ],
    }],
  },

  // -------------------------------------------------------------------
  // 6. Arabic understanding
  // -------------------------------------------------------------------
  {
    id: 'arabic-casual-no-tool',
    title: 'Casual Arabic small talk gets an Arabic reply with no tool call',
    dimension: 'arabic_understanding',
    turns: [{
      userText: 'صباح الفل، عامل إيه؟',
      assertions: [noToolCall(), repliedInArabic(), maxWords(40)],
    }],
  },
  {
    id: 'arabic-technical-with-tool',
    title:
      'An Arabic technical question resolves the correct tool AND replies in Arabic',
    dimension: 'arabic_understanding',
    turns: [{
      userText: 'عميل الدلتا عندهم كام قطيع؟',
      toolStubs: [
        {
          name: 'resolve_customer_flock',
          output: {
            ok: true,
            code: 'ok',
            data: {
              status: 'ok',
              customer: { id: 'cust_eval_delta', name: 'عميل الدلتا' },
              flock: null,
            },
          },
        },
        {
          name: 'list_customer_flocks',
          output: {
            ok: true,
            code: 'ok',
            data: {
              flocks: [{ id: 'd1', name: 'قطيع دلتا 1', ageWeeks: 12 }],
              truncated: false,
            },
          },
        },
      ],
      assertions: [
        toolCalledAny(['resolve_customer_flock', 'list_customer_flocks']),
        repliedInArabic(),
        mustMatchAny([/1|١|واحد/]),
      ],
    }],
  },

  // -------------------------------------------------------------------
  // 7. Concise synthesis (length ceiling)
  // -------------------------------------------------------------------
  {
    id: 'concise-direct-count',
    title:
      'A direct factual count question gets a short answer, not a written report',
    dimension: 'concise_synthesis',
    turns: [{
      userText: 'عميل النيل عنده كام flock؟',
      toolStubs: [RESOLVE_NILE_OK, LIST_NILE_FLOCKS],
      assertions: [maxWords(30)],
    }],
  },
  {
    id: 'concise-single-metric',
    title:
      'A single requested metric is answered concisely, without a full-row dump',
    dimension: 'concise_synthesis',
    turns: [{
      userText: 'إنتاج هبرد في الأسبوع 40 كام؟',
      toolStubs: [HUBBARD_WK40_FULL],
      assertions: [
        maxWords(35),
        mustMatchAny([/80|٨٠/]),
      ],
    }],
  },

  // -------------------------------------------------------------------
  // 8. Missing-data honesty (never invent a number)
  // -------------------------------------------------------------------
  {
    id: 'missing-data-unknown-customer',
    title:
      'An unresolvable customer name never gets an invented flock count or percentage',
    dimension: 'missing_data_honesty',
    turns: [{
      userText: 'عميل المنصورة عنده كام flock؟',
      toolStubs: [RESOLVE_NILE_NOT_FOUND],
      assertions: [
        mustNotMatch(/^\D*\d+\s*(flock|قطيع)/i),
        mustMatchAny([
          /مش لاقي|مش موجود|مفيش|ما لقيتش|ملقيتش|ملقتش|مش عندي|not found|couldn'?t find/i,
        ]),
      ],
    }],
  },
  {
    id: 'missing-data-week-out-of-range',
    title:
      'An out-of-range benchmark week never gets an interpolated or invented figure',
    dimension: 'missing_data_honesty',
    turns: [{
      userText: 'معيار الفقس لسلالة روس 308 في الأسبوع 90 كام؟',
      toolStubs: [ROSS_WK90_OUT_OF_RANGE],
      assertions: [
        toolCalled('get_breed_benchmark'),
        mustNotMatch(/\d{2}(\.\d+)?\s*(%|٪)/),
        mustMatchAny([
          /مش موجود|مش متاح|مش متغطي|مغطيين|غير متاح|مش عندي|not available|not covered/i,
        ]),
      ],
    }],
  },

  // -------------------------------------------------------------------
  // 9. Tool argument correctness
  // -------------------------------------------------------------------
  {
    id: 'arguments-breed-transliteration',
    title:
      'An Arabic-script breed name is transliterated to Latin script before the tool call, per BENCHMARK_DISCIPLINE',
    dimension: 'tool_argument_correctness',
    turns: [{
      userText: 'الفقس لسلالة روس في الأسبوع 35 كام؟',
      toolStubs: [ROSS_WK35_FULL],
      assertions: [
        argumentsValidForTool('get_breed_benchmark'),
        toolCalledWithArgs(
          'get_breed_benchmark',
          (args) => typeof args.breed === 'string' && !/[؀-ۿ]/.test(args.breed),
          'breed argument is Latin-script, not the Arabic "روس" the user typed',
        ),
        toolCalledWithArgs(
          'get_breed_benchmark',
          (args) => args.ageWeek === 35,
          'ageWeek=35 as an integer',
        ),
      ],
    }],
  },
  {
    id: 'arguments-breakout-metrics-scoped',
    title:
      'A single named breakout metric is passed as the metrics argument, not omitted into a full dump',
    dimension: 'tool_argument_correctness',
    turns: [{
      userText: 'نسبة الـ infertile بس في الأسبوع 40 كام؟',
      toolStubs: [BREAKOUT_WK40_INFERTILE_ONLY],
      assertions: [
        argumentsValidForTool('get_egg_breakout_benchmark'),
        toolCalledWithArgs(
          'get_egg_breakout_benchmark',
          (args) => args.ageWeek === 40,
          'ageWeek=40 as an integer',
        ),
      ],
    }],
  },
]

export type { AgentModelInputItem, FunctionCallItem, ToolStub, TurnResult }
