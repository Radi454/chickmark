// Renders PIP_REALTIME_TOOL_DEFINITIONS from the versioned tool contract.
//
// WHY A RENDERER AND NOT AN IMPORT
//
// `AGENT_TOOL_CONTRACT` is the one source of truth for what the model may call,
// and it lives in the Supabase edge-function deployment. This service is a
// separate Cloud Run image whose Dockerfile copies only `main.ts` and `src/`, so
// nothing under `src/` may reach across into `supabase/functions` — the image
// would not build. Copying the catalogue into `src/` instead would fork it, and
// a forked catalogue is exactly the drift the contract was written to prevent.
//
// So the catalogue crosses the deployment boundary as CONFIGURATION, and this
// script is the only sanctioned way to produce that configuration. It is a build
// and deploy-time tool: it is not part of the image, is never imported by
// `main.ts`, and runs from the repo where both trees are present.
//
//   deno run --allow-read tools/render_tool_definitions.ts            # the JSON
//   deno run --allow-read tools/render_tool_definitions.ts --env      # KEY=value
//
// `test/tool_contract_test.ts` asserts that what this produces is accepted by
// `loadConfig` and covers every tool in the contract, so a contract change that
// this renderer cannot express fails the suite rather than the deploy.

import type { AgentToolName } from '../../../supabase/functions/telegram-hatchery-agent/agent_protocol.ts'
import {
  AGENT_TOOL_CONTRACT_VERSION,
  modelFacingContract,
} from '../../../supabase/functions/telegram-hatchery-agent/agent_tool_contract.ts'
import type { RealtimeToolDefinition } from '../src/session_config.ts'

/**
 * The FLAT Realtime shape: `{type, name, description, parameters}`. The nested
 * Chat Completions shape (`{type:'function', function:{...}}`) is rejected by
 * the provider, and by `loadConfig`.
 *
 * Renders the MODEL-FACING projection (`modelFacingContract`), not the raw
 * validation contract — the Realtime session only needs enough schema to pick
 * and fill a tool call; the broker's `executeAgentTool` enforces the full
 * contract server-side regardless of what was rendered here. Pass `names` to
 * render only a subset (still in contract order); omit it to render every
 * tool, which is what the deploy pipeline's CLI entrypoint below does.
 */
export function renderRealtimeToolDefinitions(
  names?: readonly AgentToolName[],
): RealtimeToolDefinition[] {
  return modelFacingContract(names).map((entry) => ({
    type: 'function' as const,
    name: entry.name,
    description: entry.description,
    parameters: entry.parameters as unknown as Record<string, unknown>,
  }))
}

/** Convenience wrapper for the common case of rendering a fixed subset. */
export function renderRealtimeToolDefinitionsFor(
  names: readonly AgentToolName[],
): RealtimeToolDefinition[] {
  return renderRealtimeToolDefinitions(names)
}

export function renderToolDefinitionsJson(): string {
  return JSON.stringify(renderRealtimeToolDefinitions())
}

export const RENDERED_CONTRACT_VERSION = AGENT_TOOL_CONTRACT_VERSION

if (import.meta.main) {
  const json = renderToolDefinitionsJson()
  if (Deno.args.includes('--env')) {
    console.log(
      `PIP_REALTIME_TOOL_CONTRACT_VERSION=${AGENT_TOOL_CONTRACT_VERSION}`,
    )
    console.log(`PIP_REALTIME_TOOL_DEFINITIONS=${json}`)
  } else {
    console.log(json)
  }
}
