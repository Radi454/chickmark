// The npm:ws adapter (wrapNodeWs) and the pre-open retry wrapper
// (attachWithRetry / awaitSidebandOpen) around it — the layer swapped in to
// replace the always-fails-in-production subprotocol transport. See the
// comment above connectSideband in src/sideband.ts for why.
//
// Nothing here touches the network: a FakeNodeWs stands in for the real `ws`
// socket, driven by hand like the FakeSidebandSocket used elsewhere in this
// suite.

import { assert, assertEquals } from '@std/assert'
import {
  attachWithRetry,
  awaitSidebandOpen,
  type NodeWsLike,
  type NodeWsResponseLike,
  wrapNodeWs,
} from '../src/sideband.ts'
import { captureLogs } from './fakes.ts'

type Listener = (...args: unknown[]) => void

/** A minimal hand-driven stand-in for `ws`'s `WebSocket`. */
class FakeNodeWs implements NodeWsLike {
  readyState = 0
  sent: string[] = []
  closedWith: { code?: number; reason?: string } | null = null
  readonly #handlers = new Map<string, Listener[]>()

  // `(...args: never[]) => void` accepts every listener shape NodeWsLike's
  // overloads can pass under strictFunctionTypes (never is assignable to any
  // parameter type); the cast widens it back for storage, and #emit drives
  // handlers with the exact argument shapes the tests fire.
  on(event: string, listener: (...args: never[]) => void): void {
    const list = this.#handlers.get(event) ?? []
    list.push(listener as Listener)
    this.#handlers.set(event, list)
  }

  send(data: string): void {
    this.sent.push(data)
  }

  close(code?: number, reason?: string): void {
    this.closedWith = { code, reason }
  }

  #emit(event: string, ...args: unknown[]): void {
    for (const handler of this.#handlers.get(event) ?? []) handler(...args)
  }

  /** Test driver: transitions readyState the way a real socket would too. */
  triggerOpen(): void {
    this.readyState = 1
    this.#emit('open')
  }

  triggerMessage(data: unknown): void {
    this.#emit('message', data)
  }

  triggerClose(code: number): void {
    this.#emit('close', code)
  }

  triggerError(error: unknown): void {
    this.#emit('error', error)
  }

  /**
   * Bodies arrive over the response stream in chunks, then `end`. The fake
   * response fires its stored `data` handler for each chunk the instant
   * `end` is registered, since `wrapNodeWs` always registers both listeners
   * synchronously and in that order before anything can fire.
   */
  triggerUnexpectedResponse(status: number, bodyChunks: string[]): void {
    let dataHandler: ((chunk: unknown) => void) | null = null
    const response: NodeWsResponseLike = {
      statusCode: status,
      on(event, listener) {
        if (event === 'data') {
          dataHandler = listener as (chunk: unknown) => void
        } else {
          for (const chunk of bodyChunks) dataHandler?.(chunk)
          ;(listener as () => void)()
        }
      },
    }
    this.#emit('unexpected-response', {}, response)
  }
}

// ---------------------------------------------------------------------------
// wrapNodeWs
// ---------------------------------------------------------------------------

Deno.test('wrapNodeWs: sends before open are queued and flushed in order on open', () => {
  const raw = new FakeNodeWs()
  const socket = wrapNodeWs(raw)

  socket.send({ type: 'a' })
  socket.send({ type: 'b' })
  assertEquals(raw.sent, [])
  assertEquals(socket.isOpen, false)

  raw.triggerOpen()
  assertEquals(socket.isOpen, true)
  assertEquals(raw.sent, [JSON.stringify({ type: 'a' }), JSON.stringify({ type: 'b' })])

  // Once open, sends go straight through instead of queuing.
  socket.send({ type: 'c' })
  assertEquals(raw.sent.length, 3)
})

Deno.test('wrapNodeWs: onOpen fires exactly once, on the open transition', () => {
  const raw = new FakeNodeWs()
  let opens = 0
  wrapNodeWs(raw, () => opens++)
  raw.triggerOpen()
  assertEquals(opens, 1)
})

Deno.test('wrapNodeWs: a Buffer-shaped frame is decoded before JSON.parse', () => {
  const raw = new FakeNodeWs()
  const socket = wrapNodeWs(raw)
  const received: Record<string, unknown>[] = []
  socket.onMessage((event) => received.push(event))

  // `ws` hands the handler a Buffer, which is a Uint8Array subclass — never a
  // string the way the browser WebSocket does.
  const bytes = new TextEncoder().encode(JSON.stringify({ type: 'session.updated' }))
  raw.triggerMessage(bytes)

  assertEquals(received, [{ type: 'session.updated' }])
})

Deno.test('wrapNodeWs: an unparseable frame is dropped and logged, not thrown', () => {
  const raw = new FakeNodeWs()
  const socket = wrapNodeWs(raw)
  const received: Record<string, unknown>[] = []
  socket.onMessage((event) => received.push(event))

  const capture = captureLogs()
  try {
    raw.triggerMessage('{not json')
    assertEquals(received, [])
    assert(capture.lines.some((line) => line.includes('sideband.unparseable_frame')))
  } finally {
    capture.restore()
  }
})

Deno.test('wrapNodeWs: a frame that is neither string nor bytes is also unparseable', () => {
  const raw = new FakeNodeWs()
  const socket = wrapNodeWs(raw)
  const received: Record<string, unknown>[] = []
  socket.onMessage((event) => received.push(event))

  const capture = captureLogs()
  try {
    raw.triggerMessage(42)
    assertEquals(received, [])
    assert(capture.lines.some((line) => line.includes('sideband.unparseable_frame')))
  } finally {
    capture.restore()
  }
})

Deno.test('wrapNodeWs: unexpected-response logs status and a truncated body, then routes to error+close', () => {
  const raw = new FakeNodeWs()
  const socket = wrapNodeWs(raw)
  const errors: unknown[] = []
  const closes: number[] = []
  socket.onError((error) => errors.push(error))
  socket.onClose((code) => closes.push(code))

  const capture = captureLogs()
  try {
    const longBody = 'x'.repeat(200)
    raw.triggerUnexpectedResponse(401, [longBody])

    const line = JSON.parse(
      capture.lines.find((entry) => entry.includes('sideband.attach_rejected'))!,
    ) as Record<string, unknown>
    assertEquals(line.status, 401)
    // The adapter slices to 140 chars first; telemetry's length-scrubber then
    // replaces anything still over 120 chars with its length marker — so a
    // 200-char body surfaces as the sliced length, not the original.
    assertEquals(line.body, `<len:140>`)

    assertEquals(errors.length, 1)
    assertEquals(closes, [0])
  } finally {
    capture.restore()
  }
})

Deno.test('wrapNodeWs: an unexpected-response body under the log scrub length survives intact', () => {
  const raw = new FakeNodeWs()
  wrapNodeWs(raw)
  const capture = captureLogs()
  try {
    raw.triggerUnexpectedResponse(401, ["You didn't provide an API key"])
    const line = JSON.parse(
      capture.lines.find((entry) => entry.includes('sideband.attach_rejected'))!,
    ) as Record<string, unknown>
    assertEquals(line.body, "You didn't provide an API key")
  } finally {
    capture.restore()
  }
})

// ---------------------------------------------------------------------------
// awaitSidebandOpen: resolve-on-open / reject-on-first-pre-open-failure
// ---------------------------------------------------------------------------

Deno.test('awaitSidebandOpen: resolves with a working socket once open fires', async () => {
  const raw = new FakeNodeWs()
  const pending = awaitSidebandOpen(raw)
  raw.triggerOpen()
  const socket = await pending
  assertEquals(socket.isOpen, true)
})

Deno.test('awaitSidebandOpen: a pre-open error rejects the attempt', async () => {
  const raw = new FakeNodeWs()
  const pending = awaitSidebandOpen(raw)
  raw.triggerError(new Error('ECONNREFUSED'))
  await pending.then(
    () => {
      throw new Error('expected rejection')
    },
    (error) => assertEquals((error as Error).message, 'ECONNREFUSED'),
  )
})

Deno.test('awaitSidebandOpen: a pre-open unexpected-response rejects the attempt', async () => {
  const raw = new FakeNodeWs()
  const capture = captureLogs()
  try {
    const pending = awaitSidebandOpen(raw)
    raw.triggerUnexpectedResponse(401, ["You didn't provide an API key"])
    await pending.then(
      () => {
        throw new Error('expected rejection')
      },
      (error) => assertEquals((error as Error).message, 'attach_rejected'),
    )
  } finally {
    capture.restore()
  }
})

Deno.test('awaitSidebandOpen: a close after open no longer affects the settled attempt', async () => {
  const raw = new FakeNodeWs()
  const pending = awaitSidebandOpen(raw)
  raw.triggerOpen()
  const socket = await pending

  // A separately-registered consumer (the normal teardown path) still sees
  // the close — the attach itself just does not react to it a second time.
  const seenCodes: number[] = []
  socket.onClose((code) => seenCodes.push(code))
  raw.triggerClose(4409)
  assertEquals(seenCodes, [4409])
})

// ---------------------------------------------------------------------------
// attachWithRetry
// ---------------------------------------------------------------------------

Deno.test('attachWithRetry: a first-try success dials once and never sleeps', async () => {
  const raw = new FakeNodeWs()
  let dials = 0
  let sleeps = 0
  const socket = wrapNodeWs(raw)
  raw.triggerOpen()

  const result = await attachWithRetry(() => {
    dials++
    return Promise.resolve(socket)
  }, { sleep: () => (sleeps++, Promise.resolve()) })

  assertEquals(dials, 1)
  assertEquals(sleeps, 0)
  assertEquals(result, socket)
})

Deno.test('attachWithRetry: retries up to the configured count, ~750ms apart by default, then succeeds', async () => {
  const raw = new FakeNodeWs()
  const socket = wrapNodeWs(raw)
  raw.triggerOpen()

  let dials = 0
  const delays: number[] = []
  const capture = captureLogs()
  try {
    const result = await attachWithRetry(
      () => {
        dials++
        if (dials < 3) return Promise.reject(new Error(`attempt_${dials}_failed`))
        return Promise.resolve(socket)
      },
      {
        sleep: (ms) => {
          delays.push(ms)
          return Promise.resolve()
        },
      },
    )
    assertEquals(dials, 3)
    assertEquals(result, socket)
    // Default backoff is 750ms, exercised twice: after attempt 1 and attempt 2.
    assertEquals(delays, [750, 750])
    const retryLines = capture.lines
      .filter((line) => line.includes('sideband.attach_retry'))
      .map((line) => (JSON.parse(line) as Record<string, unknown>).attempt)
    // Logged with the attempt NUMBER ABOUT TO RUN, i.e. 2 and 3.
    assertEquals(retryLines, [2, 3])
  } finally {
    capture.restore()
  }
})

Deno.test('attachWithRetry: exhausting all attempts throws the last error', async () => {
  let dials = 0
  const capture = captureLogs()
  try {
    await attachWithRetry(
      () => {
        dials++
        return Promise.reject(new Error(`attempt_${dials}_failed`))
      },
      { retries: 2, sleep: () => Promise.resolve() },
    ).then(
      () => {
        throw new Error('expected rejection')
      },
      (error) => assertEquals((error as Error).message, 'attempt_3_failed'),
    )
    // One initial attempt plus two retries, never a fourth.
    assertEquals(dials, 3)
  } finally {
    capture.restore()
  }
})

Deno.test('attachWithRetry: a custom retry count and delay are honored', async () => {
  let dials = 0
  const delays: number[] = []
  await attachWithRetry(
    () => {
      dials++
      return dials <= 1 ? Promise.reject(new Error('fail')) : Promise.resolve(
        wrapNodeWs(new FakeNodeWs()),
      )
    },
    {
      retries: 1,
      delayMs: 10,
      sleep: (ms) => {
        delays.push(ms)
        return Promise.resolve()
      },
    },
  )
  assertEquals(dials, 2)
  assertEquals(delays, [10])
})
