import { agentStationRegistry } from './station_registry.generated.ts'
import { deriveStationAdapter } from '../telegram-hatchery-agent/agent_station_adapter.ts'

export interface ApprovalIntakeRow {
  id: string
  schema_key: string
  schema_version: number
  state: string
  summary_version: number
  summary_snapshot_json: unknown
  working_values_json: unknown
  user_confirmed_at: string | null
  customer_id: string | null
  flock_id: string | null
  hatchery_id: string | null
  audit_date: string
  scope: string | null
  setter_identity: string | null
  hatcher_identity: string | null
  approved_session_id: string | null
  approved_panel_row_id: string | null
}

export interface ApprovalAuditSessionRow {
  id: string
  customer_id: string
  flock_id: string
  hatchery_id: string
  date: string
}

export interface PreparedAgentIntakeApproval {
  intakeId: string
  schemaKey: string
  schemaVersion: number
  summaryVersion: number
  stationKey: string
  remoteTable: string
  panelRowId: string
  targetSessionId: string | null
  panelPayload: Readonly<Record<string, unknown>>
}

export class AgentIntakeApprovalValidationError extends Error {
  constructor(
    message: string,
    readonly code:
      | 'not_found'
      | 'not_ready'
      | 'stale_summary'
      | 'unknown_schema'
      | 'invalid_context'
      | 'invalid_values'
      | 'target_mismatch',
  ) {
    super(message)
  }
}

export function prepareAgentIntakeApproval(input: {
  intake: ApprovalIntakeRow
  expectedSummaryVersion: number
  targetSession: ApprovalAuditSessionRow | null
  requestedTargetSessionId: string | null
  panelRowId: string
  approvedAt: string
}): PreparedAgentIntakeApproval {
  const {
    intake,
    expectedSummaryVersion,
    targetSession,
    requestedTargetSessionId,
    panelRowId,
    approvedAt,
  } = input
  if (
    intake.state !== 'awaiting_admin_review' ||
    !intake.user_confirmed_at
  ) {
    throw new AgentIntakeApprovalValidationError(
      'The intake is not ready for administrator review.',
      'not_ready',
    )
  }
  const summary = record(intake.summary_snapshot_json)
  if (
    intake.summary_version !== expectedSummaryVersion ||
    integer(summary.version) !== expectedSummaryVersion
  ) {
    throw new AgentIntakeApprovalValidationError(
      'The confirmed summary changed. Refresh before approving.',
      'stale_summary',
    )
  }
  if (
    text(summary.schemaKey) !== intake.schema_key ||
    integer(summary.schemaVersion) !== intake.schema_version
  ) {
    throw new AgentIntakeApprovalValidationError(
      'The confirmed summary does not match its station schema.',
      'stale_summary',
    )
  }
  const schema = agentStationRegistry.stations.find((candidate) =>
    candidate.schemaKey === intake.schema_key &&
    candidate.version === intake.schema_version
  )
  if (!schema) {
    throw new AgentIntakeApprovalValidationError(
      'The station schema is not supported.',
      'unknown_schema',
    )
  }
  if (
    !intake.customer_id ||
    !intake.flock_id ||
    !intake.hatchery_id ||
    !intake.scope ||
    !schema.allowedLayers.some((layer) => layer === intake.scope)
  ) {
    throw new AgentIntakeApprovalValidationError(
      'The intake context is incomplete or invalid.',
      'invalid_context',
    )
  }
  if (
    intake.scope === 'setter_hatcher' &&
    (!intake.setter_identity || !intake.hatcher_identity)
  ) {
    throw new AgentIntakeApprovalValidationError(
      'Setter and hatcher identities are required for this intake.',
      'invalid_context',
    )
  }
  if (requestedTargetSessionId && !targetSession) {
    throw new AgentIntakeApprovalValidationError(
      'The selected audit visit no longer exists.',
      'not_found',
    )
  }
  if (
    targetSession &&
    (
      targetSession.id !== requestedTargetSessionId ||
      targetSession.customer_id !== intake.customer_id ||
      targetSession.flock_id !== intake.flock_id ||
      targetSession.hatchery_id !== intake.hatchery_id ||
      targetSession.date !== intake.audit_date
    )
  ) {
    throw new AgentIntakeApprovalValidationError(
      'The selected audit visit does not match the intake.',
      'target_mismatch',
    )
  }

  const values = record(intake.working_values_json)
  let adapter
  try {
    adapter = deriveStationAdapter(schema, values)
  } catch (_) {
    throw new AgentIntakeApprovalValidationError(
      'The reviewed station values are incomplete or invalid.',
      'invalid_values',
    )
  }
  if (adapter.persistence.length !== 1) {
    throw new AgentIntakeApprovalValidationError(
      'The station persistence mapping is invalid.',
      'unknown_schema',
    )
  }
  const persistence = adapter.persistence[0]
  const panelPayload: Record<string, unknown> = {
    id: panelRowId,
    session_id: requestedTargetSessionId,
    customer_id: intake.customer_id,
    flock_id: intake.flock_id,
    hatchery_id: intake.hatchery_id,
    date: intake.audit_date,
    setter: intake.setter_identity,
    hatcher: intake.hatcher_identity,
    notes:
      `AI-assisted ${schema.schemaKey}@${schema.version} intake ${intake.id}`,
    created_at: approvedAt,
    updated_at: approvedAt,
    sync_status: 'synced',
    last_synced_at: approvedAt,
    ...persistence.values,
  }
  return {
    intakeId: intake.id,
    schemaKey: schema.schemaKey,
    schemaVersion: schema.version,
    summaryVersion: expectedSummaryVersion,
    stationKey: schema.stationKey,
    remoteTable: persistence.remoteTable,
    panelRowId,
    targetSessionId: requestedTargetSessionId,
    panelPayload,
  }
}

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {}
  return value as Record<string, unknown>
}

function text(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value : null
}

function integer(value: unknown): number | null {
  return typeof value === 'number' && Number.isInteger(value) ? value : null
}
