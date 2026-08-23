// Production-path canary evals for Pip Live (Harness v2).
//
// WHY THIS EXISTS: run_evals.ts talks to the model in TEXT mode
// (output_modalities:['text'], no audio config, no reasoning knob). Production
// sessions run AUDIO output with the sideband's full session.update —
// reasoning effort, semantic_vad, transcription, voice. The 2026-08-18
// screenshot failures reproduced on the phone while the text evals were
// green: text-mode passing is NOT evidence about the spoken channel.
//
// This runner therefore sends the EXACT production session payload — built by
// the same `buildSessionUpdate` the Cloud Run sideband uses, from the same
// rendered instructions and tool definitions — and asserts on the AUDIO
// transcript of what the model speaks. User turns are typed text (synthesizing
// caller audio is not practical here); that is the one remaining gap, and it
// biases the model TOWARD text-register verbosity, so a canary that passes
// here can still be believed for voice brevity.
//
//   export OPENAI_API_KEY="$(gcloud secrets versions access latest \
//     --secret=openai-api-key --project=chickmark-ai-agent)"
//   deno run --allow-net --allow-env evals/run_canaries.ts [--filter substring]
//
// Keep this suite SMALL (single-digit scenarios). It is the fast, cheap gate
// that runs before/instead of the 47-case behavior suite.

import { WebSocket as NodeWebSocket } from 'ws'
import { buildSessionUpdate } from '../src/session_config.ts'
import { testConfig } from '../src/config.ts'

const OPENAI_REALTIME_URL = 'wss://api.openai.com/v1/realtime'
const MODEL = 'gpt-realtime-2.1-mini'
const EVENT_TIMEOUT_MS = 60_000
const MAX_TOOL_ROUNDS = 6
const INTER_SCENARIO_DELAY_MS = 4000

// ---------------------------------------------------------------------------
// Instructions + tools (same loaders as run_evals.ts)
// ---------------------------------------------------------------------------

interface FlatToolDefinition {
  readonly type: 'function'
  readonly name: string
  readonly description: string
  readonly parameters: Record<string, unknown>
}

async function loadInstructions(): Promise<{ text: string; version: string }> {
  const mod = await import('../tools/render_agent_instructions.ts') as Record<
    string,
    unknown
  >
  const fn = mod['renderRealtimeInstructions']
  if (typeof fn !== 'function') throw new Error('renderRealtimeInstructions missing')
  const text = String((fn as () => string)())
  const versionKey = Object.keys(mod).find(
    (key) => /VERSION/i.test(key) && typeof mod[key] === 'string',
  )
  return { text, version: versionKey ? String(mod[versionKey]) : 'unknown' }
}

async function loadTools(): Promise<readonly FlatToolDefinition[]> {
  const mod = await import('../tools/render_tool_definitions.ts') as Record<
    string,
    unknown
  >
  const fn = mod['renderRealtimeToolDefinitions']
  if (typeof fn !== 'function') throw new Error('renderRealtimeToolDefinitions missing')
  return (fn as () => readonly FlatToolDefinition[])()
}

// ---------------------------------------------------------------------------
// Scenario shapes
// ---------------------------------------------------------------------------

interface ToolStub {
  readonly name: string
  readonly output: unknown | ((args: Record<string, unknown>) => unknown)
}

/**
 * Per-turn state beyond the spoken reply, handed to every assertion so
 * checks can look at what tools were called and what the turn cost —
 * without re-parsing response.done events themselves.
 */
interface TurnMeta {
  readonly calls: readonly FunctionCall[]
  readonly outputTokens: number
  readonly status: string | undefined
}

interface Assertion {
  readonly label: string
  readonly check: (
    reply: string,
    priorReplies: readonly string[],
    meta: TurnMeta,
  ) => string | null
}

interface CanaryTurn {
  readonly userText: string
  readonly label: string
  readonly toolStubs?: readonly ToolStub[]
  readonly assertions: readonly Assertion[]
  // Run against everything spoken across every tool round of this turn (not
  // just the final reply) — for asserting on things that must never be said
  // mid-lookup, such as filler before a tool call resolves.
  readonly allSpeechAssertions?: readonly Assertion[]
}

interface Canary {
  readonly id: string
  readonly turns: readonly CanaryTurn[]
}

const ASSISTANT_SERVICE_PATTERN =
  /مستعد للمتابعة|لو عندك (حاجة|سؤال)|وأنا معاك|كيف يمكنني مساعدتك|هل هناك شيء آخر|دعني أساعدك|يسعدني مساعدتك|قل لي البيانات|بالتفصيل/

function wordCount(text: string): number {
  return text.trim().split(/\s+/).filter(Boolean).length
}

function maxWords(limit: number) {
  return {
    label: `maxWords(${limit})`,
    check: (reply: string) =>
      wordCount(reply) <= limit ? null : `got ${wordCount(reply)} words`,
  }
}

function noAssistantServiceLanguage() {
  return {
    label: 'noAssistantServiceLanguage',
    check: (reply: string) => {
      const match = reply.match(ASSISTANT_SERVICE_PATTERN)
      return match ? `contains "${match[0]}"` : null
    },
  }
}

function atMostOneQuestion() {
  return {
    label: 'atMostOneQuestion',
    check: (reply: string) => {
      const count = (reply.match(/[?؟]/g) ?? []).length
      return count <= 1 ? null : `${count} question marks`
    },
  }
}

function mustNotMatch(pattern: RegExp, label: string) {
  return {
    label,
    check: (reply: string) => {
      const match = reply.match(pattern)
      return match ? `contains "${match[0]}"` : null
    },
  }
}

function mustMatch(pattern: RegExp, label: string) {
  return {
    label,
    check: (reply: string) => pattern.test(reply) ? null : `no match for ${pattern}`,
  }
}

// ---------------------------------------------------------------------------
// Tool-call assertions (metrics/report-routing canaries) — operate on the
// FunctionCall list the transport already collected for the turn, not on
// the spoken reply.
// ---------------------------------------------------------------------------

function toolCalled(name: string): Assertion {
  return {
    label: `toolCalled(${name})`,
    check: (_reply, _prior, meta) =>
      meta.calls.some((call) => call.name === name) ? null : `${name} was not called`,
  }
}

function toolNotCalled(name: string): Assertion {
  return {
    label: `toolNotCalled(${name})`,
    check: (_reply, _prior, meta) =>
      meta.calls.some((call) => call.name === name) ? `${name} was called` : null,
  }
}

/** Asserts `name` was called with a raw `arguments` JSON string containing `substring` (case-insensitive). */
function toolCalledWithArgumentContaining(name: string, substring: string): Assertion {
  const needle = substring.toLowerCase()
  return {
    label: `toolCalledWithArgumentContaining(${name}, "${substring}")`,
    check: (_reply, _prior, meta) => {
      const match = meta.calls.some((call) =>
        call.name === name && call.rawArguments.toLowerCase().includes(needle)
      )
      return match
        ? null
        : `${name} was not called with arguments containing "${substring}"`
    },
  }
}

function maxOutputTokens(limit: number): Assertion {
  return {
    label: `maxOutputTokens(${limit})`,
    check: (_reply, _prior, meta) =>
      meta.outputTokens <= limit
        ? null
        : `output tokens ${meta.outputTokens} exceeds ${limit}`,
  }
}

/** A max_output_tokens truncation arrives with status 'incomplete' — a legitimate answer must always finish as 'completed'. */
function respondedCompletely(): Assertion {
  return {
    label: 'respondedCompletely',
    check: (_reply, _prior, meta) =>
      meta.status === 'completed' ? null : `response status was "${meta.status}"`,
  }
}

// ---------------------------------------------------------------------------
// Number-matching helpers — the breakout canaries below need to ban a
// handful of sibling metric values from a shaped payload's `context`, in
// both Western and Arabic-Indic digit forms with any decimal separator the
// model might speak, same convention as the hand-written patterns above.
// ---------------------------------------------------------------------------

const ARABIC_INDIC_DIGITS = '٠١٢٣٤٥٦٧٨٩'

function toArabicIndicDigits(value: string): string {
  return value.replace(/[0-9]/g, (digit) => ARABIC_INDIC_DIGITS[Number(digit)])
}

/** `"6.2"` -> a regex-alternation fragment matching it in Western or Arabic-Indic digits, any decimal separator. */
function numberVariants(value: string): string {
  const [intPart, fracPart] = value.split('.')
  const western = fracPart ? `${intPart}[.,٫]${fracPart}` : intPart
  const arabic = fracPart
    ? `${toArabicIndicDigits(intPart)}[.,٫]${toArabicIndicDigits(fracPart)}`
    : toArabicIndicDigits(intPart)
  return `${western}|${arabic}`
}

function mustNotMatchAnyNumber(values: readonly string[], label: string): Assertion {
  return mustNotMatch(new RegExp(values.map(numberVariants).join('|')), label)
}

const FULL_BENCHMARK_ROW = {
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
  },
}

// The flat egg-breakout benchmark row (no `metrics` arg) — mirrors
// FULL_BENCHMARK_ROW's shape for get_breed_benchmark. Field names match
// BmkEggBreakoutBenchmarkRow / BREAKOUT_REQUESTABLE_METRICS in
// supabase/functions/telegram-hatchery-agent/bmk_tools.ts.
const FULL_BREAKOUT_ROW = {
  ok: true,
  code: 'ok',
  data: {
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
}

// Same eleven values, reused as the `context` block of a shaped
// get_egg_breakout_benchmark response (the `requested`/`unavailable`/
// `unknownMetrics` payload the tool now returns when a `metrics` arg is
// given). Kept as a separate literal from FULL_BREAKOUT_ROW.data so a
// canary can freely null out one field without touching the flat-row fixture.
const FULL_BREAKOUT_CONTEXT = {
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
}

// All eleven breakout percentages as strings, for building
// mustNotMatchAnyNumber patterns per-canary (each canary excludes whichever
// values it legitimately states).
const BREAKOUT_METRIC_VALUES: Record<string, string> = {
  infertile: '6.2',
  early_24h: '1.4',
  early_48h: '1.1',
  blood_ring: '0.8',
  black_eye: '0.6',
  early_dead: '2.3',
  mid_dead: '1.2',
  late_dead: '3.1',
  external_pip: '1.7',
  cracked: '0.9',
  contaminated: '0.5',
}

function siblingValues(exclude: readonly string[]): readonly string[] {
  return Object.entries(BREAKOUT_METRIC_VALUES)
    .filter(([key]) => !exclude.includes(key))
    .map(([, value]) => value)
}

const CANARIES: readonly Canary[] = [
  {
    id: 'greeting',
    turns: [{
      userText: 'صباح الفل',
      label: 'صباح الفل',
      assertions: [maxWords(7), noAssistantServiceLanguage(), atMostOneQuestion()],
    }, {
      userText: 'صباح الفل',
      label: 'repeated صباح الفل',
      assertions: [
        maxWords(7),
        noAssistantServiceLanguage(),
        atMostOneQuestion(),
        {
          label: 'notCannedRepeat',
          check: (reply, prior) =>
            prior.length > 0 && reply.trim() === prior[prior.length - 1].trim()
              ? 'verbatim repeat of previous greeting'
              : null,
        },
      ],
    }],
  },
  {
    id: 'clarification-hubbard-wk40',
    turns: [{
      userText: 'عايز أنتج قطيع هبرد في الأسبوع الأربعين',
      label: 'hubbard wk40',
      // 25: one short sentence plus one short question is acceptable; the
      // production failure this guards against was a 45+-word multi-question
      // paragraph.
      assertions: [
        maxWords(25),
        atMostOneQuestion(),
        noAssistantServiceLanguage(),
        mustNotMatch(
          /هل هي إدخال|أو حاجة تانية\؟.*\؟|اسم المفرخ.*الماكينة|الماكينة.*المفرخ/,
          'noBatchedFieldList',
        ),
      ],
    }],
  },
  {
    id: 'direct-count',
    turns: [{
      userText: 'عميل Rs-NileV عنده كام flock؟',
      label: 'flock count',
      toolStubs: [
        {
          name: 'resolve_customer_flock',
          output: {
            ok: true,
            data: { customer: { id: 'cust_rs_nilev', name: 'Rs-NileV' }, flock: null },
          },
        },
        {
          name: 'list_customer_flocks',
          output: {
            ok: true,
            data: {
              flocks: [
                { id: 'f1', name: 'Rs-NileV-A' },
                { id: 'f2', name: 'Rs-NileV-B' },
                { id: 'f3', name: 'Rs-NileV-C' },
              ],
              count: 3,
            },
          },
        },
      ],
      assertions: [
        maxWords(8),
        noAssistantServiceLanguage(),
        mustMatch(/3|٣|ثلاث|تلات/, 'statesThree'),
      ],
    }],
  },
  {
    id: 'progressive-disclosure',
    turns: [{
      userText: 'الأداء عامل إيه؟',
      label: 'الأداء عامل إيه؟',
      assertions: [maxWords(30), atMostOneQuestion(), noAssistantServiceLanguage()],
    }, {
      userText: 'ليه؟',
      label: 'ليه؟ follow-up',
      assertions: [noAssistantServiceLanguage()],
    }],
  },
  {
    id: 'missing-benchmark',
    turns: [{
      userText: 'إيه معيار الإنتاج لسلالة روس في الأسبوع التسعين؟',
      label: 'ross wk90 (out of range)',
      toolStubs: [{
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
      }],
      assertions: [
        maxWords(25),
        noAssistantServiceLanguage(),
        mustNotMatch(
          /\d+([.,]\d+)?\s*(٪|%|في المية|بالمية|في المئة)/,
          'noInventedPercentage',
        ),
      ],
    }],
  },
  {
    id: 'casual-offtopic',
    turns: [{
      userText: 'يومك عامل إيه؟',
      label: 'يومك عامل إيه؟',
      assertions: [
        maxWords(15),
        noAssistantServiceLanguage(),
        mustNotMatch(
          /لا أستطيع|أقدر أساعدك فقط|خارج نطاق|مخصص لعمليات/,
          'noSupportBotDeflection',
        ),
      ],
    }],
  },
  {
    id: 'single-metric-scope',
    turns: [{
      userText: 'إنتاج Hubbard في الأسبوع 40 كام؟',
      label: 'production only',
      toolStubs: [{ name: 'get_breed_benchmark', output: FULL_BENCHMARK_ROW }],
      assertions: [
        maxWords(15),
        atMostOneQuestion(),
        noAssistantServiceLanguage(),
        mustMatch(/80|٨٠|ثمانين|تمانين/, 'statesProductionValue'),
        mustNotMatch(
          /hatchability|فقس|خصوب|فرتيل|fertility|HOF|هوف|90[.,٫]2|٩٠[.,٫]٢|96[.,٫]5|٩٦[.,٫]٥|93[.,٫]47|٩٣[.,٫]٤٧|65[.,٫]3|٦٥[.,٫]٣/i,
          'noSiblingMetrics',
        ),
      ],
      allSpeechAssertions: [
        mustNotMatch(
          /ثانية أشوف|لحظة|ثواني|خليني أشوف|استنى|دقيقة|هشوف دلوقتي/,
          'noLookupFiller',
        ),
      ],
    }],
  },
  {
    id: 'two-metrics-scope',
    turns: [{
      userText: 'قولي الخصوبة ونسبة الفقس لهبرد في الأسبوع 40',
      label: 'fertility + hatchability',
      toolStubs: [{ name: 'get_breed_benchmark', output: FULL_BENCHMARK_ROW }],
      assertions: [
        maxWords(25),
        noAssistantServiceLanguage(),
        mustMatch(/96[.,٫]5|٩٦[.,٫]٥/, 'statesFertility'),
        mustMatch(/90[.,٫]2|٩٠[.,٫]٢/, 'statesHatchability'),
        mustNotMatch(
          /HOF|هوف|93[.,٫]47|٩٣[.,٫]٤٧|إنتاج 80|الإنتاج/i,
          'noUnrequestedMetrics',
        ),
      ],
    }],
  },
  {
    id: 'full-summary-allowed',
    turns: [{
      // Latin breed name on purpose: this canary tests the full-summary
      // allowance, not the Arabic-transliteration flow (that ambiguity made
      // the model ask a breed-confirmation question instead of summarizing).
      userText: 'إديني ملخص أداء Hubbard كامل في الأسبوع 40',
      label: 'explicit full summary',
      toolStubs: [{ name: 'get_breed_benchmark', output: FULL_BENCHMARK_ROW }],
      assertions: [
        noAssistantServiceLanguage(),
        {
          label: 'atLeastThreeMetrics',
          check: (reply: string) => {
            const hits = [/80|٨٠/, /90[.,٫]2/, /96[.,٫]5/, /93[.,٫]/, /65[.,٫]3/, /46|٤٦/]
              .filter((pattern) => pattern.test(reply)).length
            return hits >= 3 ? null : `only ${hits} metrics present`
          },
        },
      ],
    }],
  },
  {
    id: 'missing-metric-value',
    turns: [{
      userText: 'إنتاج Hubbard في الأسبوع 40 كام؟',
      label: 'production null in row',
      toolStubs: [{
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
            productionPct: null,
            eggWeightG: 65.3,
            chickWeightG: 46,
            // Mirrors the real tool since contract 1.1.0: null metrics are
            // also named explicitly, because a bare JSON null was not salient
            // enough for the mini model (it parroted a calibration-example
            // number instead of saying the value is unavailable).
            unavailable: ['production'],
          },
        },
      }],
      assertions: [
        maxWords(20),
        noAssistantServiceLanguage(),
        mustNotMatch(
          /90[.,٫]2|٩٠[.,٫]٢|96[.,٫]5|٩٦[.,٫]٥|93[.,٫]47|٩٣[.,٫]٤٧|65[.,٫]3|٦٥[.,٫]٣/,
          'noSiblingSubstitution',
        ),
        mustNotMatch(
          /\d+([.,٫]\d+)?\s*(٪|%|في المية|بالمية|في المئة)/,
          'noInventedPercentage',
        ),
        mustMatch(
          /مش متاح|غير متاح|مش موجود|مالقيتش|مش لاقي|مش متوفر|غير متوفر/,
          'saysUnavailable',
        ),
        mustNotMatch(/84|٨٤|95|٩٥|88|٨٨/, 'noCalibrationExampleNumbers'),
      ],
    }],
  },
  {
    id: 'shaped-null-metric',
    turns: [{
      userText: 'إنتاج Hubbard في الأسبوع 40 كام؟',
      label: 'shaped payload, production null',
      toolStubs: [{
        name: 'get_breed_benchmark',
        output: (args: Record<string, unknown>) => ({
          ok: true,
          code: 'ok',
          data: {
            breed: 'Hubbard',
            ageWeek: 40,
            requested: [{ metric: 'production', value: null, unit: '%' }],
            unavailable: ['production'],
            context: {
              breed: 'Hubbard',
              ageWeek: 40,
              hatchabilityPct: 90.2,
              fertilityPct: 96.5,
              hofPct: 93.47,
              productionPct: null,
              eggWeightG: 65.3,
              chickWeightG: 46,
            },
          },
        }),
      }],
      assertions: [
        maxWords(20),
        noAssistantServiceLanguage(),
        mustMatch(
          /مش متاح|غير متاح|مش موجود|مالقيتش|مش لاقي|مش متوفر|غير متوفر/,
          'saysUnavailable',
        ),
        mustNotMatch(
          /80|٨٠|84|٨٤|90|٩٠|96|٩٦|93|٩٣|65|٦٥|46|٤٦|95|٩٥|88|٨٨/,
          'noNumberAtAll',
        ),
      ],
    }],
  },
  // -------------------------------------------------------------------------
  // 2026-08-19 shaped get_egg_breakout_benchmark + report/benchmark routing.
  // -------------------------------------------------------------------------
  {
    // THE most important canary in the suite: the exact production failure
    // this shipped to fix. A report/history request must go to the audit
    // tools, never to a benchmark tool, and with no customer resolved yet it
    // gets exactly one short clarification — not a flat-dumped benchmark row.
    id: 'breakout-report-not-benchmark',
    turns: [{
      userText: 'إيه آخر تقرير break out موجود عندك؟',
      label: 'report request, no customer resolved',
      toolStubs: [
        {
          name: 'list_customers',
          output: {
            ok: true,
            data: {
              customers: [
                { id: 'cust_rs_nilev', name: 'Rs-NileV' },
                { id: 'cust_abu_ghaly', name: 'Abu Ghaly' },
              ],
              truncated: false,
            },
          },
        },
        {
          name: 'resolve_customer_flock',
          output: {
            ok: true,
            data: {
              status: 'customer_not_found',
              customer: null,
              flock: null,
              candidates: [
                { id: 'cust_rs_nilev', name: 'Rs-NileV' },
                { id: 'cust_abu_ghaly', name: 'Abu Ghaly' },
              ],
              truncated: false,
            },
          },
        },
        {
          name: 'list_customer_audits',
          output: {
            ok: true,
            data: { customerId: 'unknown', flockId: null, audits: [], truncated: false },
          },
        },
      ],
      assertions: [
        toolNotCalled('get_egg_breakout_benchmark'),
        toolNotCalled('get_breed_benchmark'),
        atMostOneQuestion(),
        maxWords(14),
      ],
    }],
  },
  {
    // The canary above uses the incident sentence VERBATIM, and that same
    // sentence is a calibration example in the policy. It therefore cannot
    // distinguish "the model applied the rule" from "the model parroted the
    // example" — an Opus review caught exactly that. This canary asks for a
    // recorded result in wording that appears NOWHERE in the policy: no
    // "آخر تقرير", no "audit", no customer named, and no age week. Only the
    // rule itself can route it. If the routing rules ever regress to
    // classifying "no customer named" as a standard question, this fails and
    // the verbatim one still passes.
    id: 'report-unparroted-phrasing',
    turns: [{
      userText: 'النتيجة اللي طلعت عندنا كام؟',
      label: 'recorded-result request, wording not in the policy',
      toolStubs: [
        {
          name: 'list_customers',
          output: {
            ok: true,
            data: {
              customers: [
                { id: 'cust_rs_nilev', name: 'Rs-NileV' },
                { id: 'cust_abu_ghaly', name: 'Abu Ghaly' },
              ],
              truncated: false,
            },
          },
        },
        {
          name: 'list_customer_audits',
          output: {
            ok: true,
            data: { customerId: 'unknown', flockId: null, audits: [], truncated: false },
          },
        },
      ],
      assertions: [
        toolNotCalled('get_egg_breakout_benchmark'),
        toolNotCalled('get_breed_benchmark'),
        atMostOneQuestion(),
        maxWords(14),
      ],
    }],
  },
  {
    // Finding 4 of the same review: the report triggers must not swallow an
    // ordinary station-record question. "سجل" is the everyday Arabic word for
    // both an audit record and a machine reading, so a temperature-record
    // question must still reach query_station_records rather than the
    // audit-selection chain.
    id: 'station-record-not-audit',
    turns: [{
      userText: 'إيه آخر سجل حرارة في ماكينة التحضين؟',
      label: 'station record, not an audit report',
      toolStubs: [
        {
          name: 'resolve_customer_flock',
          output: {
            ok: true,
            data: {
              status: 'ok',
              customer: { id: 'cust_rs_nilev', name: 'Rs-NileV' },
              flock: null,
            },
          },
        },
        {
          name: 'query_station_records',
          output: {
            ok: true,
            code: 'ok',
            data: {
              records: [{ recordedAt: '2026-08-18', temperatureF: 99.5 }],
              truncated: false,
            },
          },
        },
      ],
      assertions: [
        toolNotCalled('list_customer_audits'),
        toolNotCalled('select_audit_option'),
        atMostOneQuestion(),
      ],
    }],
  },
  {
    id: 'breakout-single-metric-scope',
    turns: [{
      userText: 'نسبة الـ infertile المفروض تكون كام في الأسبوع 40؟',
      label: 'infertile only',
      toolStubs: [{
        name: 'get_egg_breakout_benchmark',
        output: {
          ok: true,
          code: 'ok',
          data: {
            ageWeek: 40,
            requested: [{ metric: 'infertile', value: 6.2, unit: '%' }],
            context: FULL_BREAKOUT_CONTEXT,
          },
        },
      }],
      assertions: [
        maxWords(15),
        noAssistantServiceLanguage(),
        mustMatch(/6[.,٫]2|٦[.,٫]٢/, 'statesInfertileValue'),
        mustNotMatchAnyNumber(siblingValues(['infertile']), 'noSiblingMetrics'),
        toolCalledWithArgumentContaining('get_egg_breakout_benchmark', 'infertile'),
      ],
    }],
  },
  {
    id: 'breakout-two-metric-scope',
    turns: [{
      userText: 'نسبة الـ infertile والـ contaminated كام في الأسبوع 40؟',
      label: 'infertile + contaminated',
      toolStubs: [{
        name: 'get_egg_breakout_benchmark',
        output: {
          ok: true,
          code: 'ok',
          data: {
            ageWeek: 40,
            requested: [
              { metric: 'infertile', value: 6.2, unit: '%' },
              { metric: 'contaminated', value: 0.5, unit: '%' },
            ],
            context: FULL_BREAKOUT_CONTEXT,
          },
        },
      }],
      assertions: [
        maxWords(25),
        noAssistantServiceLanguage(),
        mustMatch(/6[.,٫]2|٦[.,٫]٢/, 'statesInfertileValue'),
        mustMatch(/0[.,٫]5|٠[.,٫]٥/, 'statesContaminatedValue'),
        mustNotMatchAnyNumber(
          siblingValues(['infertile', 'contaminated']),
          'noUnrequestedMetrics',
        ),
      ],
    }],
  },
  {
    id: 'breakout-full-summary-allowed',
    turns: [{
      // Explicit, deliberate full-detail request — the longest legitimate
      // reply the voice policy permits. Proves the 1536-token ceiling does
      // not truncate it (see tools/probe_output_tokens.ts: this exact shape
      // measured at 761 output tokens).
      userText: 'إديني كل أرقام الـ breakout كاملة للأسبوع 40 واحدة واحدة بالتفصيل',
      label: 'explicit full breakout summary',
      toolStubs: [{ name: 'get_egg_breakout_benchmark', output: FULL_BREAKOUT_ROW }],
      assertions: [
        noAssistantServiceLanguage(),
        respondedCompletely(),
        maxOutputTokens(1536),
        {
          label: 'atLeastFourMetrics',
          check: (reply: string) => {
            const hits = [
              /6[.,٫]2|٦[.,٫]٢/,
              /1[.,٫]4|١[.,٫]٤/,
              /1[.,٫]1|١[.,٫]١/,
              /0[.,٫]8|٠[.,٫]٨/,
              /0[.,٫]6|٠[.,٫]٦/,
              /2[.,٫]3|٢[.,٫]٣/,
              /1[.,٫]2|١[.,٫]٢/,
              /3[.,٫]1|٣[.,٫]١/,
              /1[.,٫]7|١[.,٫]٧/,
              /0[.,٫]9|٠[.,٫]٩/,
              /0[.,٫]5|٠[.,٫]٥/,
            ].filter((pattern) => pattern.test(reply)).length
            return hits >= 4 ? null : `only ${hits} metrics present`
          },
        },
      ],
    }],
  },
  {
    id: 'breakout-null-metric',
    turns: [{
      userText: 'نسبة الـ contaminated كام في الأسبوع 40؟',
      label: 'shaped payload, contaminated null',
      toolStubs: [{
        name: 'get_egg_breakout_benchmark',
        output: {
          ok: true,
          code: 'ok',
          data: {
            ageWeek: 40,
            requested: [{ metric: 'contaminated', value: null, unit: '%' }],
            unavailable: ['contaminated'],
            context: { ...FULL_BREAKOUT_CONTEXT, contamPct: null },
          },
        },
      }],
      assertions: [
        maxWords(20),
        noAssistantServiceLanguage(),
        mustMatch(
          /مش متاح|غير متاح|مش موجود|مالقيتش|مش لاقي|مش متوفر|غير متوفر/,
          'saysUnavailable',
        ),
        mustNotMatchAnyNumber(siblingValues(['contaminated']), 'noSiblingSubstitution'),
        mustNotMatch(
          /\d+([.,٫]\d+)?\s*(٪|%|في المية|بالمية|في المئة)/,
          'noInventedPercentage',
        ),
      ],
    }],
  },
  {
    // Anti-regression for the flat-dump failure: an unrecognized metric name
    // must not make the model read the whole context row aloud.
    id: 'breakout-unknown-metric',
    turns: [{
      userText: 'إيه نسبة جودة القشرة في الأسبوع 40؟',
      label: 'unrecognized metric (shell quality)',
      toolStubs: [{
        name: 'get_egg_breakout_benchmark',
        output: {
          ok: true,
          code: 'ok',
          data: {
            ageWeek: 40,
            requested: [],
            unknownMetrics: ['shell_quality'],
            context: FULL_BREAKOUT_CONTEXT,
          },
        },
      }],
      assertions: [
        maxWords(20),
        atMostOneQuestion(),
        noAssistantServiceLanguage(),
        mustNotMatchAnyNumber(Object.values(BREAKOUT_METRIC_VALUES), 'noContextDump'),
      ],
    }],
  },
  {
    id: 'length-guard-long-followup',
    turns: [{
      userText: 'قارنلي كل نتايج آخر تدقيق بالمعايير رقم رقم، عايز التفاصيل كاملة',
      label: 'full audit-vs-benchmark comparison',
      toolStubs: [{
        name: 'compare_selected_audit_to_benchmark',
        output: {
          ok: true,
          code: 'ok',
          data: {
            auditId: 'audit_123',
            breed: 'Hubbard',
            ageWeek: 40,
            breakoutBenchmarkAvailable: true,
            comparisons: [
              {
                metricKey: 'hatchabilityPct',
                label: 'Hatchability',
                unit: '%',
                actual: 88.5,
                standard: 90.2,
                observedRows: 12,
                delta: -1.7,
              },
              {
                metricKey: 'fertilityPct',
                label: 'Fertility',
                unit: '%',
                actual: 95.1,
                standard: 96.5,
                observedRows: 12,
                delta: -1.4,
              },
              {
                metricKey: 'hofPct',
                label: 'Hatch of fertile',
                unit: '%',
                actual: 93.06,
                standard: 93.47,
                observedRows: 12,
                delta: -0.41,
              },
              {
                metricKey: 'productionPct',
                label: 'Production',
                unit: '%',
                actual: 78.4,
                standard: 80,
                observedRows: 0,
                delta: -1.6,
              },
              {
                metricKey: 'eggWeightG',
                label: 'Egg weight',
                unit: 'g',
                actual: 64.8,
                standard: 65.3,
                observedRows: 0,
                delta: -0.5,
              },
              {
                metricKey: 'chickWeightG',
                label: 'Chick weight',
                unit: 'g',
                actual: 45.6,
                standard: 46,
                observedRows: 0,
                delta: -0.4,
              },
              {
                metricKey: 'infertilePct',
                label: 'Infertile',
                unit: '%',
                actual: 6.9,
                standard: 6.2,
                observedRows: 12,
                delta: 0.7,
              },
              {
                metricKey: 'early24hPct',
                label: 'Early dead 24h',
                unit: '%',
                actual: 1.6,
                standard: 1.4,
                observedRows: 12,
                delta: 0.2,
              },
              {
                metricKey: 'early48hPct',
                label: 'Early dead 48h',
                unit: '%',
                actual: 1.3,
                standard: 1.1,
                observedRows: 12,
                delta: 0.2,
              },
              {
                metricKey: 'bloodRingPct',
                label: 'Blood ring',
                unit: '%',
                actual: 1.0,
                standard: 0.8,
                observedRows: 12,
                delta: 0.2,
              },
              {
                metricKey: 'blackEyePct',
                label: 'Black eye',
                unit: '%',
                actual: 0.7,
                standard: 0.6,
                observedRows: 12,
                delta: 0.1,
              },
              {
                metricKey: 'earlyDeadPct',
                label: 'Early dead',
                unit: '%',
                actual: 2.5,
                standard: 2.3,
                observedRows: 12,
                delta: 0.2,
              },
              {
                metricKey: 'midDeadPct',
                label: 'Mid dead',
                unit: '%',
                actual: 1.4,
                standard: 1.2,
                observedRows: 12,
                delta: 0.2,
              },
              {
                metricKey: 'lateDeadPct',
                label: 'Late dead',
                unit: '%',
                actual: 3.4,
                standard: 3.1,
                observedRows: 12,
                delta: 0.3,
              },
              {
                metricKey: 'externalPipPct',
                label: 'External pip',
                unit: '%',
                actual: 2.0,
                standard: 1.7,
                observedRows: 12,
                delta: 0.3,
              },
              {
                metricKey: 'crackedPct',
                label: 'Cracked',
                unit: '%',
                actual: 1.1,
                standard: 0.9,
                observedRows: 12,
                delta: 0.2,
              },
              {
                metricKey: 'contamPct',
                label: 'Contaminated',
                unit: '%',
                actual: 0.8,
                standard: 0.5,
                observedRows: 12,
                delta: 0.3,
              },
            ],
          },
        },
      }],
      assertions: [
        maxWords(45),
        respondedCompletely(),
        maxOutputTokens(1536),
      ],
    }],
  },
]

// ---------------------------------------------------------------------------
// Transport (audio-out variant of run_evals.ts)
// ---------------------------------------------------------------------------

interface RealtimeEvent {
  readonly type: string
  readonly [key: string]: unknown
}

class Session {
  private readonly queue: RealtimeEvent[] = []
  private readonly waiters: Array<(event: RealtimeEvent) => void> = []

  private constructor(private readonly ws: NodeWebSocket) {
    ws.on('message', (data: Buffer | string) => {
      try {
        this.push(JSON.parse(data.toString()))
      } catch {
        // non-JSON frame: ignore
      }
    })
    ws.on('close', (code: number) => this.push({ type: '_closed', code }))
    ws.on('error', (err: Error) => this.push({ type: '_error', message: err.message }))
  }

  static async connect(apiKey: string): Promise<Session> {
    const ws = new NodeWebSocket(`${OPENAI_REALTIME_URL}?model=${MODEL}`, {
      headers: { Authorization: `Bearer ${apiKey}` },
    })
    const session = new Session(ws)
    await new Promise<void>((resolve, reject) => {
      ws.once('open', () => resolve())
      ws.once(
        'error',
        (err: Error) => reject(new Error(`connect failed: ${err.message}`)),
      )
    })
    return session
  }

  private push(event: RealtimeEvent): void {
    const waiter = this.waiters.shift()
    if (waiter) waiter(event)
    else this.queue.push(event)
  }

  next(): Promise<RealtimeEvent> {
    const queued = this.queue.shift()
    if (queued) return Promise.resolve(queued)
    return new Promise((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error(`timed out after ${EVENT_TIMEOUT_MS}ms`)),
        EVENT_TIMEOUT_MS,
      )
      this.waiters.push((event) => {
        clearTimeout(timer)
        resolve(event)
      })
    })
  }

  send(payload: unknown): void {
    this.ws.send(JSON.stringify(payload))
  }

  close(): void {
    try {
      this.ws.close(1000, 'canary done')
    } catch {
      // already closed
    }
  }
}

async function awaitEvent(
  session: Session,
  predicate: (event: RealtimeEvent) => boolean,
): Promise<RealtimeEvent> {
  for (;;) {
    const event = await session.next()
    if (event.type === '_error') throw new Error(`transport: ${String(event.message)}`)
    if (event.type === '_closed') throw new Error(`socket closed (${String(event.code)})`)
    if (event.type === 'error') {
      throw new Error(`provider error: ${JSON.stringify(event)}`)
    }
    if (predicate(event)) return event
  }
}

interface FunctionCall {
  readonly name: string
  readonly callId: string
  readonly arguments: Record<string, unknown>
  // The raw `arguments` JSON string as sent by the model, kept alongside the
  // parsed form so assertions can substring-match on it directly (parsing
  // then re-stringifying can reorder keys / reformat values).
  readonly rawArguments: string
}

/** Best-effort JSON parse of a function_call item's `arguments` string. */
function parseCallArguments(raw: unknown): Record<string, unknown> {
  if (typeof raw !== 'string') return {}
  try {
    const parsed = JSON.parse(raw)
    return parsed && typeof parsed === 'object' ? parsed as Record<string, unknown> : {}
  } catch {
    return {}
  }
}

/** Extracts the spoken transcript + tool calls from one response.done. */
function parseResponse(
  done: RealtimeEvent,
): { transcript: string; calls: FunctionCall[] } {
  const response = done.response as Record<string, unknown> | undefined
  const output = (response?.output as unknown[] | undefined) ?? []
  let transcript = ''
  const calls: FunctionCall[] = []
  for (const raw of output) {
    const item = raw as Record<string, unknown>
    if (item.type === 'message') {
      const content = (item.content as Array<Record<string, unknown>> | undefined) ?? []
      for (const part of content) {
        // Audio output carries the spoken words in `transcript`.
        if (typeof part.transcript === 'string') transcript += part.transcript
        else if (typeof part.text === 'string') transcript += part.text
      }
    }
    if (item.type === 'function_call') {
      const rawArguments = typeof item.arguments === 'string' ? item.arguments : ''
      calls.push({
        name: String(item.name),
        callId: String(item.call_id),
        arguments: parseCallArguments(item.arguments),
        rawArguments,
      })
    }
  }
  return { transcript, calls }
}

/** Pulls `response.usage.output_tokens` and `response.status` off one response.done. */
function extractResponseMeta(
  done: RealtimeEvent,
): { outputTokens: number; status: string | undefined } {
  const response = done.response as Record<string, unknown> | undefined
  const usage = response?.usage as Record<string, unknown> | undefined
  const outputTokens = typeof usage?.output_tokens === 'number' ? usage.output_tokens : 0
  const status = typeof response?.status === 'string' ? response.status : undefined
  return { outputTokens, status }
}

async function runTurn(
  session: Session,
  turn: CanaryTurn,
): Promise<
  {
    final: string
    allSpeech: string
    calls: FunctionCall[]
    outputTokens: number
    status: string | undefined
  }
> {
  session.send({
    type: 'conversation.item.create',
    item: {
      type: 'message',
      role: 'user',
      content: [{ type: 'input_text', text: turn.userText }],
    },
  })
  session.send({ type: 'response.create' })

  let transcript = ''
  const allSpeech: string[] = []
  const allCalls: FunctionCall[] = []
  let totalOutputTokens = 0
  let lastStatus: string | undefined
  for (let round = 0; round <= MAX_TOOL_ROUNDS; round++) {
    let done = await awaitEvent(session, (event) => event.type === 'response.done')
    let parsed = parseResponse(done)
    let meta = extractResponseMeta(done)
    totalOutputTokens += meta.outputTokens
    lastStatus = meta.status
    // Known transient hiccup (see run_evals.ts): response.done can carry zero
    // output under rapid successive sessions. Retry the response, never the
    // user message or tool output.
    for (
      let retry = 1;
      parsed.transcript === '' && parsed.calls.length === 0 && retry <= 3;
      retry++
    ) {
      console.error(`  [warn] empty response.done — retrying (${retry}/3)`)
      await sleep(4000 * retry)
      session.send({ type: 'response.create' })
      done = await awaitEvent(session, (event) => event.type === 'response.done')
      parsed = parseResponse(done)
      meta = extractResponseMeta(done)
      totalOutputTokens += meta.outputTokens
      lastStatus = meta.status
    }
    transcript = parsed.transcript || transcript
    if (parsed.transcript) allSpeech.push(parsed.transcript)
    allCalls.push(...parsed.calls)
    if (parsed.calls.length === 0) break
    for (const call of parsed.calls) {
      const stub = turn.toolStubs?.find((candidate) => candidate.name === call.name)
      const output = stub
        ? (typeof stub.output === 'function'
          ? (stub.output as (args: Record<string, unknown>) => unknown)(call.arguments)
          : stub.output)
        : { ok: false, code: 'unstubbed_in_eval', tool: call.name, data: null }
      session.send({
        type: 'conversation.item.create',
        item: {
          type: 'function_call_output',
          call_id: call.callId,
          output: JSON.stringify(output),
        },
      })
    }
    session.send({ type: 'response.create' })
  }
  return {
    final: transcript,
    allSpeech: allSpeech.join(' '),
    calls: allCalls,
    outputTokens: totalOutputTokens,
    status: lastStatus,
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

async function main(): Promise<void> {
  const apiKey = Deno.env.get('OPENAI_API_KEY')
  if (!apiKey) {
    console.error('OPENAI_API_KEY is not set.')
    Deno.exit(1)
  }
  const filterFlagIndex = Deno.args.indexOf('--filter')
  const filter = filterFlagIndex >= 0 ? Deno.args[filterFlagIndex + 1] : undefined
  const effortFlagIndex = Deno.args.indexOf('--effort')
  const effort = effortFlagIndex >= 0
    ? Deno.args[effortFlagIndex + 1] as 'minimal' | 'low' | 'medium' | 'high'
    : undefined

  const { text: instructions, version } = await loadInstructions()
  const tools = await loadTools()
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(instructions),
  )
  const sha = Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0')).join('')

  console.log(`Model: ${MODEL} (audio output — production payload shape)`)
  console.log(`Instructions version: ${version}`)
  console.log(`Instructions sha256: ${sha} (${instructions.length} chars)`)
  console.log(`Tools: ${tools.length}`)
  console.log('')

  const config = effort ? testConfig({ reasoningEffort: effort }) : testConfig()
  console.log(`Reasoning effort: ${config.reasoningEffort}`)
  let pass = 0
  let fail = 0
  const failures: string[] = []

  const toRun = CANARIES.filter((canary) => !filter || canary.id.includes(filter))
  for (const [index, canary] of toRun.entries()) {
    if (index > 0) await sleep(INTER_SCENARIO_DELAY_MS)
    console.log(`=== ${canary.id} ===`)
    let session: Session | undefined
    const priorReplies: string[] = []
    try {
      session = await Session.connect(apiKey)
      // THE point of this runner: the exact production payload.
      session.send(buildSessionUpdate({ config, tools: [...tools], instructions }))
      await awaitEvent(session, (event) => event.type === 'session.updated')

      for (const turn of canary.turns) {
        const { final: reply, allSpeech, calls, outputTokens, status } = await runTurn(
          session,
          turn,
        )
        const meta: TurnMeta = { calls, outputTokens, status }
        console.log(`  user:  ${turn.userText}`)
        console.log(`  pip:   ${reply || '(empty)'}`)
        console.log(
          `  usage: ${outputTokens} output tokens, status="${status ?? 'unknown'}"`,
        )
        for (const assertion of turn.assertions) {
          const problem = assertion.check(reply, priorReplies, meta)
          if (problem === null) {
            pass++
          } else {
            fail++
            failures.push(`${canary.id} / ${turn.label} / ${assertion.label}: ${problem}`)
            console.log(`  FAIL ${assertion.label}: ${problem}`)
          }
        }
        for (const assertion of turn.allSpeechAssertions ?? []) {
          const problem = assertion.check(allSpeech, priorReplies, meta)
          if (problem === null) {
            pass++
          } else {
            fail++
            failures.push(`${canary.id} / ${turn.label} / ${assertion.label}: ${problem}`)
            console.log(`  FAIL ${assertion.label}: ${problem}`)
          }
        }
        priorReplies.push(reply)
      }
    } catch (err) {
      fail++
      failures.push(`${canary.id} / transport: ${String(err)}`)
      console.log(`  TRANSPORT FAIL: ${String(err)}`)
    } finally {
      session?.close()
    }
    console.log('')
  }

  console.log('='.repeat(70))
  console.log(`${pass} passed, ${fail} failed`)
  for (const failure of failures) console.log(`  FAIL ${failure}`)
  Deno.exit(fail > 0 ? 1 : 0)
}

if (import.meta.main) {
  main()
}
