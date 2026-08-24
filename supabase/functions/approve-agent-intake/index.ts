import { createClient } from 'npm:@supabase/supabase-js@2.110.8'

import {
  AgentIntakeApprovalValidationError,
  type ApprovalAuditSessionRow,
  type ApprovalIntakeRow,
  prepareAgentIntakeApproval,
  type PreparedAgentIntakeApproval,
} from '../_shared/agent_intake_approval.ts'

interface ApprovalUser {
  id: string
}

interface ApprovalProfile {
  role: string
  status: string
}

interface ApprovalCommitResult {
  intake_id: string
  audit_session_id: string
  panel_row_id: string
  already_approved: boolean
}

export interface ApproveAgentIntakeDependencies {
  authenticate(authorization: string): Promise<ApprovalUser | null>
  loadProfile(userId: string): Promise<ApprovalProfile | null>
  loadIntake(intakeId: string): Promise<ApprovalIntakeRow | null>
  loadAuditSession(
    auditSessionId: string,
  ): Promise<ApprovalAuditSessionRow | null>
  commit(
    prepared: PreparedAgentIntakeApproval,
    reviewerId: string,
    approvedAt: string,
  ): Promise<ApprovalCommitResult>
  createId(): string
  now(): Date
}

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

export async function handleApproveAgentIntake(
  request: Request,
  deps: ApproveAgentIntakeDependencies,
): Promise<Response> {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (request.method !== 'POST') {
    return json(405, { error: 'Method not allowed.' })
  }
  const authorization = request.headers.get('Authorization')?.trim()
  if (!authorization) {
    return json(401, { error: 'Sign in as an admin to approve intakes.' })
  }
  const user = await deps.authenticate(authorization)
  if (!user) {
    return json(401, { error: 'Your administrator session is not valid.' })
  }
  const profile = await deps.loadProfile(user.id)
  if (profile?.role !== 'admin' || profile.status !== 'approved') {
    return json(403, {
      error: 'Only an approved app administrator can approve intakes.',
    })
  }

  let body: Record<string, unknown>
  try {
    body = record(await request.json())
  } catch (_) {
    return json(400, { error: 'Invalid request body.' })
  }
  const intakeId = text(body.intakeId)
  const targetSessionId = optionalText(body.targetSessionId)
  const expectedSummaryVersion = positiveInteger(body.expectedSummaryVersion)
  if (!intakeId || expectedSummaryVersion === null) {
    return json(400, {
      error: 'Intake ID and expected summary version are required.',
    })
  }

  const intake = await deps.loadIntake(intakeId)
  if (!intake) return json(404, { error: 'The intake no longer exists.' })
  if (intake.approved_panel_row_id && intake.approved_session_id) {
    if (
      intake.summary_version !== expectedSummaryVersion ||
      (targetSessionId && targetSessionId !== intake.approved_session_id)
    ) {
      return json(409, {
        error: 'The intake approval no longer matches this review.',
      })
    }
    return json(200, {
      intake_id: intake.id,
      audit_session_id: intake.approved_session_id,
      panel_row_id: intake.approved_panel_row_id,
      already_approved: true,
    })
  }

  const targetSession = targetSessionId
    ? await deps.loadAuditSession(targetSessionId)
    : null
  const approvedAt = deps.now().toISOString()
  let prepared: PreparedAgentIntakeApproval
  try {
    prepared = prepareAgentIntakeApproval({
      intake,
      expectedSummaryVersion,
      targetSession,
      requestedTargetSessionId: targetSessionId,
      panelRowId: deps.createId(),
      approvedAt,
    })
  } catch (error) {
    if (error instanceof AgentIntakeApprovalValidationError) {
      const status = error.code === 'not_found'
        ? 404
        : error.code === 'stale_summary' ||
            error.code === 'target_mismatch' ||
            error.code === 'not_ready'
        ? 409
        : 400
      return json(status, { error: error.message, code: error.code })
    }
    return json(400, { error: 'The intake could not be validated.' })
  }

  try {
    const result = await deps.commit(prepared, user.id, approvedAt)
    if (result.intake_id !== intake.id) {
      return json(500, { error: 'Approval result did not match the intake.' })
    }
    return json(200, { ...result })
  } catch (_) {
    return json(409, {
      error: 'The intake changed during approval. Refresh and try again.',
    })
  }
}

export function serveApproveAgentIntake(
  request: Request,
): Promise<Response> | Response {
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json(500, { error: 'Intake approval is not configured.' })
  }
  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  return handleApproveAgentIntake(request, {
    async authenticate(authorization) {
      const callerClient = createClient(supabaseUrl, anonKey, {
        global: { headers: { Authorization: authorization } },
        auth: { persistSession: false, autoRefreshToken: false },
      })
      const { data, error } = await callerClient.auth.getUser()
      return error || !data.user ? null : { id: data.user.id }
    },
    async loadProfile(userId) {
      const { data, error } = await adminClient
        .from('profiles')
        .select('role, status')
        .eq('id', userId)
        .maybeSingle()
      return error || !data ? null : data
    },
    async loadIntake(intakeId) {
      const { data, error } = await adminClient
        .from('agent_intake_sessions')
        .select('*')
        .eq('id', intakeId)
        .maybeSingle()
      if (error) throw error
      return data as ApprovalIntakeRow | null
    },
    async loadAuditSession(auditSessionId) {
      const { data, error } = await adminClient
        .from('audit_sessions')
        .select('id, customer_id, flock_id, hatchery_id, date')
        .eq('id', auditSessionId)
        .maybeSingle()
      if (error) throw error
      return data as ApprovalAuditSessionRow | null
    },
    async commit(prepared, reviewerId, approvedAt) {
      const { data, error } = await adminClient.rpc('approve_agent_intake', {
        p_intake_id: prepared.intakeId,
        p_expected_summary_version: prepared.summaryVersion,
        p_target_session_id: prepared.targetSessionId,
        p_remote_table: prepared.remoteTable,
        p_station_key: prepared.stationKey,
        p_panel_row_id: prepared.panelRowId,
        p_panel_payload: { ...prepared.panelPayload, created_by: reviewerId },
        p_reviewer_id: reviewerId,
        p_approved_at: approvedAt,
      })
      if (error) throw error
      return singleResult(data)
    },
    createId: () => crypto.randomUUID(),
    now: () => new Date(),
  })
}

if (import.meta.main) {
  Deno.serve(serveApproveAgentIntake)
}

function singleResult(value: unknown): ApprovalCommitResult {
  const candidate = Array.isArray(value)
    ? (value.length === 1 ? value[0] : null)
    : value
  const row = record(candidate)
  const intakeId = text(row.intake_id)
  const auditSessionId = text(row.audit_session_id)
  const panelRowId = text(row.panel_row_id)
  if (!intakeId || !auditSessionId || !panelRowId) {
    throw new Error('Invalid approval result')
  }
  return {
    intake_id: intakeId,
    audit_session_id: auditSessionId,
    panel_row_id: panelRowId,
    already_approved: row.already_approved === true,
  }
}

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {}
}

function text(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null
}

function optionalText(value: unknown): string | null {
  return value === null || value === undefined ? null : text(value)
}

function positiveInteger(value: unknown): number | null {
  return typeof value === 'number' && Number.isInteger(value) && value > 0
    ? value
    : null
}
