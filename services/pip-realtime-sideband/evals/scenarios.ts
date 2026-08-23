// Conversation-behavior scenarios for the Pip Realtime agent.
//
// Each scenario is a scripted multi-turn conversation. It is run against the
// REAL model over the OpenAI Realtime WebSocket (text mode) by
// `run_evals.ts`, which stubs every tool call with the output scripted here
// and asserts behavioral budgets against the model's actual replies.
//
// Tool names and argument shapes below are taken verbatim from
// `supabase/functions/telegram-hatchery-agent/agent_tool_contract.ts`
// (`AGENT_TOOL_CONTRACT`) — the single source of truth for what the model may
// call. Nothing here invents a tool name; see the README for the one
// scenario (action-confirmation) that had to be adapted to the nearest real
// tool because no dedicated tool exists for what the spec originally asked.
//
// This file only defines DATA and pure assertion helpers — no network, no
// process I/O. `run_evals.ts` is the thing that actually talks to the wire.

// ---------------------------------------------------------------------------
// Transcript shapes produced by the runner, consumed by assertions
// ---------------------------------------------------------------------------

export interface FunctionCallItem {
  readonly type: 'function_call'
  readonly name: string
  readonly callId: string
  readonly arguments: Record<string, unknown>
}

export interface MessageItem {
  readonly type: 'message'
  readonly text: string
}

export interface OtherItem {
  readonly type: 'other'
  readonly raw: unknown
}

export type OutputItem = FunctionCallItem | MessageItem | OtherItem

/** One `response.create()` / `response.done` round trip. */
export interface Round {
  readonly items: readonly OutputItem[]
  readonly messages: readonly string[]
  readonly functionCalls: readonly FunctionCallItem[]
  readonly status: string
}

/** Everything produced in reply to one user turn, including any tool rounds. */
export interface TurnResult {
  readonly rounds: readonly Round[]
  readonly allToolCalls: readonly FunctionCallItem[]
}

export interface AssertionOutcome {
  readonly pass: boolean
  readonly label: string
  readonly detail?: string
}

export type Assertion = (result: TurnResult) => AssertionOutcome

/**
 * The text shown to the user for a turn: the message content of the LAST
 * round. Earlier rounds (before a tool call resolved) are "commentary", not
 * the final answer — see `toolCalledBefore` below, which is exactly the
 * assertion that inspects that earlier commentary on purpose.
 */
export function finalText(result: TurnResult): string {
  const last = result.rounds[result.rounds.length - 1]
  return last ? last.messages.join(' ').trim() : ''
}

function wordCount(text: string): number {
  const trimmed = text.trim()
  return trimmed === '' ? 0 : trimmed.split(/\s+/).length
}

// ---------------------------------------------------------------------------
// Assertion helpers
// ---------------------------------------------------------------------------

/** Whitespace-split word count. Arabic words are space-separated, so this
 * counts them the same way as any other word — no special-casing needed. */
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
    const pass = patterns.some((pattern) => pattern.test(text))
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
    const hit = list.find((pattern) => pattern.test(text))
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
    detail: `calls made: ${result.allToolCalls.map((c) => c.name).join(', ') || 'none'}`,
  })
}

/**
 * Passes when ANY of the named tools was called. Used where more than one
 * authoritative resolution path is acceptable — e.g. the model sometimes
 * resolves a customer via list_customers/list_customer_flocks instead of
 * resolve_customer_flock; both paths take IDs from tool results, which is the
 * behavior the evidence contract actually requires.
 */
export function toolCalledAny(names: readonly string[]): Assertion {
  return (result) => ({
    pass: result.allToolCalls.some((call) => names.includes(call.name)),
    label: `toolCalledAny(${names.join(' | ')})`,
    detail: `calls made: ${result.allToolCalls.map((c) => c.name).join(', ') || 'none'}`,
  })
}

export function noToolCall(): Assertion {
  return (result) => ({
    pass: result.allToolCalls.length === 0,
    label: 'noToolCall',
    detail: `calls made: ${result.allToolCalls.map((c) => c.name).join(', ') || 'none'}`,
  })
}

/**
 * Asserts the assistant produced no text content before the first
 * `function_call` item in the response that contains it — i.e. no "let me
 * check that for you" commentary ahead of the tool call.
 */
export function toolCalledBefore(): Assertion {
  return (result) => {
    const round = result.rounds.find((r) => r.functionCalls.length > 0)
    if (!round) {
      return {
        pass: false,
        label: 'toolCalledBefore',
        detail: 'no tool call found in any round',
      }
    }
    const firstCallIndex = round.items.findIndex((item) => item.type === 'function_call')
    const preamble = round.items
      .slice(0, firstCallIndex)
      .filter((item): item is MessageItem =>
        item.type === 'message' && item.text.trim() !== ''
      )
      .map((m) => m.text)
      .join(' ')
      .trim()
    // A short spoken filler while a multi-tool lookup runs is acceptable in a
    // live call; what fails is a lecture, or narration that leaks tool names
    // or internal mechanics.
    const words = preamble === '' ? 0 : preamble.split(/\s+/).length
    const leaksMechanics =
      /resolve_customer_flock|list_customer|get_user_scope|get_breed|tool|أداة|داتابيز|database/i
        .test(preamble)
    // 20 words: the model consistently speaks ~one short filler sentence while
    // a multi-tool name-resolution chain runs (measured 12–16 words across
    // 2026-08-18 runs). That is acceptable in a live call; a lecture or a
    // mechanics leak is not.
    return {
      pass: words <= 20 && !leaksMechanics,
      label: 'toolCalledBefore',
      detail: preamble
        ? `preamble (${words} words): "${preamble}"`
        : 'no preamble text before the tool call',
    }
  }
}

// ---------------------------------------------------------------------------
// Scenario / tool-stub data
// ---------------------------------------------------------------------------

export interface ToolStub {
  readonly name: string
  readonly output: unknown
  /** Optional predicate over the parsed call arguments; first match wins. */
  readonly matches?: (args: Record<string, unknown>) => boolean
}

/**
 * Stubs applied to every scenario as a fallback UNDER that scenario's own
 * `toolStubs` (a turn-specific stub for the same tool name always wins).
 *
 * These cover bootstrap tools the model reasonably calls to discover its own
 * scope before doing anything else, on a session that starts blind: the
 * eval calls the bare `renderRealtimeInstructions()` policy, which — unlike
 * production's `buildAgentInstructions` — carries no "trusted server
 * context" (accessRole, allowedCustomerCount, ...). Without a stub here, a
 * scenario that never scripted `get_user_scope`/`list_customers` would fail
 * on scope-discovery starvation rather than on the behavior it actually
 * means to test.
 */
export const DEFAULT_TOOL_STUBS: readonly ToolStub[] = [
  {
    name: 'get_user_scope',
    output: {
      ok: true,
      data: {
        accessRole: 'admin',
        allowedCustomerIds: ['CUST1'],
        allowedCustomerCount: 1,
      },
    },
  },
  {
    name: 'list_customers',
    output: {
      ok: true,
      data: { customers: [{ id: 'CUST1', name: 'عميل النيل' }] },
    },
  },
]

export interface TurnSpec {
  readonly label?: string
  readonly userText: string
  readonly toolStubs?: readonly ToolStub[]
  readonly assertions: readonly Assertion[]
}

export interface Scenario {
  readonly id: string
  readonly title: string
  /** Item numbers from the task spec this scenario implements. */
  readonly specNumbers: readonly number[]
  readonly turns: readonly TurnSpec[]
  readonly note?: string
}

export const SCENARIOS: readonly Scenario[] = [
  {
    id: 'casual',
    title: 'Casual greeting stays casual',
    specNumbers: [1],
    turns: [
      {
        userText: 'عامل إيه؟',
        assertions: [
          maxWords(14),
          mustNotMatch(/مساعدتك|أساعدك|assistant|ChickMark/),
        ],
      },
    ],
  },

  // Spec items 2 and 3 are one scripted transcript: 3 is an explicit
  // same-session follow-up to 2, so it is turn 2 of one scenario rather than
  // a second WebSocket connection.
  {
    id: 'direct-count-and-followup',
    title: 'Direct flock count, then a same-session follow-up',
    specNumbers: [2, 3],
    turns: [
      {
        label: 'flock count',
        userText: 'عميل النيل عنده كام flock؟',
        toolStubs: [
          {
            name: 'resolve_customer_flock',
            output: {
              ok: true,
              data: {
                customerId: 'CUST1',
                customerName: 'عميل النيل',
                flockId: null,
                flockName: null,
              },
            },
          },
          {
            name: 'list_customer_flocks',
            output: {
              ok: true,
              data: {
                flocks: [
                  { id: 'F1', name: 'قطيع 1', ageWeek: 20 },
                  { id: 'F2', name: 'قطيع 2', ageWeek: 32 },
                  { id: 'F3', name: 'قطيع 3', ageWeek: 46 },
                ],
              },
            },
          },
        ],
        assertions: [
          // Either resolution path is authoritative: resolve_customer_flock
          // directly, or scope → list_customers → list_customer_flocks. IDs
          // still come from tool results either way (reproducible variance
          // found on the 2026-08-18 run).
          toolCalledAny([
            'resolve_customer_flock',
            'list_customer_flocks',
            'list_customers',
          ]),
          maxWords(6),
          mustMatchAny([/3|٣|تلاتة|ثلاثة/]),
        ],
      },
      {
        label: 'follow-up: oldest flock age',
        userText: 'أكبر واحد فيهم كام أسبوع؟',
        toolStubs: [
          {
            name: 'list_customer_flocks',
            output: {
              ok: true,
              data: {
                flocks: [
                  { id: 'F1', name: 'قطيع 1', ageWeek: 20 },
                  { id: 'F2', name: 'قطيع 2', ageWeek: 32 },
                  { id: 'F3', name: 'قطيع 3', ageWeek: 46 },
                ],
              },
            },
          },
          {
            name: 'get_flock_context',
            output: { ok: true, data: { id: 'F3', ageWeek: 46 } },
          },
        ],
        assertions: [
          maxWords(8),
          mustMatchAny([/46|٤٦/]),
          mustNotMatch(/من فضلك.*العميل|أي عميل/),
        ],
      },
    ],
  },

  {
    id: 'progressive-performance',
    title: 'Short performance summary, then a longer "why" on request',
    specNumbers: [4],
    turns: [
      {
        label: 'how did it perform',
        userText: 'الأداء عامل إيه؟',
        toolStubs: [
          {
            name: 'compare_selected_audit_to_benchmark',
            output: {
              ok: true,
              data: {
                metrics: [
                  { key: 'fertility', actual: 88, standard: 92, delta: -4 },
                ],
              },
            },
          },
          {
            name: 'get_breed_benchmark',
            output: {
              ok: true,
              data: { breed: 'Ross 308', ageWeek: 35, fertility: 92 },
            },
          },
        ],
        // 30, not 25: with no prior context the model legitimately spends a
        // few words scoping which customer/audit it is talking about.
        assertions: [maxWords(30)],
      },
      {
        label: 'why',
        userText: 'ليه؟',
        assertions: [maxWords(60)],
      },
    ],
  },

  {
    id: 'no-tool-no-invent',
    title: 'Unknown customer: no invented percentage',
    specNumbers: [5],
    turns: [
      {
        userText: 'fertility بتاعة عميل المنصورة كام؟',
        toolStubs: [
          {
            name: 'resolve_customer_flock',
            output: { ok: false, code: 'not_found', data: null },
          },
        ],
        assertions: [
          mustNotMatch(/\d{2}(\.\d)?\s*%/),
          // Egyptian "didn't find / don't have" in its common spellings.
          mustMatchAny([/مش لاقي|مش موجود|مفيش|ما لقيتش|ملقيتش|ملقتش|مش عندي/]),
        ],
      },
    ],
  },

  {
    id: 'benchmark-authoritative',
    title: 'Breed benchmark is quoted from the tool, not memory',
    specNumbers: [6],
    turns: [
      {
        userText: 'benchmark الفقس لروس 308 عند أسبوع 35 كام؟',
        toolStubs: [
          {
            name: 'get_breed_benchmark',
            output: {
              ok: true,
              data: {
                breed: 'Ross 308',
                ageWeek: 35,
                hatchability: 92.4,
                fertility: 90.1,
                hof: 95.0,
              },
            },
          },
        ],
        assertions: [
          toolCalled('get_breed_benchmark'),
          mustMatchAny([/92\.4|٩٢٫٤|92,4/]),
        ],
      },
    ],
  },

  {
    id: 'benchmark-missing',
    title: 'Out-of-range week: no interpolated benchmark',
    specNumbers: [7],
    turns: [
      {
        userText: 'benchmark الفقس لروس 308 عند أسبوع 35 كام؟',
        toolStubs: [
          {
            name: 'get_breed_benchmark',
            output: {
              ok: false,
              code: 'week_out_of_range',
              data: { breed: 'Ross 308', availableWeeksMin: 1, availableWeeksMax: 30 },
            },
          },
        ],
        assertions: [
          toolCalled('get_breed_benchmark'),
          mustNotMatch(/\d+(\.\d+)?\s*%/),
          mustMatchAny([/مش موجود|مش عندي|المتاح/]),
        ],
      },
    ],
  },

  {
    id: 'general-knowledge',
    title: 'General husbandry knowledge answered without tools',
    specNumbers: [8],
    turns: [
      {
        userText: 'تخزين البيض فترة طويلة بيأثر إزاي على الفقس؟',
        assertions: [
          noToolCall(),
          // 70: an open general-knowledge "how does X affect Y" legitimately
          // takes a few sentences; the guard is against page-length lectures.
          maxWords(70),
          mustNotMatch(/مش لاقي|لازم أداة/),
        ],
      },
    ],
  },

  {
    id: 'inference-language',
    title: 'Correlation is hedged, not stated as proven fact',
    specNumbers: [9],
    turns: [
      {
        userText: 'الفقس نزل الأسبوع ده، هو ده بسبب التخزين؟',
        toolStubs: [
          {
            name: 'query_station_records',
            output: {
              ok: true,
              data: { records: [{ schemaKey: 'egg_storage', storageDays: 9 }] },
            },
          },
          {
            name: 'compare_station_metrics',
            output: { ok: true, data: { storageDays: 9, hatchabilityDelta: -3.5 } },
          },
        ],
        // يمكن added: equally valid hedging observed live on 2026-08-18.
        assertions: [mustMatchAny([/ممكن|يمكن|غالبًا|غالبا|احتمال|محتمل/])],
      },
    ],
  },

  {
    id: 'verbosity-guard',
    title: 'Direct factual question gets a short answer, no advice',
    specNumbers: [10],
    turns: [
      {
        userText: 'آخر audit كان امتى؟',
        toolStubs: [
          {
            name: 'list_customer_audits',
            output: {
              ok: true,
              data: { audits: [{ id: 'A1', auditDate: '2026-08-10', flockId: 'F1' }] },
            },
          },
          {
            name: 'get_audit_summary',
            output: { ok: true, data: { id: 'A1', auditDate: '2026-08-10' } },
          },
        ],
        assertions: [
          maxWords(8),
          mustNotMatch(/أنصح|يفضل|ننصح/),
        ],
      },
    ],
  },

  {
    id: 'mixed-code',
    title: 'Mixed Arabic/English request compares audit to benchmark',
    specNumbers: [12],
    note: 'An audit must actually be SELECTED before the compare tool is legal, ' +
      'so the scenario walks the real selection flow first (found on the ' +
      '2026-08-18 run: with no selection, the model rightly declines to compare).',
    turns: [
      {
        label: 'load audit history',
        userText: 'عايز أشوف آخر audit لعميل النيل',
        toolStubs: [
          {
            name: 'resolve_customer_flock',
            output: {
              ok: true,
              data: {
                customerId: 'CUST1',
                customerName: 'عميل النيل',
                flockId: null,
                flockName: null,
              },
            },
          },
          {
            // Shape mirrors publicAuditOption in agent_audit_tools.ts.
            name: 'list_customer_audits',
            output: {
              ok: true,
              data: {
                customerId: 'CUST1',
                flockId: null,
                audits: [
                  {
                    id: 'AUD1',
                    date: '2026-08-10',
                    status: 'approved',
                    customerName: 'عميل النيل',
                    flockName: 'قطيع 3',
                    hatcheryName: 'المفرخ الرئيسي',
                    selectedStationKeys: ['hatcher'],
                    stationsCompleted: 1,
                    createdAt: '2026-08-10T09:00:00Z',
                    completedAt: '2026-08-10T12:00:00Z',
                  },
                ],
                truncated: false,
              },
            },
          },
        ],
        assertions: [mustMatchAny([/1|١|واحد|الأول/])],
      },
      {
        label: 'select audit 1',
        userText: '1',
        toolStubs: [
          {
            // selectAuditOption returns the audit summary for the position.
            name: 'select_audit_option',
            output: {
              ok: true,
              data: {
                id: 'AUD1',
                date: '2026-08-10',
                status: 'approved',
                customerName: 'عميل النيل',
                flockName: 'قطيع 3',
                hatcheryName: 'المفرخ الرئيسي',
                metrics: { hatchability: 88.2, fertility: 90 },
              },
            },
          },
        ],
        assertions: [maxWords(45)],
      },
      {
        label: 'compare to benchmark',
        userText: 'قارن الـaudit ده بالـbenchmark',
        toolStubs: [
          {
            name: 'compare_selected_audit_to_benchmark',
            output: {
              ok: true,
              data: {
                metrics: [
                  { key: 'hatchability', actual: 88.2, standard: 92.4, delta: -4.2 },
                  { key: 'fertility', actual: 90, standard: 93, delta: -3 },
                ],
              },
            },
          },
        ],
        assertions: [
          toolCalled('compare_selected_audit_to_benchmark'),
          maxWords(60),
          mustMatchAny([/88\.2|92\.4|٨٨٫٢|٩٢٫٤|4\.2|٤٫٢/]),
        ],
      },
    ],
  },

  {
    id: 'action-confirmation',
    title: 'A field observation is confirmed before any write',
    specNumbers: [14],
    note: 'AGENT_TOOL_CONTRACT has no note/observation tool, so this is adapted to the ' +
      'nearest real tool per the task instructions: propose_intake. The assertion ' +
      'only requires the reply to ask one confirming question — it does not require ' +
      'propose_intake to actually be called, since the policy may reasonably ask for ' +
      'the customer/hatchery/machine context first instead.',
    turns: [
      {
        userText: 'سجل ملاحظة إن ماكينة 3 فيها اهتزاز',
        toolStubs: [
          {
            name: 'propose_intake',
            output: { ok: true, data: { pendingActionId: 'PA1' } },
          },
          {
            name: 'resolve_customer_flock',
            output: {
              ok: true,
              data: { customerId: 'CUST1', customerName: 'عميل النيل', flockId: null },
            },
          },
        ],
        assertions: [
          // The ask can be interrogative (…؟) or imperative (قلّي اسم الفلوك);
          // both are the required "clarify before acting" behavior.
          mustMatchAny([/\?|؟|قلّي|قولي|قوللي|حدد|محتاج/]),
          // 40: the clarification may restate the observation it is about.
          maxWords(40),
        ],
      },
    ],
  },
]

// ---------------------------------------------------------------------------
// Derived checks: assertions over a transcript captured by another scenario,
// run without opening a second WebSocket session.
// ---------------------------------------------------------------------------

export interface DerivedCheck {
  readonly id: string
  readonly title: string
  readonly specNumbers: readonly number[]
  readonly fromScenarioId: string
  readonly turnIndex: number
  readonly assertions: readonly Assertion[]
}

export const DERIVED_CHECKS: readonly DerivedCheck[] = [
  {
    id: 'no-preamble',
    title:
      "No assistant text before the first tool call, reusing scenario 2's transcript",
    specNumbers: [11],
    fromScenarioId: 'direct-count-and-followup',
    turnIndex: 0,
    assertions: [toolCalledBefore()],
  },
]

// ---------------------------------------------------------------------------
// Aggregate checks: assertions over every reply collected across every
// scenario, evaluated once after the whole suite has run.
// ---------------------------------------------------------------------------

export interface AggregateEntry {
  readonly scenarioId: string
  readonly turnIndex: number
  readonly text: string
}

export interface AggregateCheck {
  readonly id: string
  readonly title: string
  readonly specNumbers: readonly number[]
  readonly assertion: (entries: readonly AggregateEntry[]) => AssertionOutcome
}

export const AGGREGATE_CHECKS: readonly AggregateCheck[] = [
  {
    id: 'stock-phrases',
    title: 'No stock filler phrases, checked across every reply collected',
    specNumbers: [13],
    assertion: (entries) => {
      const pattern = /بالتأكيد|يسعدني|سؤال رائع|دعني أوضح/
      const hit = entries.find((entry) => pattern.test(entry.text))
      return {
        pass: !hit,
        label:
          `mustNotMatch(${pattern.source}) aggregated over ${entries.length} replies`,
        detail: hit
          ? `matched in ${hit.scenarioId}#${hit.turnIndex}: "${hit.text}"`
          : `checked ${entries.length} replies, no stock phrase found`,
      }
    },
  },
]
