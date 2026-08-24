import { assertEquals, assertObjectMatch } from 'jsr:@std/assert@1.0.14'

import {
  type ApproveAgentIntakeDependencies,
  handleApproveAgentIntake,
} from './index.ts'

Deno.test('requires a valid approved app administrator', async () => {
  const missing = await handleApproveAgentIntake(request(), dependencies())
  assertEquals(missing.status, 401)

  const notAdmin = dependencies()
  notAdmin.loadProfile = () =>
    Promise.resolve({ role: 'auditor', status: 'approved' })
  const denied = await handleApproveAgentIntake(
    request(undefined, 'Bearer user'),
    notAdmin,
  )
  assertEquals(denied.status, 403)
  assertEquals(notAdminState(notAdmin).commitCalls, 0)
})

Deno.test('approves a generic station through the atomic commit boundary', async () => {
  const deps = dependencies()
  const response = await handleApproveAgentIntake(
    request({
      intakeId: 'intake-1',
      expectedSummaryVersion: 2,
      targetSessionId: 'audit-1',
    }, 'Bearer admin'),
    deps,
  )

  assertEquals(response.status, 200)
  assertObjectMatch(await response.json(), {
    intake_id: 'intake-1',
    audit_session_id: 'audit-1',
    panel_row_id: 'panel-1',
    already_approved: false,
  })
  const state = notAdminState(deps)
  assertEquals(state.commitCalls, 1)
  assertEquals(state.prepared?.remoteTable, 'chick_weights')
  assertEquals(state.prepared?.summaryVersion, 2)
  assertEquals(state.prepared?.panelPayload.weights_json, '[39.5,40,41.25]')
})

Deno.test('rejects stale versions and cross-customer target visits', async () => {
  const stale = await handleApproveAgentIntake(
    request({
      intakeId: 'intake-1',
      expectedSummaryVersion: 1,
    }, 'Bearer admin'),
    dependencies(),
  )
  assertEquals(stale.status, 409)

  const mismatched = dependencies()
  mismatched.loadAuditSession = () =>
    Promise.resolve({
      id: 'audit-1',
      customer_id: 'wrong-customer',
      flock_id: 'flock-1',
      hatchery_id: 'hatchery-1',
      date: '2026-07-28',
    })
  const denied = await handleApproveAgentIntake(
    request({
      intakeId: 'intake-1',
      expectedSummaryVersion: 2,
      targetSessionId: 'audit-1',
    }, 'Bearer admin'),
    mismatched,
  )
  assertEquals(denied.status, 409)
  assertEquals(notAdminState(mismatched).commitCalls, 0)
})

Deno.test('returns the existing IDs on an idempotent retry', async () => {
  const deps = dependencies()
  const original = await deps.loadIntake('intake-1')
  deps.loadIntake = () =>
    Promise.resolve({
      ...original!,
      state: 'approved',
      approved_session_id: 'audit-existing',
      approved_panel_row_id: 'panel-existing',
    })
  const response = await handleApproveAgentIntake(
    request({
      intakeId: 'intake-1',
      expectedSummaryVersion: 2,
    }, 'Bearer admin'),
    deps,
  )

  assertEquals(response.status, 200)
  assertObjectMatch(await response.json(), {
    audit_session_id: 'audit-existing',
    panel_row_id: 'panel-existing',
    already_approved: true,
  })
  assertEquals(notAdminState(deps).commitCalls, 0)
})

function request(
  body: Record<string, unknown> = {
    intakeId: 'intake-1',
    expectedSummaryVersion: 2,
  },
  authorization?: string,
) {
  const headers = new Headers({ 'Content-Type': 'application/json' })
  if (authorization) headers.set('Authorization', authorization)
  return new Request('https://example.test/approve-agent-intake', {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  })
}

interface FakeState {
  commitCalls: number
  prepared: Parameters<ApproveAgentIntakeDependencies['commit']>[0] | null
}

const states = new WeakMap<ApproveAgentIntakeDependencies, FakeState>()

function notAdminState(deps: ApproveAgentIntakeDependencies): FakeState {
  return states.get(deps)!
}

function dependencies(): ApproveAgentIntakeDependencies {
  const state: FakeState = { commitCalls: 0, prepared: null }
  const deps: ApproveAgentIntakeDependencies = {
    authenticate: () => Promise.resolve({ id: 'admin-1' }),
    loadProfile: () => Promise.resolve({ role: 'admin', status: 'approved' }),
    loadIntake: () => Promise.resolve(weightIntake()),
    loadAuditSession: (id) =>
      Promise.resolve({
        id,
        customer_id: 'customer-1',
        flock_id: 'flock-1',
        hatchery_id: 'hatchery-1',
        date: '2026-07-28',
      }),
    commit: (prepared) => {
      state.commitCalls++
      state.prepared = prepared
      return Promise.resolve({
        intake_id: prepared.intakeId,
        audit_session_id: prepared.targetSessionId ?? 'audit-new',
        panel_row_id: prepared.panelRowId,
        already_approved: false,
      })
    },
    createId: () => 'panel-1',
    now: () => new Date('2026-07-28T13:00:00.000Z'),
  }
  states.set(deps, state)
  return deps
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
    house_identity: 'House 1',
    trolley_identity: null,
    tray_identity: null,
    position_identity: null,
    setter_identity: null,
    hatcher_identity: null,
    approved_session_id: null,
    approved_panel_row_id: null,
  }
}
