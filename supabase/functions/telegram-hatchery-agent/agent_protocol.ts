export interface AgentScope {
  staffLinkId: string
  accessRole: 'customer' | 'admin'
  allowedCustomerIds: readonly string[]
}

export type AgentToolName =
  | 'get_user_scope'
  | 'list_customers'
  | 'resolve_customer_flock'
  | 'get_customer_context'
  | 'list_customer_flocks'
  | 'list_customer_hatcheries'
  | 'list_customer_audits'
  | 'select_audit_option'
  | 'get_audit_summary'
  | 'get_selected_audit_breakouts'
  | 'get_breed_benchmark'
  | 'get_egg_breakout_benchmark'
  | 'get_operational_standards'
  | 'compare_selected_audit_to_benchmark'
  | 'get_flock_context'
  | 'query_station_records'
  | 'compare_station_metrics'
  | 'get_record_provenance'
  | 'list_applicable_stations'
  | 'load_station_schema'
  | 'propose_intake'
  | 'start_intake'
  | 'record_station_values'
  | 'get_intake_status'
  | 'create_station_summary'
  | 'confirm_station_summary'
  | 'submit_station_for_review'
  | 'pause_intake'
  | 'resume_intake'
  | 'cancel_intake'
  | 'list_legacy_draft_questions'
  | 'answer_legacy_draft_question'

export interface AgentToolResult {
  ok: boolean
  code: string
  data: Record<string, unknown> | null
}

export interface AgentToolCall {
  id: string
  name: string
  arguments: Record<string, unknown>
  sequence?: number
}

export interface AgentToolExecutionInput {
  scope: AgentScope
  conversationId: string
  activeVisitId: string | null
  conversationTurnId?: string
  conversationTurnIndex?: number
  /**
   * The conversation's CURRENT context epoch. `/new` (and the app's clear
   * control) bumps it, and every read that reconstructs conversational state
   * must filter on it — otherwise "start over" doesn't, and a tool can serve
   * the user a list they explicitly threw away.
   */
  conversationContextEpoch?: number
  toolCallSequence?: number
  toolCallId?: string
  arguments: Readonly<Record<string, unknown>>
}
