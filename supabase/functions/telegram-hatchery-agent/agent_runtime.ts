import { buildAgentInstructions } from './agent_prompt.ts'
import type {
  AgentModelInputItem,
  AgentModelOutputItem,
  AgentProvider,
} from './agent_provider.ts'
import type {
  AgentScope,
  AgentToolCall,
  AgentToolResult,
} from './agent_protocol.ts'
import {
  AGENT_TOOL_DEFINITIONS,
  MAX_AGENT_TOOL_CALLS_PER_TURN,
} from './agent_tools.ts'

export interface AgentHistoryTurn {
  role: 'user' | 'assistant'
  text: string
}

export interface AgentTurnAttachment {
  kind: string
  fileName: string | null
  mimeType: string | null
  fileData: string | null
}

export interface AgentTurnInput {
  scope: AgentScope
  conversationId: string
  activeVisitId: string | null
  conversationTurnId: string
  conversationTurnIndex: number
  text: string
  attachment?: AgentTurnAttachment | null
  recentTurns: readonly AgentHistoryTurn[]
  pendingAction: unknown
  activeIntake: unknown
}

export type AgentTurnResult =
  | {
    status: 'replied'
    reply: string
    providerResponseId: string
    toolCallCount: number
  }
  | {
    status:
      | 'provider_unavailable'
      | 'provider_timeout'
      | 'turn_timeout'
      | 'tool_limit_exceeded'
      | 'invalid_model_output'
    toolCallCount: number
  }

export interface AgentRuntimeDependencies {
  provider: AgentProvider
  executeTool(call: AgentToolCall): Promise<AgentToolResult>
  maxTurnMs?: number
}

const MAX_HISTORY_TURNS = 20
const MAX_HISTORY_TEXT_CHARS = 4000
const MAX_CURRENT_TEXT_CHARS = 8000
const MAX_TOOL_OUTPUT_CHARS = 32_000
const MAX_REPLY_CHARS = 4000
const knownToolNames: ReadonlySet<string> = new Set(
  AGENT_TOOL_DEFINITIONS.map((definition) => definition.name),
)

export async function runAgentTurn(
  input: AgentTurnInput,
  dependencies: AgentRuntimeDependencies,
): Promise<AgentTurnResult> {
  const maxTurnMs = dependencies.maxTurnMs ?? 20_000
  const deadline = Date.now() + maxTurnMs
  const abortController = new AbortController()
  const modelInput = buildInitialInput(input)
  const instructions = buildAgentInstructions({
    scope: input.scope,
    conversationId: input.conversationId,
    activeVisitId: input.activeVisitId,
    pendingAction: input.pendingAction,
    activeIntake: input.activeIntake,
  })
  let toolCallCount = 0

  while (true) {
    const remainingMs = deadline - Date.now()
    if (remainingMs <= 0) {
      abortController.abort()
      return { status: 'provider_timeout', toolCallCount }
    }
    let response
    try {
      response = await withTimeout(
        dependencies.provider.respond(
          {
            instructions,
            input: modelInput,
            tools: AGENT_TOOL_DEFINITIONS,
          },
          { signal: abortController.signal },
        ),
        remainingMs,
        abortController,
      )
    } catch (error) {
      if (error instanceof AgentRuntimeTimeoutError) {
        return { status: 'provider_timeout', toolCallCount }
      }
      return { status: 'provider_unavailable', toolCallCount }
    }

    const functionItems = response.output.filter((item) =>
      item.type === 'function_call'
    )
    if (functionItems.length === 0) {
      const reply = extractAssistantText(response.output)
      if (!reply) {
        return { status: 'invalid_model_output', toolCallCount }
      }
      return {
        status: 'replied',
        reply: normalizeTelegramReply(reply).slice(0, MAX_REPLY_CHARS),
        providerResponseId: response.id,
        toolCallCount,
      }
    }

    modelInput.push(...response.output.map((item) => structuredClone(item)))
    for (const item of functionItems) {
      if (toolCallCount >= MAX_AGENT_TOOL_CALLS_PER_TURN) {
        return { status: 'tool_limit_exceeded', toolCallCount }
      }
      toolCallCount += 1
      const parsed = parseToolCall(item)
      let toolResult: AgentToolResult
      if (!parsed) {
        toolResult = {
          ok: false,
          code: 'invalid_arguments',
          data: null,
        }
      } else if (!knownToolNames.has(parsed.call.name)) {
        toolResult = {
          ok: false,
          code: 'unknown_tool',
          data: null,
        }
      } else {
        try {
          toolResult = await withTimeout(
            dependencies.executeTool(parsed.call),
            Math.max(1, deadline - Date.now()),
            abortController,
          )
        } catch (error) {
          if (error instanceof AgentRuntimeTimeoutError) {
            return { status: 'turn_timeout', toolCallCount }
          }
          toolResult = { ok: false, code: 'tool_failed', data: null }
        }
      }
      modelInput.push({
        type: 'function_call_output',
        call_id: parsed?.callId ?? safeCallId(item),
        output: boundedJson(toolResult),
      })
    }
  }
}

function buildInitialInput(input: AgentTurnInput): AgentModelInputItem[] {
  const turns = input.recentTurns.slice(-MAX_HISTORY_TURNS)
  const items: AgentModelInputItem[] = turns.map((turn) => ({
    role: turn.role,
    content: turn.text.slice(-MAX_HISTORY_TEXT_CHARS),
  }))
  const currentContent: Record<string, unknown> = {
    role: 'user',
    content: currentMessageContent(input),
  }
  items.push(currentContent)
  return items
}

function currentMessageContent(input: AgentTurnInput): unknown {
  const text = input.text.slice(0, MAX_CURRENT_TEXT_CHARS)
  if (!input.attachment) return text
  const content: Array<Record<string, unknown>> = []
  if (text) content.push({ type: 'input_text', text })
  if (
    input.attachment.kind === 'image' &&
    input.attachment.fileData
  ) {
    content.push({
      type: 'input_image',
      image_url: input.attachment.fileData,
      detail: 'high',
    })
  } else if (input.attachment.fileData) {
    content.push({
      type: 'input_file',
      filename: input.attachment.fileName ?? 'telegram-upload',
      file_data: input.attachment.fileData,
    })
  } else {
    content.push({
      type: 'input_text',
      text: `Untrusted attachment metadata: ${
        JSON.stringify({
          kind: input.attachment.kind,
          fileName: input.attachment.fileName,
          mimeType: input.attachment.mimeType,
        })
      }`,
    })
  }
  return content
}

function parseToolCall(
  item: AgentModelOutputItem,
): { call: AgentToolCall; callId: string } | null {
  if (
    typeof item.name !== 'string' ||
    typeof item.arguments !== 'string'
  ) return null
  const callId = safeCallId(item)
  try {
    const args: unknown = JSON.parse(item.arguments)
    if (!isRecord(args)) return null
    return {
      call: {
        id: callId,
        name: item.name,
        arguments: args,
      },
      callId,
    }
  } catch (_) {
    return null
  }
}

function safeCallId(item: AgentModelOutputItem): string {
  if (
    typeof item.call_id === 'string' &&
    item.call_id.trim().length > 0 &&
    item.call_id.length <= 200
  ) return item.call_id
  if (
    typeof item.id === 'string' &&
    item.id.trim().length > 0 &&
    item.id.length <= 200
  ) return item.id
  return crypto.randomUUID()
}

function extractAssistantText(
  output: readonly AgentModelOutputItem[],
): string | null {
  const chunks: string[] = []
  for (const item of output) {
    if (
      item.type !== 'message' || item.role !== 'assistant' ||
      !Array.isArray(item.content)
    ) continue
    for (const content of item.content) {
      if (
        isRecord(content) && content.type === 'output_text' &&
        typeof content.text === 'string'
      ) {
        const text = content.text.trim()
        if (text) chunks.push(text)
      }
    }
  }
  return chunks.length === 0 ? null : chunks.join('\n')
}

function normalizeTelegramReply(value: string): string {
  return value
    .replaceAll('**', '')
    .replaceAll('__', '')
    .replace(/```(?:[a-z0-9_-]+)?\n?/gi, '')
    .replaceAll('```', '')
    .replaceAll('`', '')
    .trim()
}

function boundedJson(value: unknown): string {
  const encoded = JSON.stringify(value)
  return encoded.length <= MAX_TOOL_OUTPUT_CHARS ? encoded : JSON.stringify({
    ok: false,
    code: 'tool_output_too_large',
    data: null,
  })
}

function withTimeout<T>(
  promise: Promise<T>,
  timeoutMs: number,
  controller: AbortController,
): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      controller.abort()
      reject(new AgentRuntimeTimeoutError())
    }, timeoutMs)
    promise.then(
      (value) => {
        clearTimeout(timer)
        resolve(value)
      },
      (error) => {
        clearTimeout(timer)
        reject(error)
      },
    )
  })
}

class AgentRuntimeTimeoutError extends Error {}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
