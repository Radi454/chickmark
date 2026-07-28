import type { AgentToolDefinition } from './agent_tools.ts'

export type AgentModelInputItem = Record<string, unknown>
export type AgentModelOutputItem = Record<string, unknown>

export interface AgentModelRequest {
  instructions: string
  input: AgentModelInputItem[]
  tools: readonly AgentToolDefinition[]
}

export interface AgentModelResponse {
  id: string
  output: AgentModelOutputItem[]
}

export interface AgentProvider {
  respond(
    request: AgentModelRequest,
    options?: { signal?: AbortSignal },
  ): Promise<AgentModelResponse>
}

export type AgentProviderName = 'openai' | 'openrouter'

export interface ResponsesAgentProviderConfig {
  provider: AgentProviderName
  apiKey: string
  model?: string
  fetchImpl?: typeof fetch
}

export class AgentProviderError extends Error {
  constructor(
    message: string,
    readonly status: number | null = null,
  ) {
    super(message)
    this.name = 'AgentProviderError'
  }
}

const OPENAI_ENDPOINT = 'https://api.openai.com/v1/responses'
const OPENROUTER_ENDPOINT = 'https://openrouter.ai/api/v1/responses'
const DEFAULT_OPENAI_MODEL = 'gpt-4.1-mini'
const FREE_OPENROUTER_MODEL = 'openrouter/free'

export function createResponsesAgentProvider(
  config: ResponsesAgentProviderConfig,
): AgentProvider {
  const endpoint = config.provider === 'openrouter'
    ? OPENROUTER_ENDPOINT
    : OPENAI_ENDPOINT
  const requestedModel = config.model ??
    (config.provider === 'openrouter'
      ? FREE_OPENROUTER_MODEL
      : DEFAULT_OPENAI_MODEL)
  const fetchImpl = config.fetchImpl ?? fetch

  return {
    async respond(request, options) {
      const send = (model: string) =>
        fetchImpl(endpoint, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${config.apiKey}`,
            'Content-Type': 'application/json',
          },
          signal: options?.signal,
          body: JSON.stringify({
            model,
            instructions: request.instructions,
            input: request.input,
            tools: request.tools.map((tool) => ({
              ...tool,
              strict: false,
            })),
            tool_choice: 'auto',
            parallel_tool_calls: false,
            max_output_tokens: 1200,
            store: false,
          }),
        })

      let response: Response
      try {
        response = await send(requestedModel)
        if (
          config.provider === 'openrouter' &&
          response.status === 402 &&
          requestedModel !== FREE_OPENROUTER_MODEL
        ) {
          response = await send(FREE_OPENROUTER_MODEL)
        }
      } catch (error) {
        if (options?.signal?.aborted) throw error
        throw new AgentProviderError('Agent provider request failed')
      }

      if (!response.ok) {
        throw new AgentProviderError(
          `Agent provider returned HTTP ${response.status}`,
          response.status,
        )
      }
      let payload: unknown
      try {
        payload = await response.json()
      } catch (_) {
        throw new AgentProviderError('Agent provider returned invalid JSON')
      }
      return parseResponse(payload)
    },
  }
}

function parseResponse(payload: unknown): AgentModelResponse {
  if (!isRecord(payload) || typeof payload.id !== 'string') {
    throw new AgentProviderError('Agent provider response is malformed')
  }
  if (!Array.isArray(payload.output) || !payload.output.every(isRecord)) {
    throw new AgentProviderError('Agent provider output is malformed')
  }
  return {
    id: payload.id,
    output: payload.output.map((item) => structuredClone(item)),
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
