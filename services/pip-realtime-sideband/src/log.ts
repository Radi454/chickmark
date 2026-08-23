// Content-free telemetry.
//
// Nothing that flows through this module may carry audio, transcript text, tool
// arguments, tool results, model tokens, secrets, access tokens or the binding
// token frame. The emit path therefore accepts ONLY a stable event name plus a
// bag of scalar fields, and it scrubs any field whose key looks like content or
// whose value looks like free text. That is deliberately paranoid: a log line is
// the easiest place for a domain transcript to leak.

export type LogLevel = 'debug' | 'info' | 'warn' | 'error'

export type LogFields = Record<string, string | number | boolean | null | undefined>

/** Field names that must never be emitted, whatever the value looks like. */
const FORBIDDEN_KEYS = new Set([
  'text',
  'transcript',
  'transcript_text',
  'delta',
  'audio',
  'arguments',
  'args',
  'arguments_json',
  'result',
  'result_json',
  'output',
  'content',
  'prompt',
  'instructions',
  'token',
  'access_token',
  'binding_token',
  'client_secret',
  'authorization',
  'api_key',
  'secret',
  'password',
  'summary',
  'message',
])

/**
 * Any string longer than this is assumed to be prose rather than an identifier
 * and is replaced by its length. Ids in this system (uuid, `item_...`,
 * `resp_...`, `call_...`) all sit well under the bound.
 */
const MAX_SCALAR_LENGTH = 120

let sink: (line: string) => void = (line) => console.log(line)

/** Test seam: redirect emitted lines. */
export function setLogSink(next: (line: string) => void): void {
  sink = next
}

export function resetLogSink(): void {
  sink = (line) => console.log(line)
}

function scrubKey(key: string): boolean {
  const lowered = key.toLowerCase()
  if (FORBIDDEN_KEYS.has(lowered)) return true
  return (
    lowered.endsWith('_text') ||
    lowered.endsWith('_secret') ||
    lowered.endsWith('_token') ||
    lowered.includes('password')
  )
}

function scrubValue(value: LogFields[string]): string | number | boolean | null {
  if (value === undefined) return null
  if (value === null) return null
  if (typeof value === 'number' || typeof value === 'boolean') return value
  if (value.length > MAX_SCALAR_LENGTH) return `<len:${value.length}>`
  return value
}

export function emit(level: LogLevel, event: string, fields: LogFields = {}): void {
  const safe: Record<string, unknown> = { level, event, at: new Date().toISOString() }
  for (const [key, value] of Object.entries(fields)) {
    if (scrubKey(key)) {
      safe[key] = '<redacted>'
      continue
    }
    safe[key] = scrubValue(value)
  }
  sink(JSON.stringify(safe))
}

export const log = {
  debug: (event: string, fields?: LogFields) => emit('debug', event, fields),
  info: (event: string, fields?: LogFields) => emit('info', event, fields),
  warn: (event: string, fields?: LogFields) => emit('warn', event, fields),
  error: (event: string, fields?: LogFields) => emit('error', event, fields),
}

/**
 * Errors are logged by shape, never by domain content: a provider error
 * string COULD in principle embed a request body, which could embed a
 * transcript, so this never returns the arbitrary text of anything that
 * isn't already known to be a transport/protocol-level error.
 *
 * A plain `Error` still resolves to just `err.name` — the message on those is
 * whatever the throwing code wrote, and that code is not audited the way this
 * module's own callers are.
 *
 * But a socket/library error that arrives as a non-Error object (the DOM
 * `ErrorEvent` this service's own WebSocket wrapper passes to `onError`, or a
 * Node-style `{ message, error: { message } }` shape some libraries emit) used
 * to fall through to `typeof err`, which is always the unhelpful literal
 * `"object"` — that is what actually showed up in production for every
 * socket-level failure. Those messages are network/protocol text
 * (`ECONNREFUSED`, `unexpected server response 401`, ...), not conversation
 * content, so surfacing them is safe and is the whole point of this function:
 * a log line that says WHY a socket died.
 */
export function errorShape(err: unknown): string {
  if (err instanceof Error) return err.name
  if (err && typeof err === 'object') {
    const record = err as Record<string, unknown>
    if (typeof record.message === 'string' && record.message !== '') {
      return record.message
    }
    const nested = record.error
    if (nested && typeof nested === 'object') {
      const nestedMessage = (nested as Record<string, unknown>).message
      if (typeof nestedMessage === 'string' && nestedMessage !== '') return nestedMessage
    }
  }
  return String(err)
}
