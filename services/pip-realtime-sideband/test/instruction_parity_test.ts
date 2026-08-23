import { assert, assertEquals, assertStringIncludes } from '@std/assert'

import { CHICKMARK_REALTIME_POLICY_VERSION } from '../../../supabase/functions/telegram-hatchery-agent/agent_prompt.ts'
import {
  RENDERED_INSTRUCTION_VERSION,
  renderRealtimeInstructions,
} from '../tools/render_agent_instructions.ts'

Deno.test('the rendered Live policy is the Harness v2 realtime policy', () => {
  const rendered = renderRealtimeInstructions()
  // Benchmark discipline carries over to voice unchanged.
  assertStringIncludes(rendered, 'get_breed_benchmark')
  assertStringIncludes(rendered, 'state the breed and the age')
  // Voice-only conversation guidance is present.
  assertStringIncludes(rendered, 'Voice conversation:')
  assertStringIncludes(rendered, 'العامية المصرية')
  // Telegram-only formatting and the topic limiter must not leak into voice —
  // casual conversation is allowed on a live call.
  assert(!rendered.includes('Telegram'))
  assert(!rendered.includes('Stay within ChickMark'))
  // Report-vs-benchmark routing is voice-only and must reach the rendered
  // Live policy: the 2026-08-19 production failure was a report request
  // ("إيه آخر تقرير break out موجود عندك؟") answered from the published
  // standard. If this section stops rendering, that regression is silent.
  assertStringIncludes(rendered, 'Report vs benchmark routing:')
  assertStringIncludes(rendered, 'list_customer_audits')
  // The version names the realtime policy directly.
  assertEquals(RENDERED_INSTRUCTION_VERSION, CHICKMARK_REALTIME_POLICY_VERSION)
  assertEquals(RENDERED_INSTRUCTION_VERSION, '2.3.0')
})
