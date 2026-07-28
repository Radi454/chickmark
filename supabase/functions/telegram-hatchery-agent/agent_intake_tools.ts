import {
  type AgentStationSchema,
  applicableStationSchemas,
  requireStationSchema,
} from '../_shared/station_registry.generated.ts'
import {
  type AgentClarification,
  type AgentConversation,
  type AgentIntakeClient,
  type AgentIntakeContext,
  type AgentIntakeSession,
  type AgentIntakeStore,
  type AgentIntakeValueUpdate,
  type AgentIntakeVisit,
  type AgentPendingAction,
  type AgentSummarySnapshot,
} from './agent_intake_store.ts'
import type {
  AgentScope,
  AgentToolExecutionInput,
  AgentToolName,
  AgentToolResult,
} from './agent_protocol.ts'
import {
  calculateStationValues,
  validateStationValueSet,
} from './agent_station_adapter.ts'
import type { AgentToolHandler } from './agent_tools.ts'

export interface AgentIntakeContextRequest {
  customerId: string
  flockId: string
  hatcheryId: string
  auditDate: string
  layer: string
  setterIdentity: string | null
  hatcherIdentity: string | null
}

export interface AgentIntakeContextResolver {
  resolveFlockSector(
    scope: AgentScope,
    requested: { customerId: string; flockId: string },
  ): Promise<string | null>
  resolve(
    scope: AgentScope,
    requested: AgentIntakeContextRequest,
  ): Promise<AgentIntakeContext | null>
}

export function createSupabaseAgentIntakeContextResolver(
  client: AgentIntakeClient,
): AgentIntakeContextResolver {
  return {
    async resolveFlockSector(scope, requested) {
      if (!scope.allowedCustomerIds.includes(requested.customerId)) return null
      const result = await client
        .from('flocks')
        .select('id, customer_id, sector_key')
        .eq('id', requested.flockId)
        .maybeSingle()
      if (result.error || !result.data) return null
      return optionalText(result.data.customer_id) === requested.customerId
        ? optionalText(result.data.sector_key)
        : null
    },
    async resolve(scope, requested) {
      if (!scope.allowedCustomerIds.includes(requested.customerId)) return null
      const [customerResult, flockResult, hatcheryResult] = await Promise.all([
        client
          .from('customers')
          .select('id, name')
          .eq('id', requested.customerId)
          .maybeSingle(),
        client
          .from('flocks')
          .select('id, customer_id, flock_id, sector_key')
          .eq('id', requested.flockId)
          .maybeSingle(),
        client
          .from('hatcheries')
          .select('id, customer_id, name')
          .eq('id', requested.hatcheryId)
          .maybeSingle(),
      ])
      if (
        customerResult.error || flockResult.error || hatcheryResult.error ||
        !customerResult.data || !flockResult.data || !hatcheryResult.data
      ) return null
      const customerId = optionalText(customerResult.data.id)
      const flockCustomerId = optionalText(flockResult.data.customer_id)
      const hatcheryCustomerId = optionalText(
        hatcheryResult.data.customer_id,
      )
      const sectorKey = optionalText(flockResult.data.sector_key)
      if (
        customerId !== requested.customerId ||
        flockCustomerId !== requested.customerId ||
        hatcheryCustomerId !== requested.customerId ||
        !sectorKey
      ) return null
      const customerName = optionalText(customerResult.data.name)
      const flockName = optionalText(flockResult.data.flock_id)
      const hatcheryName = optionalText(hatcheryResult.data.name)
      if (!customerName || !flockName || !hatcheryName) return null
      return {
        customerId,
        customerName,
        flockId: requested.flockId,
        flockName,
        hatcheryId: requested.hatcheryId,
        hatcheryName,
        auditDate: requested.auditDate,
        layer: requested.layer,
        setterIdentity: requested.setterIdentity,
        hatcherIdentity: requested.hatcherIdentity,
        sectorKey,
      }
    },
  }
}

export interface AgentIntakeToolDependencies {
  store: AgentIntakeStore
  contextResolver: AgentIntakeContextResolver
  now?: () => Date
  createId?: () => string
  minimumConfidence?: number
}

interface ValueCandidate {
  fieldKey: string
  value: unknown
  sourcePhrase: string
  confidence: number
}

interface RejectedValue {
  fieldKey: string
  sourcePhrase: string
  reason: string
  inputIndex: number
}

export function createAgentIntakeToolHandlers(
  dependencies: AgentIntakeToolDependencies,
): Partial<Record<AgentToolName, AgentToolHandler>> {
  const now = dependencies.now ?? (() => new Date())
  const createId = dependencies.createId ?? (() => crypto.randomUUID())
  const minimumConfidence = dependencies.minimumConfidence ?? 0.8
  return {
    propose_intake: (input) =>
      proposeIntake(dependencies.store, input, now, createId),
    start_intake: (input) => startIntake(dependencies, input, now, createId),
    record_station_values: (input) =>
      recordStationValues(
        dependencies.store,
        input,
        now,
        minimumConfidence,
      ),
    get_intake_status: (input) => getIntakeStatus(dependencies.store, input),
    create_station_summary: (input) =>
      createStationSummary(dependencies.store, input, now),
    confirm_station_summary: (input) =>
      confirmStationSummary(dependencies.store, input, now),
    submit_station_for_review: (input) =>
      submitStationForReview(dependencies.store, input, now),
    pause_intake: (input) =>
      changeIntakeState(dependencies.store, input, now, 'pause'),
    resume_intake: (input) =>
      changeIntakeState(dependencies.store, input, now, 'resume'),
    cancel_intake: (input) =>
      changeIntakeState(dependencies.store, input, now, 'cancel'),
    load_station_schema: (input) => Promise.resolve(loadSchemaResult(input)),
    list_applicable_stations: (input) =>
      listApplicableStations(dependencies.contextResolver, input),
  }
}

async function proposeIntake(
  store: AgentIntakeStore,
  input: AgentToolExecutionInput,
  now: () => Date,
  createId: () => string,
): Promise<AgentToolResult> {
  const turn = requiredTurn(input)
  if (!turn) return infrastructureContextRequired()
  const customerId = input.arguments.customerId as string
  if (!input.scope.allowedCustomerIds.includes(customerId)) return scopeDenied()
  const conversation = await authorizedConversation(store, input)
  if (!conversation) return scopeDenied()
  const proposedAt = now()
  const action: AgentPendingAction = {
    id: createId(),
    kind: 'station_intake',
    customerId,
    proposedAt: proposedAt.toISOString(),
    proposedTurnId: turn.id,
    proposedTurnIndex: turn.index,
    expiresAt: new Date(proposedAt.getTime() + 15 * 60_000).toISOString(),
    expiresAfterTurnIndex: turn.index + 5,
  }
  const updated = await store.updateConversation(
    conversation.id,
    conversation.stateVersion,
    { pendingAction: action, updatedAt: proposedAt.toISOString() },
  )
  if (!updated) return stateConflict()
  return ok({
    pendingActionId: action.id,
    customerId,
    expiresAt: action.expiresAt,
    expiresAfterTurnIndex: action.expiresAfterTurnIndex,
  })
}

async function startIntake(
  dependencies: AgentIntakeToolDependencies,
  input: AgentToolExecutionInput,
  now: () => Date,
  createId: () => string,
): Promise<AgentToolResult> {
  const turn = requiredTurn(input)
  if (!turn) return infrastructureContextRequired()
  const conversation = await authorizedConversation(dependencies.store, input)
  if (!conversation) return scopeDenied()
  const action = conversation.pendingAction
  if (!action || action.id !== input.arguments.pendingActionId) {
    return { ok: false, code: 'confirmation_required', data: null }
  }
  if (
    turn.id === action.proposedTurnId ||
    turn.index <= action.proposedTurnIndex
  ) {
    return { ok: false, code: 'confirmation_required', data: null }
  }
  const currentTime = now()
  if (
    currentTime.getTime() > Date.parse(action.expiresAt) ||
    turn.index > action.expiresAfterTurnIndex
  ) {
    return { ok: false, code: 'pending_action_expired', data: null }
  }

  const requested = requestedContext(input)
  if (
    action.customerId !== requested.customerId ||
    !input.scope.allowedCustomerIds.includes(requested.customerId)
  ) return scopeDenied()
  const context = await dependencies.contextResolver.resolve(
    input.scope,
    requested,
  )
  if (!context || context.customerId !== requested.customerId) {
    return scopeDenied()
  }
  const schema = loadSchema(input.arguments)
  if (!schema) return { ok: false, code: 'unknown_schema', data: null }
  if (
    !schema.sectorKeys.includes(context.sectorKey) ||
    !schema.allowedLayers.includes(context.layer)
  ) {
    return { ok: false, code: 'schema_not_applicable', data: null }
  }
  if (
    context.layer === 'setter_hatcher' &&
    (!context.setterIdentity || !context.hatcherIdentity)
  ) {
    return { ok: false, code: 'context_incomplete', data: null }
  }

  let visit: AgentIntakeVisit | null = null
  if (conversation.activeVisitId) {
    visit = await dependencies.store.loadVisit(conversation.activeVisitId)
    if (visit && !sameVisitContext(visit, context)) {
      return { ok: false, code: 'visit_context_mismatch', data: null }
    }
    if (visit?.state === 'completed' || visit?.state === 'cancelled') {
      visit = null
    }
  }
  if (!visit) {
    visit = {
      id: createId(),
      conversationId: conversation.id,
      customerId: context.customerId,
      flockId: context.flockId,
      hatcheryId: context.hatcheryId,
      auditDate: context.auditDate,
      state: 'collecting',
      approvedSessionId: null,
      createdAt: currentTime.toISOString(),
      updatedAt: currentTime.toISOString(),
    }
    await dependencies.store.createVisit(visit)
  }
  const session: AgentIntakeSession = {
    id: createId(),
    visitId: visit.id,
    staffLinkId: conversation.staffLinkId,
    telegramChatId: conversation.telegramChatId,
    schemaKey: schema.schemaKey,
    schemaVersion: schema.version,
    state: 'collecting',
    language: 'mixed',
    rowVersion: 1,
    context,
    workingValues: {},
    pendingClarification: null,
    summaryVersion: 0,
    summarySnapshot: null,
    userConfirmedAt: null,
    lastToolEventId: input.toolCallId ?? null,
    createdAt: currentTime.toISOString(),
    updatedAt: currentTime.toISOString(),
  }
  const updatedConversation = await dependencies.store.updateConversation(
    conversation.id,
    conversation.stateVersion,
    {
      pendingAction: null,
      activeVisitId: visit.id,
      updatedAt: currentTime.toISOString(),
    },
  )
  if (!updatedConversation) return stateConflict()
  try {
    await dependencies.store.createSession(session)
  } catch (_) {
    return { ok: false, code: 'state_conflict', data: null }
  }
  return ok({
    intakeId: session.id,
    visitId: visit.id,
    schemaKey: session.schemaKey,
    schemaVersion: session.schemaVersion,
    state: session.state,
    rowVersion: session.rowVersion,
  })
}

async function recordStationValues(
  store: AgentIntakeStore,
  input: AgentToolExecutionInput,
  now: () => Date,
  minimumConfidence: number,
): Promise<AgentToolResult> {
  const session = await authorizedSession(store, input)
  if (!session) return scopeDenied()
  const expectedVersion = input.arguments.expectedRowVersion as number
  if (session.rowVersion !== expectedVersion) return stateConflict()
  if (!editableStates.has(session.state)) {
    return { ok: false, code: 'intake_not_editable', data: null }
  }
  const schema = loadSessionSchema(session)
  if (!schema) return { ok: false, code: 'unknown_schema', data: null }
  const values = { ...session.workingValues }
  const candidates: Array<{
    candidate: ValueCandidate
    field: Record<string, unknown>
    inputIndex: number
  }> = []
  const rejected: RejectedValue[] = []
  for (
    const [inputIndex, raw] of (input.arguments.values as unknown[]).entries()
  ) {
    const candidate = parseCandidate(raw)
    if (!candidate) {
      rejected.push({
        fieldKey: isRecord(raw) ? optionalText(raw.fieldKey) ?? '' : '',
        sourcePhrase: isRecord(raw) ? optionalText(raw.sourcePhrase) ?? '' : '',
        reason: 'invalid_candidate',
        inputIndex,
      })
      continue
    }
    const field = schema.fields.find((item) =>
      item.fieldKey === candidate.fieldKey
    )
    if (!field) {
      rejected.push({
        fieldKey: candidate.fieldKey,
        sourcePhrase: candidate.sourcePhrase,
        reason: 'unknown_field',
        inputIndex,
      })
      continue
    }
    if (candidate.confidence < minimumConfidence) {
      rejected.push({
        fieldKey: candidate.fieldKey,
        sourcePhrase: candidate.sourcePhrase,
        reason: 'low_confidence',
        inputIndex,
      })
      continue
    }
    const reason = firstIssueReason(schema, {
      ...values,
      [candidate.fieldKey]: candidate.value,
    }, candidate.fieldKey)
    if (reason) {
      rejected.push({
        fieldKey: candidate.fieldKey,
        sourcePhrase: candidate.sourcePhrase,
        reason,
        inputIndex,
      })
      continue
    }
    candidates.push({ candidate, field, inputIndex })
  }

  const proposedValues = { ...values }
  for (const { candidate } of candidates) {
    proposedValues[candidate.fieldKey] = structuredClone(candidate.value)
  }
  const directlyAccepted = new Map<string, ValueCandidate>()
  for (const { candidate, field, inputIndex } of candidates) {
    const reason = firstIssueReason(
      schema,
      proposedValues,
      candidate.fieldKey,
    )
    if (reason) {
      rejected.push({
        fieldKey: candidate.fieldKey,
        sourcePhrase: candidate.sourcePhrase,
        reason,
        inputIndex,
      })
      continue
    }
    directlyAccepted.set(candidate.fieldKey, candidate)
  }

  const accepted: ValueCandidate[] = []
  for (const { candidate, inputIndex } of candidates) {
    if (directlyAccepted.get(candidate.fieldKey) !== candidate) continue
    const dependentConflict = schema.fields.some((field) => {
      const validation = isRecord(field.validation) ? field.validation : {}
      if (validation.maxFieldKey !== candidate.fieldKey) return false
      const dependentKey = field.fieldKey
      if (typeof dependentKey !== 'string') return false
      const replacement = directlyAccepted.get(dependentKey)
      const dependentValue = replacement?.value ?? values[dependentKey]
      return typeof candidate.value === 'number' &&
        typeof dependentValue === 'number' &&
        dependentValue > candidate.value
    })
    if (dependentConflict) {
      rejected.push({
        fieldKey: candidate.fieldKey,
        sourcePhrase: candidate.sourcePhrase,
        reason: 'dependent_value_conflict',
        inputIndex,
      })
      continue
    }
    values[candidate.fieldKey] = structuredClone(candidate.value)
    accepted.push(candidate)
  }
  rejected.sort((left, right) => left.inputIndex - right.inputIndex)
  const publicRejected = rejected.map(({ inputIndex: _, ...value }) => value)
  if (accepted.length === 0) {
    return ok({
      acceptedKeys: [],
      rejected: publicRejected,
      missingRequiredKeys: missingRequired(schema, values),
      complete: false,
      rowVersion: session.rowVersion,
      summaryInvalidated: false,
    })
  }

  const timestamp = now().toISOString()
  const missing = missingRequired(schema, values)
  const summaryInvalidated = session.summarySnapshot !== null ||
    session.userConfirmedAt !== null
  const clarification = rejected.length === 0
    ? null
    : clarificationFor(rejected)
  const updated = await store.updateSession(session.id, expectedVersion, {
    workingValues: values,
    pendingClarification: clarification,
    summarySnapshot: null,
    userConfirmedAt: null,
    state: rejected.length > 0
      ? 'awaiting_clarification'
      : missing.length === 0
      ? 'ready_for_summary'
      : 'collecting',
    lastToolEventId: input.toolCallId ?? session.lastToolEventId,
    updatedAt: timestamp,
  })
  if (!updated) return stateConflict()
  const valueUpdates: AgentIntakeValueUpdate[] = accepted.map((candidate) => ({
    intakeSessionId: session.id,
    fieldKey: candidate.fieldKey,
    value: candidate.value,
    sourcePhrase: candidate.sourcePhrase,
    confidence: candidate.confidence,
    clarificationReason: null,
    toolCallId: input.toolCallId ?? null,
    updatedAt: timestamp,
  }))
  await store.upsertValues(valueUpdates)
  return ok({
    acceptedKeys: accepted.map((candidate) => candidate.fieldKey),
    rejected: publicRejected,
    missingRequiredKeys: missing,
    complete: missing.length === 0 && rejected.length === 0,
    rowVersion: updated.rowVersion,
    summaryInvalidated,
  })
}

async function getIntakeStatus(
  store: AgentIntakeStore,
  input: AgentToolExecutionInput,
): Promise<AgentToolResult> {
  const session = await authorizedSession(store, input)
  if (!session) return scopeDenied()
  const schema = loadSessionSchema(session)
  if (!schema) return { ok: false, code: 'unknown_schema', data: null }
  const missing = missingRequired(schema, session.workingValues)
  return ok({
    intakeId: session.id,
    visitId: session.visitId,
    state: session.state,
    rowVersion: session.rowVersion,
    values: session.workingValues,
    missingRequiredKeys: missing,
    pendingClarification: session.pendingClarification,
    complete: missing.length === 0,
    summaryVersion: session.summaryVersion,
    hasCurrentSummary: session.summarySnapshot !== null,
    userConfirmed: session.userConfirmedAt !== null,
  })
}

async function createStationSummary(
  store: AgentIntakeStore,
  input: AgentToolExecutionInput,
  now: () => Date,
): Promise<AgentToolResult> {
  const session = await authorizedSession(store, input)
  if (!session) return scopeDenied()
  const expectedVersion = input.arguments.expectedRowVersion as number
  if (session.rowVersion !== expectedVersion) return stateConflict()
  const schema = loadSessionSchema(session)
  if (!schema) return { ok: false, code: 'unknown_schema', data: null }
  const missing = missingRequired(schema, session.workingValues)
  if (missing.length > 0) {
    return {
      ok: false,
      code: 'intake_incomplete',
      data: { missingRequiredKeys: missing },
    }
  }
  const timestamp = now().toISOString()
  const summary: AgentSummarySnapshot = {
    version: session.summaryVersion + 1,
    schemaKey: schema.schemaKey,
    schemaVersion: schema.version,
    values: structuredClone(session.workingValues),
    calculations: calculateStationValues(schema, session.workingValues),
    generatedAt: timestamp,
  }
  const updated = await store.updateSession(session.id, expectedVersion, {
    state: 'awaiting_user_confirmation',
    pendingClarification: null,
    summaryVersion: summary.version,
    summarySnapshot: summary,
    userConfirmedAt: null,
    lastToolEventId: input.toolCallId ?? session.lastToolEventId,
    updatedAt: timestamp,
  })
  if (!updated) return stateConflict()
  return ok({
    intakeId: session.id,
    rowVersion: updated.rowVersion,
    summaryVersion: summary.version,
    summary,
  })
}

async function confirmStationSummary(
  store: AgentIntakeStore,
  input: AgentToolExecutionInput,
  now: () => Date,
): Promise<AgentToolResult> {
  const session = await authorizedSession(store, input)
  if (!session) return scopeDenied()
  const expectedVersion = input.arguments.expectedRowVersion as number
  if (session.rowVersion !== expectedVersion) return stateConflict()
  const requestedSummaryVersion = input.arguments.summaryVersion as number
  if (
    session.state !== 'awaiting_user_confirmation' ||
    !session.summarySnapshot ||
    requestedSummaryVersion !== session.summaryVersion ||
    requestedSummaryVersion !== session.summarySnapshot.version
  ) {
    return { ok: false, code: 'summary_version_mismatch', data: null }
  }
  const timestamp = now().toISOString()
  const updated = await store.updateSession(session.id, expectedVersion, {
    userConfirmedAt: timestamp,
    lastToolEventId: input.toolCallId ?? session.lastToolEventId,
    updatedAt: timestamp,
  })
  if (!updated) return stateConflict()
  return ok({
    intakeId: session.id,
    state: updated.state,
    rowVersion: updated.rowVersion,
    summaryVersion: updated.summaryVersion,
    userConfirmedAt: updated.userConfirmedAt,
  })
}

async function submitStationForReview(
  store: AgentIntakeStore,
  input: AgentToolExecutionInput,
  now: () => Date,
): Promise<AgentToolResult> {
  const session = await authorizedSession(store, input)
  if (!session) return scopeDenied()
  const expectedVersion = input.arguments.expectedRowVersion as number
  if (session.rowVersion !== expectedVersion) return stateConflict()
  if (!session.summarySnapshot || !session.userConfirmedAt) {
    return { ok: false, code: 'summary_confirmation_required', data: null }
  }
  const timestamp = now().toISOString()
  const updated = await store.updateSession(session.id, expectedVersion, {
    state: 'awaiting_admin_review',
    lastToolEventId: input.toolCallId ?? session.lastToolEventId,
    updatedAt: timestamp,
  })
  if (!updated) return stateConflict()
  await store.updateVisit(session.visitId, {
    state: 'awaiting_admin_review',
    updatedAt: timestamp,
  })
  return ok({
    intakeId: session.id,
    visitId: session.visitId,
    state: updated.state,
    rowVersion: updated.rowVersion,
  })
}

async function changeIntakeState(
  store: AgentIntakeStore,
  input: AgentToolExecutionInput,
  now: () => Date,
  action: 'pause' | 'resume' | 'cancel',
): Promise<AgentToolResult> {
  const session = await authorizedSession(store, input)
  if (!session) return scopeDenied()
  const expectedVersion = input.arguments.expectedRowVersion as number
  if (session.rowVersion !== expectedVersion) return stateConflict()
  if (action === 'resume' && session.state !== 'paused') {
    return { ok: false, code: 'intake_not_paused', data: null }
  }
  if (
    action === 'pause' &&
    (!editableStates.has(session.state) || session.state === 'paused')
  ) {
    return { ok: false, code: 'intake_not_editable', data: null }
  }
  const timestamp = now().toISOString()
  const nextState = action === 'pause'
    ? 'paused'
    : action === 'cancel'
    ? 'cancelled'
    : missingRequired(loadSessionSchema(session)!, session.workingValues)
        .length === 0
    ? 'ready_for_summary'
    : 'collecting'
  const updated = await store.updateSession(session.id, expectedVersion, {
    state: nextState,
    lastToolEventId: input.toolCallId ?? session.lastToolEventId,
    updatedAt: timestamp,
  })
  if (!updated) return stateConflict()
  return ok({
    intakeId: session.id,
    state: updated.state,
    rowVersion: updated.rowVersion,
  })
}

function loadSchemaResult(input: AgentToolExecutionInput): AgentToolResult {
  const schema = loadSchema(input.arguments)
  return schema
    ? ok({
      schemaKey: schema.schemaKey,
      version: schema.version,
      stationKey: schema.stationKey,
      moduleKey: schema.moduleKey,
      names: schema.names,
      allowedLayers: schema.allowedLayers,
      fields: schema.fields.map((field) => ({
        fieldKey: field.fieldKey,
        names: field.names,
        aliases: field.aliases,
        type: field.type,
        unit: field.unit,
        required: field.required,
        explicitZero: field.explicitZero,
        validation: field.validation,
      })),
      calculatedFields: schema.calculations.map((calculation) => ({
        fieldKey: calculation.fieldKey,
        unit: calculation.unit,
      })),
      completion: schema.completion,
    })
    : { ok: false, code: 'unknown_schema', data: null }
}

async function listApplicableStations(
  resolver: AgentIntakeContextResolver,
  input: AgentToolExecutionInput,
): Promise<AgentToolResult> {
  const customerId = input.arguments.customerId as string
  const flockId = input.arguments.flockId as string
  if (!input.scope.allowedCustomerIds.includes(customerId)) return scopeDenied()
  const sectorKey = await resolver.resolveFlockSector(input.scope, {
    customerId,
    flockId,
  })
  if (!sectorKey) return scopeDenied()
  return ok({
    customerId,
    flockId,
    sectorKey,
    stations: applicableStationSchemas([sectorKey]).map((schema) => ({
      schemaKey: schema.schemaKey,
      version: schema.version,
      stationKey: schema.stationKey,
      moduleKey: schema.moduleKey,
      names: schema.names,
      aliases: schema.aliases,
      allowedLayers: schema.allowedLayers,
    })),
  })
}

function requestedContext(
  input: AgentToolExecutionInput,
): AgentIntakeContextRequest {
  return {
    customerId: input.arguments.customerId as string,
    flockId: input.arguments.flockId as string,
    hatcheryId: input.arguments.hatcheryId as string,
    auditDate: input.arguments.auditDate as string,
    layer: input.arguments.layer as string,
    setterIdentity: optionalText(input.arguments.setterIdentity),
    hatcherIdentity: optionalText(input.arguments.hatcherIdentity),
  }
}

async function authorizedConversation(
  store: AgentIntakeStore,
  input: AgentToolExecutionInput,
): Promise<AgentConversation | null> {
  const conversation = await store.loadConversation(input.conversationId)
  return conversation?.staffLinkId === input.scope.staffLinkId
    ? conversation
    : null
}

async function authorizedSession(
  store: AgentIntakeStore,
  input: AgentToolExecutionInput,
): Promise<AgentIntakeSession | null> {
  const session = await store.loadSession(input.arguments.intakeId as string)
  return session?.staffLinkId === input.scope.staffLinkId &&
      input.scope.allowedCustomerIds.includes(session.context.customerId)
    ? session
    : null
}

function loadSchema(args: Readonly<Record<string, unknown>>) {
  try {
    return requireStationSchema(
      args.schemaKey as string,
      args.schemaVersion as number,
    )
  } catch (_) {
    return null
  }
}

function loadSessionSchema(session: AgentIntakeSession) {
  try {
    return requireStationSchema(session.schemaKey, session.schemaVersion)
  } catch (_) {
    return null
  }
}

function parseCandidate(raw: unknown): ValueCandidate | null {
  if (!isRecord(raw)) return null
  const fieldKey = optionalText(raw.fieldKey)
  const sourcePhrase = optionalText(raw.sourcePhrase)
  const confidence = typeof raw.confidence === 'number' ? raw.confidence : null
  if (
    !fieldKey || !sourcePhrase || confidence === null ||
    !Number.isFinite(confidence) || confidence < 0 || confidence > 1 ||
    !('value' in raw)
  ) return null
  return {
    fieldKey,
    value: raw.value,
    sourcePhrase,
    confidence,
  }
}

function missingRequired(
  schema: AgentStationSchema,
  values: Readonly<Record<string, unknown>>,
): string[] {
  return validateStationValueSet(schema, values).missing
}

function clarificationFor(
  rejected: readonly RejectedValue[],
): AgentClarification {
  const rejection = rejected[0]
  return {
    fieldKey: rejection.fieldKey,
    sourcePhrase: rejection.sourcePhrase,
    reason: rejection.reason,
  }
}

function firstIssueReason(
  schema: AgentStationSchema,
  values: Readonly<Record<string, unknown>>,
  fieldKey: string,
): string | null {
  const issue = validateStationValueSet(schema, values).issues.find(
    (candidate) => candidate.fieldKey === fieldKey,
  )
  if (!issue) return null
  return issue.code === 'item_above_maximum'
    ? 'above_dynamic_maximum'
    : issue.code
}

function sameVisitContext(
  visit: AgentIntakeVisit,
  context: AgentIntakeContext,
): boolean {
  return visit.customerId === context.customerId &&
    visit.flockId === context.flockId &&
    visit.hatcheryId === context.hatcheryId &&
    visit.auditDate === context.auditDate
}

function requiredTurn(
  input: AgentToolExecutionInput,
): { id: string; index: number } | null {
  return input.conversationTurnId &&
      Number.isInteger(input.conversationTurnIndex) &&
      input.conversationTurnIndex! >= 0
    ? {
      id: input.conversationTurnId,
      index: input.conversationTurnIndex!,
    }
    : null
}

const editableStates = new Set<AgentIntakeSession['state']>([
  'collecting',
  'awaiting_clarification',
  'ready_for_summary',
  'awaiting_user_confirmation',
])

function ok(data: Record<string, unknown>): AgentToolResult {
  return { ok: true, code: 'ok', data }
}

function scopeDenied(): AgentToolResult {
  return { ok: false, code: 'scope_denied', data: null }
}

function stateConflict(): AgentToolResult {
  return { ok: false, code: 'state_conflict', data: null }
}

function infrastructureContextRequired(): AgentToolResult {
  return { ok: false, code: 'turn_context_required', data: null }
}

function optionalText(value: unknown): string | null {
  const text = value?.toString().trim()
  return text ? text : null
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
