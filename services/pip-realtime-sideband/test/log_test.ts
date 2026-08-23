import { assert, assertEquals } from '@std/assert'
import { log } from '../src/log.ts'
import { captureLogs } from './fakes.ts'

Deno.test('telemetry drops content fields even when a caller passes them', () => {
  const capture = captureLogs()
  try {
    log.info('tool.executed', {
      session_id: 'sess_1',
      transcript: 'the hatch rate was 84 percent',
      arguments: '{"flock_id":"flock_1"}',
      binding_token: 'secret',
      access_token: 'jwt',
      tool_name: 'lookup_flock',
    })
    const line = JSON.parse(capture.lines[0]) as Record<string, unknown>
    assertEquals(line.session_id, 'sess_1')
    assertEquals(line.tool_name, 'lookup_flock')
    assertEquals(line.transcript, '<redacted>')
    assertEquals(line.arguments, '<redacted>')
    assertEquals(line.binding_token, '<redacted>')
    assertEquals(line.access_token, '<redacted>')
    assert(!capture.lines[0].includes('hatch rate'))
    assert(!capture.lines[0].includes('flock_1'))
  } finally {
    capture.restore()
  }
})

Deno.test('telemetry replaces prose-length values with a length, never the text', () => {
  const capture = captureLogs()
  try {
    log.warn('sideband.provider_error', { code: 'x'.repeat(500) })
    assertEquals(
      (JSON.parse(capture.lines[0]) as Record<string, unknown>).code,
      '<len:500>',
    )
  } finally {
    capture.restore()
  }
})

Deno.test('telemetry keeps identifiers and counters intact', () => {
  const capture = captureLogs()
  try {
    log.info('usage.settled', { session_id: 'sess_1', slices: 2, seconds: 600 })
    const line = JSON.parse(capture.lines[0]) as Record<string, unknown>
    assertEquals(line.slices, 2)
    assertEquals(line.seconds, 600)
    assertEquals(line.event, 'usage.settled')
    assertEquals(line.level, 'info')
  } finally {
    capture.restore()
  }
})
