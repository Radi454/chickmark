// supabase/functions/app-hatchery-agent/voice.ts
//
// Wraps OpenAI Whisper (speech-to-text) and TTS (text-to-speech) behind two
// small functions. Prefers a dedicated OPENAI_VOICE_KEY secret so a voice
// spend cap can be isolated from the agent brain's OPENAI_API_KEY, but falls
// back to OPENAI_API_KEY when no separate voice key has been set — so voice
// works immediately with only the key the brain already uses.
//
// Logging discipline: never log audio bytes, transcripts, or replies.

const TRANSCRIPTION_ENDPOINT = 'https://api.openai.com/v1/audio/transcriptions'
const SPEECH_ENDPOINT = 'https://api.openai.com/v1/audio/speech'
const WHISPER_MODEL = 'whisper-1'
const TTS_MODEL = 'tts-1'
const TTS_VOICE = 'alloy'

export class VoiceProviderError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'VoiceProviderError'
  }
}

export interface VoiceConfig {
  apiKey: string
  fetchImpl?: typeof fetch
}

export function readVoiceConfig(): VoiceConfig | null {
  const apiKey = Deno.env.get('OPENAI_VOICE_KEY')?.trim() ||
    Deno.env.get('OPENAI_API_KEY')?.trim()
  return apiKey ? { apiKey } : null
}

/** Decodes a base64 audio clip and sends it to Whisper. Returns the transcript. */
export async function transcribeAudio(
  audioBase64: string,
  config: VoiceConfig,
): Promise<string> {
  const bytes = decodeBase64(audioBase64)
  const form = new FormData()
  form.append('file', new Blob([bytes.slice().buffer as ArrayBuffer]), 'audio.m4a')
  form.append('model', WHISPER_MODEL)

  const fetchImpl = config.fetchImpl ?? fetch
  let response: Response
  try {
    response = await fetchImpl(TRANSCRIPTION_ENDPOINT, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${config.apiKey}` },
      body: form,
    })
  } catch (_) {
    throw new VoiceProviderError('Transcription request failed')
  }
  if (!response.ok) {
    throw new VoiceProviderError(`Transcription returned HTTP ${response.status}`)
  }
  let payload: unknown
  try {
    payload = await response.json()
  } catch (_) {
    throw new VoiceProviderError('Transcription response is invalid JSON')
  }
  const text = isRecord(payload) && typeof payload.text === 'string'
    ? payload.text.trim()
    : ''
  if (!text) throw new VoiceProviderError('Transcription returned no text')
  return text
}

/** Calls OpenAI TTS on the given text and returns base64-encoded mp3 audio. */
export async function synthesizeSpeech(
  text: string,
  config: VoiceConfig,
): Promise<string> {
  const fetchImpl = config.fetchImpl ?? fetch
  let response: Response
  try {
    response = await fetchImpl(SPEECH_ENDPOINT, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${config.apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ model: TTS_MODEL, voice: TTS_VOICE, input: text }),
    })
  } catch (_) {
    throw new VoiceProviderError('Speech request failed')
  }
  if (!response.ok) {
    throw new VoiceProviderError(`Speech request returned HTTP ${response.status}`)
  }
  let bytes: Uint8Array
  try {
    bytes = new Uint8Array(await response.arrayBuffer())
  } catch (_) {
    throw new VoiceProviderError('Speech response could not be read')
  }
  if (bytes.length === 0) throw new VoiceProviderError('Speech response was empty')
  return encodeBase64(bytes)
}

function decodeBase64(value: string): Uint8Array {
  try {
    const binary = atob(value)
    const bytes = new Uint8Array(binary.length)
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
    return bytes
  } catch (_) {
    throw new VoiceProviderError('audioBase64 is not valid base64')
  }
}

function encodeBase64(bytes: Uint8Array): string {
  let binary = ''
  const chunkSize = 0x8000
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize))
  }
  return btoa(binary)
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
