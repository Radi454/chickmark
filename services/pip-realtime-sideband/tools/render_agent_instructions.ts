// Renders the Harness v2 voice policy for the separately deployed Sideband.
// This is a deploy-time tool, never imported by the Cloud Run runtime.

import {
  CHICKMARK_REALTIME_POLICY,
  CHICKMARK_REALTIME_POLICY_VERSION,
} from '../../../supabase/functions/telegram-hatchery-agent/agent_prompt.ts'

export function renderRealtimeInstructions(): string {
  return CHICKMARK_REALTIME_POLICY
}

export const RENDERED_INSTRUCTION_VERSION = CHICKMARK_REALTIME_POLICY_VERSION

if (import.meta.main) {
  if (Deno.args.includes('--json')) {
    console.log(JSON.stringify({
      PIP_REALTIME_INSTRUCTIONS_VERSION: RENDERED_INSTRUCTION_VERSION,
      PIP_REALTIME_INSTRUCTIONS: renderRealtimeInstructions(),
    }))
  } else {
    console.log(renderRealtimeInstructions())
  }
}
