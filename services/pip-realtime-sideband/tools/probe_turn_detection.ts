// Standalone probe: does the Realtime API accept `turn_detection.type ===
// 'semantic_vad'` for model gpt-realtime-2.1-mini, and which `eagerness`
// values does it accept?
//
// NOT part of the runtime service. Run manually:
//   OPENAI_API_KEY="$(gcloud secrets versions access latest --secret=pip-openai-key --project=chickmark-ai-agent)" \
//     deno run --allow-net --allow-env tools/probe_turn_detection.ts
//
// This connects directly to the model-attach endpoint (not a call attach), so
// no live call/call_id is needed. It prints only provider-generated
// diagnostic fields (code/param/message) and NEVER the API key.

import { WebSocket as NodeWebSocket } from 'ws'

const MODEL = 'gpt-realtime-2.1-mini'
const URL = `wss://api.openai.com/v1/realtime?model=${MODEL}`
const TIMEOUT_MS = 10_000

function sessionUpdate(turnDetection: Record<string, unknown>) {
  return {
    type: 'session.update',
    session: {
      type: 'realtime',
      output_modalities: ['audio'],
      audio: {
        input: { turn_detection: turnDetection },
        output: { voice: 'cedar' },
      },
    },
  }
}

interface ProbeResult {
  outcome: 'accepted' | 'rejected' | 'timeout' | 'connect_error'
  detail?: { code?: unknown; param?: unknown; message?: unknown }
}

function probe(
  label: string,
  turnDetection: Record<string, unknown>,
): Promise<ProbeResult> {
  return new Promise((resolve) => {
    const apiKey = Deno.env.get('OPENAI_API_KEY')
    if (!apiKey) {
      console.error('OPENAI_API_KEY is not set')
      resolve({ outcome: 'connect_error' })
      return
    }
    const socket = new NodeWebSocket(URL, {
      headers: { Authorization: `Bearer ${apiKey}` },
    })
    let settled = false
    const finish = (result: ProbeResult) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      try {
        socket.close()
      } catch {
        // ignore
      }
      resolve(result)
    }

    const timer = setTimeout(() => {
      console.log(
        `[${label}] TIMEOUT after ${TIMEOUT_MS}ms with no session.updated/error`,
      )
      finish({ outcome: 'timeout' })
    }, TIMEOUT_MS)

    socket.on('open', () => {
      console.log(`[${label}] connected; sending session.update`)
      socket.send(JSON.stringify(sessionUpdate(turnDetection)))
    })

    socket.on('message', (data: unknown) => {
      let text: string
      if (typeof data === 'string') text = data
      else if (data instanceof Uint8Array) text = new TextDecoder().decode(data)
      else return
      let parsed: Record<string, unknown>
      try {
        parsed = JSON.parse(text)
      } catch {
        return
      }
      if (parsed.type === 'session.updated') {
        console.log(`[${label}] ACCEPTED: session.updated received`)
        finish({ outcome: 'accepted' })
      } else if (parsed.type === 'error') {
        const err = (parsed.error ?? {}) as Record<string, unknown>
        console.log(
          `[${label}] REJECTED: code=${JSON.stringify(err.code)} param=${
            JSON.stringify(err.param)
          } message=${JSON.stringify(String(err.message ?? '').slice(0, 200))}`,
        )
        finish({ outcome: 'rejected', detail: err })
      }
      // Ignore other event types (e.g. session.created).
    })

    socket.on('unexpected-response', (_req: unknown, res: { statusCode?: number }) => {
      console.log(`[${label}] unexpected-response status=${res.statusCode}`)
      finish({ outcome: 'connect_error' })
    })

    socket.on('error', (error: unknown) => {
      console.log(
        `[${label}] connect error: ${
          error instanceof Error ? error.message : String(error)
        }`,
      )
      finish({ outcome: 'connect_error' })
    })

    socket.on('close', (code: number) => {
      if (!settled) {
        console.log(`[${label}] closed before ack/error, code=${code}`)
        finish({ outcome: 'connect_error' })
      }
    })
  })
}

async function main() {
  console.log(`Probing ${MODEL} at ${URL}`)

  const low = await probe('semantic_vad eagerness=low', {
    type: 'semantic_vad',
    eagerness: 'low',
    create_response: true,
    interrupt_response: true,
  })

  if (low.outcome !== 'accepted') {
    console.log('\n--- eagerness=low was not accepted; probing eagerness=auto ---')
    await probe('semantic_vad eagerness=auto', {
      type: 'semantic_vad',
      eagerness: 'auto',
      create_response: true,
      interrupt_response: true,
    })

    console.log('\n--- probing bare semantic_vad (no eagerness) ---')
    await probe('semantic_vad (no eagerness)', {
      type: 'semantic_vad',
      create_response: true,
      interrupt_response: true,
    })
  }

  console.log('\nDone.')
}

await main()
