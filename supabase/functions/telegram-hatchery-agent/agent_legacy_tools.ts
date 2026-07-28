import {
  answerOpenDraftQuestion,
  type AnswerRoutingAdminClient,
  type LegacyDraftQuestion,
  loadOpenDraftQuestions,
} from './answer_routing.ts'
import type {
  AgentToolExecutionInput,
  AgentToolName,
  AgentToolResult,
} from './agent_protocol.ts'
import type { AgentToolHandler } from './agent_tools.ts'

export interface AgentLegacyQuestionStore {
  listOpenQuestions(input: {
    staffLinkId: string
    conversationId: string
    submissionId: string
  }): Promise<readonly LegacyDraftQuestion[] | null>
  answerOpenQuestion(input: {
    staffLinkId: string
    conversationId: string
    submissionId: string
    questionId: string
    answer: string
    answeredAt: string
  }): Promise<
    | {
      questionId: string
      submissionId: string
      remainingCount: number
      status: 'waiting_for_staff_answer' | 'needs_admin_review'
    }
    | null
  >
}

interface ConversationLookup {
  select(columns: string): ConversationLookup
  eq(column: string, value: unknown): ConversationLookup
  maybeSingle(): Promise<{
    data: Record<string, unknown> | null
    error: { message: string } | null
  }>
}

interface AgentLegacyClient extends AnswerRoutingAdminClient {
  from(table: string):
    & ConversationLookup
    & ReturnType<AnswerRoutingAdminClient['from']>
}

export function createSupabaseAgentLegacyQuestionStore(
  client: AgentLegacyClient,
): AgentLegacyQuestionStore {
  return {
    async listOpenQuestions(input) {
      const chatId = await authorizedChatId(client, input)
      if (!chatId) return null
      return loadOpenDraftQuestions(
        client,
        input.staffLinkId,
        chatId,
        input.submissionId,
      )
    },
    async answerOpenQuestion(input) {
      const chatId = await authorizedChatId(client, input)
      if (!chatId) return null
      return answerOpenDraftQuestion({
        client,
        staffLinkId: input.staffLinkId,
        chatId,
        submissionId: input.submissionId,
        questionId: input.questionId,
        answerText: input.answer,
        timestamp: input.answeredAt,
      })
    },
  }
}

export function createAgentLegacyToolHandlers(
  store: AgentLegacyQuestionStore,
  options: { now?: () => Date } = {},
): Partial<Record<AgentToolName, AgentToolHandler>> {
  const now = options.now ?? (() => new Date())
  return {
    list_legacy_draft_questions: (input) =>
      listLegacyDraftQuestions(store, input),
    answer_legacy_draft_question: (input) =>
      answerLegacyDraftQuestion(store, input, now),
  }
}

async function listLegacyDraftQuestions(
  store: AgentLegacyQuestionStore,
  input: AgentToolExecutionInput,
): Promise<AgentToolResult> {
  const submissionId = input.arguments.submissionId as string
  const questions = await store.listOpenQuestions({
    staffLinkId: input.scope.staffLinkId,
    conversationId: input.conversationId,
    submissionId,
  })
  if (!questions) return scopeDenied()
  return ok({
    submissionId,
    questions: questions.map((question) => ({
      questionId: question.id,
      rowOrdinal: question.rowOrdinal,
      fieldKey: question.fieldKey,
      questionTextEn: question.questionTextEn,
      questionTextAr: question.questionTextAr,
    })),
  })
}

async function answerLegacyDraftQuestion(
  store: AgentLegacyQuestionStore,
  input: AgentToolExecutionInput,
  now: () => Date,
): Promise<AgentToolResult> {
  const result = await store.answerOpenQuestion({
    staffLinkId: input.scope.staffLinkId,
    conversationId: input.conversationId,
    submissionId: input.arguments.submissionId as string,
    questionId: input.arguments.questionId as string,
    answer: input.arguments.answer as string,
    answeredAt: now().toISOString(),
  })
  return result ? ok(result) : {
    ok: false,
    code: 'question_not_open_or_invalid',
    data: null,
  }
}

async function authorizedChatId(
  client: AgentLegacyClient,
  input: { staffLinkId: string; conversationId: string },
): Promise<string | null> {
  const result = await client
    .from('agent_conversations')
    .select('id, staff_link_id, telegram_chat_id')
    .eq('id', input.conversationId)
    .eq('staff_link_id', input.staffLinkId)
    .maybeSingle()
  if (result.error || !result.data) return null
  return text(result.data.telegram_chat_id)
}

function ok(data: Record<string, unknown>): AgentToolResult {
  return { ok: true, code: 'ok', data }
}

function scopeDenied(): AgentToolResult {
  return { ok: false, code: 'scope_denied', data: null }
}

function text(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null
}
