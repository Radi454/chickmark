import { assertEquals } from '@std/assert'

import {
  type AgentLegacyQuestionStore,
  createAgentLegacyToolHandlers,
} from './agent_legacy_tools.ts'
import type { AgentToolResult } from './agent_protocol.ts'
import { executeAgentTool } from './agent_tools.ts'

const scope = {
  staffLinkId: 'staff-a',
  accessRole: 'customer' as const,
  allowedCustomerIds: ['customer-a'],
}

Deno.test('legacy questions are returned only through an explicit scoped call', async () => {
  const calls: string[] = []
  const store: AgentLegacyQuestionStore = {
    listOpenQuestions(input) {
      calls.push(`list:${input.submissionId}`)
      return Promise.resolve(
        input.staffLinkId === 'staff-a'
          ? [{
            id: 'question-a',
            submissionId: 'submission-a',
            rowOrdinal: 1,
            fieldKey: 'flockAgeWeeks',
            questionTextEn: 'What is the flock age?',
            questionTextAr: 'ما عمر القطيع؟',
            submittedAt: '2026-07-28T10:00:00.000Z',
          }]
          : null,
      )
    },
    answerOpenQuestion: () => Promise.resolve(null),
  }
  const handlers = createAgentLegacyToolHandlers(store)

  assertEquals(calls, [])
  assertEquals(
    await call(handlers, 'list_legacy_draft_questions', {
      submissionId: 'submission-a',
    }),
    {
      ok: true,
      code: 'ok',
      data: {
        submissionId: 'submission-a',
        questions: [{
          questionId: 'question-a',
          rowOrdinal: 1,
          fieldKey: 'flockAgeWeeks',
          questionTextEn: 'What is the flock age?',
          questionTextAr: 'ما عمر القطيع؟',
        }],
      },
    },
  )
  assertEquals(calls, ['list:submission-a'])
})

Deno.test('legacy answer requires explicit submission and question identity', async () => {
  const answers: Array<Record<string, unknown>> = []
  const store: AgentLegacyQuestionStore = {
    listOpenQuestions: () => Promise.resolve([]),
    answerOpenQuestion(input) {
      answers.push(input)
      return Promise.resolve(
        input.submissionId === 'submission-a' &&
          input.questionId === 'question-a'
          ? {
            questionId: input.questionId,
            submissionId: input.submissionId,
            remainingCount: 0,
            status: 'needs_admin_review',
          }
          : null,
      )
    },
  }
  const handlers = createAgentLegacyToolHandlers(store, {
    now: () => new Date('2026-07-28T12:00:00.000Z'),
  })

  assertEquals(
    await call(handlers, 'answer_legacy_draft_question', {
      submissionId: 'submission-a',
      questionId: 'question-a',
      answer: '30',
    }),
    {
      ok: true,
      code: 'ok',
      data: {
        questionId: 'question-a',
        submissionId: 'submission-a',
        remainingCount: 0,
        status: 'needs_admin_review',
      },
    },
  )
  assertEquals(answers, [{
    staffLinkId: 'staff-a',
    conversationId: 'conversation-a',
    submissionId: 'submission-a',
    questionId: 'question-a',
    answer: '30',
    answeredAt: '2026-07-28T12:00:00.000Z',
  }])
  assertEquals(
    await call(handlers, 'answer_legacy_draft_question', {
      questionId: 'question-a',
      answer: '30',
    }),
    { ok: false, code: 'invalid_arguments', data: null },
  )
})

function call(
  handlers: ReturnType<typeof createAgentLegacyToolHandlers>,
  name: string,
  arguments_: Record<string, unknown>,
): Promise<AgentToolResult> {
  return executeAgentTool(
    { id: `call-${name}`, name, arguments: arguments_ },
    {
      scope,
      conversationId: 'conversation-a',
      activeVisitId: null,
      conversationTurnId: 'turn-a',
      conversationTurnIndex: 1,
      evidence: { record: () => undefined },
      handlers,
    },
  )
}
