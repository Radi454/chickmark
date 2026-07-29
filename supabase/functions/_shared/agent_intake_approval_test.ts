import { assertEquals, assertThrows } from 'jsr:@std/assert@1.0.14'

import {
  AgentIntakeApprovalValidationError,
  prepareAgentIntakeApproval,
} from './agent_intake_approval.ts'

Deno.test('prepares only registry-mapped values for a generic station', () => {
  const prepared = prepareAgentIntakeApproval({
    intake: weightIntake(),
    expectedSummaryVersion: 2,
    targetSession: null,
    requestedTargetSessionId: null,
    panelRowId: 'panel-1',
    approvedAt: '2026-07-28T13:00:00.000Z',
  })

  assertEquals(prepared.schemaKey, 'chicks.weights')
  assertEquals(prepared.remoteTable, 'chick_weights')
  assertEquals(prepared.stationKey, 'chicks')
  assertEquals(prepared.panelPayload.weights_json, '[39.5,40,41.25]')
  assertEquals(prepared.panelPayload.sample_size, 3)
  assertEquals(prepared.panelPayload.avg_weight, 40.3)
  assertEquals(prepared.panelPayload.invented, undefined)
  assertEquals(prepared.panelPayload.session_id, null)
})

Deno.test('rejects stale, unconfirmed, and mismatched schema summaries', () => {
  assertApprovalCode(
    () =>
      prepareAgentIntakeApproval({
        intake: weightIntake(),
        expectedSummaryVersion: 1,
        targetSession: null,
        requestedTargetSessionId: null,
        panelRowId: 'panel-1',
        approvedAt: '2026-07-28T13:00:00.000Z',
      }),
    'stale_summary',
  )
  assertApprovalCode(
    () =>
      prepareAgentIntakeApproval({
        intake: { ...weightIntake(), user_confirmed_at: null },
        expectedSummaryVersion: 2,
        targetSession: null,
        requestedTargetSessionId: null,
        panelRowId: 'panel-1',
        approvedAt: '2026-07-28T13:00:00.000Z',
      }),
    'not_ready',
  )
  assertApprovalCode(
    () =>
      prepareAgentIntakeApproval({
        intake: {
          ...weightIntake(),
          summary_snapshot_json: {
            ...weightIntake().summary_snapshot_json as Record<string, unknown>,
            schemaKey: 'chicks.pasgar',
          },
        },
        expectedSummaryVersion: 2,
        targetSession: null,
        requestedTargetSessionId: null,
        panelRowId: 'panel-1',
        approvedAt: '2026-07-28T13:00:00.000Z',
      }),
    'stale_summary',
  )
})

Deno.test('rejects invalid values and cross-context target visits', () => {
  assertApprovalCode(
    () =>
      prepareAgentIntakeApproval({
        intake: {
          ...weightIntake(),
          working_values_json: { weightsJson: [0] },
        },
        expectedSummaryVersion: 2,
        targetSession: null,
        requestedTargetSessionId: null,
        panelRowId: 'panel-1',
        approvedAt: '2026-07-28T13:00:00.000Z',
      }),
    'invalid_values',
  )
  assertApprovalCode(
    () =>
      prepareAgentIntakeApproval({
        intake: weightIntake(),
        expectedSummaryVersion: 2,
        targetSession: {
          id: 'audit-1',
          customer_id: 'another-customer',
          flock_id: 'flock-1',
          hatchery_id: 'hatchery-1',
          date: '2026-07-28',
        },
        requestedTargetSessionId: 'audit-1',
        panelRowId: 'panel-1',
        approvedAt: '2026-07-28T13:00:00.000Z',
      }),
    'target_mismatch',
  )
})

function assertApprovalCode(
  callback: () => unknown,
  code: AgentIntakeApprovalValidationError['code'],
) {
  const error = assertThrows(
    callback,
    AgentIntakeApprovalValidationError,
  )
  assertEquals(error.code, code)
}

function weightIntake() {
  return {
    id: 'intake-1',
    schema_key: 'chicks.weights',
    schema_version: 1,
    state: 'awaiting_admin_review',
    summary_version: 2,
    summary_snapshot_json: {
      version: 2,
      schemaKey: 'chicks.weights',
      schemaVersion: 1,
      values: { weightsJson: [39.5, 40, 41.25] },
      calculations: {
        sampleSize: 3,
        avgWeight: 40.3,
        uniformityPct: 100,
        cvPct: 2.2,
      },
      generatedAt: '2026-07-28T12:00:00.000Z',
    },
    working_values_json: {
      weightsJson: [39.5, 40, 41.25],
    },
    user_confirmed_at: '2026-07-28T12:01:00.000Z',
    customer_id: 'customer-1',
    flock_id: 'flock-1',
    hatchery_id: 'hatchery-1',
    audit_date: '2026-07-28',
    scope: 'house',
    setter_identity: null,
    hatcher_identity: null,
    approved_session_id: null,
    approved_panel_row_id: null,
  }
}
