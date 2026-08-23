import { assertEquals } from 'jsr:@std/assert'
import { makeHangup } from '../src/cleanup.ts'
import type { RealtimeConfig } from '../src/config.ts'

// Only the two fields makeHangup reads.
const config = {
  openAiRealtimeUrl: 'wss://api.openai.com/v1/realtime',
  openAiApiKey: 'test-key',
} as unknown as RealtimeConfig

/** Swaps global fetch for one call, always restoring it. */
async function withFetch(
  impl: (url: string, init?: RequestInit) => Promise<Response>,
  run: () => Promise<void>,
): Promise<void> {
  const original = globalThis.fetch
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) =>
    impl(String(input), init)) as typeof fetch
  try {
    await run()
  } finally {
    globalThis.fetch = original
  }
}

Deno.test('hangup treats 404 as terminal success, not failure', async () => {
  // Verified against the live provider on 2026-08-17: hanging up a call it has
  // already dropped returns 404 "No session found for the provided call_id".
  // That is the ORDINARY outcome for an orphan — the client is long gone — so
  // recording it as failed would make every routine sweep look broken and hide
  // a real failure.
  await withFetch(
    () =>
      Promise.resolve(
        new Response(
          JSON.stringify({
            error: { message: 'No session found for the provided call_id' },
          }),
          { status: 404 },
        ),
      ),
    async () => {
      assertEquals(await makeHangup(config)('rtc_already_closed'), 'succeeded')
    },
  )
})

Deno.test('hangup reports success on 200', async () => {
  await withFetch(
    () => Promise.resolve(new Response('{}', { status: 200 })),
    async () => {
      assertEquals(await makeHangup(config)('rtc_live'), 'succeeded')
    },
  )
})

Deno.test('hangup reports failure on a real provider error', async () => {
  // A 500 is NOT "already closed" — it must stay visible as a failure so a
  // genuine provider outage is not silently counted as a clean sweep.
  await withFetch(
    () => Promise.resolve(new Response('boom', { status: 500 })),
    async () => {
      assertEquals(await makeHangup(config)('rtc_broken'), 'failed')
    },
  )
})

Deno.test('hangup reports failure when the request throws', async () => {
  await withFetch(
    () => Promise.reject(new Error('network down')),
    async () => {
      assertEquals(await makeHangup(config)('rtc_unreachable'), 'failed')
    },
  )
})

Deno.test('hangup targets the documented REST path over https', async () => {
  let seen = ''
  await withFetch(
    (url) => {
      seen = url
      return Promise.resolve(new Response('{}', { status: 200 }))
    },
    async () => {
      await makeHangup(config)('rtc_abc/123')
    },
  )
  // wss -> https, and the id is encoded rather than splicing into the path.
  assertEquals(
    seen,
    'https://api.openai.com/v1/realtime/calls/rtc_abc%2F123/hangup',
  )
})
