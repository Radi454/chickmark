import { assertStringIncludes } from '@std/assert'

import { CHICKMARK_AGENT_POLICY } from './agent_prompt.ts'

Deno.test('the prompt forbids benchmark figures from memory', () => {
  assertStringIncludes(CHICKMARK_AGENT_POLICY, 'get_breed_benchmark')
  assertStringIncludes(CHICKMARK_AGENT_POLICY, 'never state a benchmark from memory')
})

Deno.test('the prompt requires breed and age week alongside benchmark figures', () => {
  assertStringIncludes(CHICKMARK_AGENT_POLICY, 'state the breed and the age in weeks')
})

Deno.test('the prompt forbids interpolating uncovered benchmark ranges', () => {
  assertStringIncludes(CHICKMARK_AGENT_POLICY, 'breed_not_found')
  assertStringIncludes(CHICKMARK_AGENT_POLICY, 'week_out_of_range')
  assertStringIncludes(CHICKMARK_AGENT_POLICY, 'never interpolate, extrapolate')
})

Deno.test('the prompt requires compare_selected_audit_to_benchmark for audit judgment', () => {
  assertStringIncludes(CHICKMARK_AGENT_POLICY, 'compare_selected_audit_to_benchmark')
})
