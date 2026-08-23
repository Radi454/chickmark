export const PIP_MODEL_DEFAULTS = Object.freeze({
  text: 'gpt-5-nano',
  // OpenRouter path for the text agent (see `resolveOpenRouterTextModels`
  // below). Both ids are verified on OpenRouter's model catalogue to exist
  // and to advertise `tools` + `tool_choice` in `supported_parameters`. Paid
  // (non-`:free`) variants, chosen for reliability over the `:free` tier.
  textOpenRouter: 'openai/gpt-oss-120b',
  textOpenRouterFallback: 'openai/gpt-oss-20b',
  // Vision-capable OpenRouter model for a call whose `input` carries an
  // image or video (see `requestIsVisual` in `agent_provider.ts`).
  // `openai/gpt-oss-120b`/`-20b` are text->text only and cannot accept
  // visual input, so this is a deliberately separate model, not a fallback
  // on the text pair.
  textOpenRouterVision: 'google/gemma-4-31b-it',
  live: 'gpt-realtime-2.1-mini',
  voiceNoteTranscription: 'gpt-4o-mini-transcribe',
  voiceNoteSpeech: 'gpt-4o-mini-tts',
})

export type PipModelEnvReader = (name: string) => string | undefined

export function resolvePipTextModel(env: PipModelEnvReader): string {
  return env('OPENAI_TEXT_MODEL')?.trim() || PIP_MODEL_DEFAULTS.text
}

export interface OpenRouterTextModels {
  primary: string
  fallback: string
  /**
   * The vision-capable model for a call whose input carries an image or
   * video. Never falls back to `fallback` (text->text) — see the doc
   * comment on `visionFallbackModel` in `agent_provider.ts`.
   */
  vision: string
}

/**
 * Resolves the OpenRouter-provider text-agent model triple: a primary text
 * model, its single text fallback, and a separate vision-capable model. The
 * text fallback is ALWAYS an OpenRouter model too — this phase never falls
 * back to the paid OpenAI API.
 *
 * Primary: `OPENROUTER_MODEL` -> `AI_MODEL` -> `PIP_MODEL_DEFAULTS.textOpenRouter`.
 * Fallback: `OPENROUTER_FALLBACK_MODEL` -> `PIP_MODEL_DEFAULTS.textOpenRouterFallback`.
 * Vision: `OPENROUTER_VISION_MODEL` -> `PIP_MODEL_DEFAULTS.textOpenRouterVision`.
 *
 * All env values are trimmed; an empty string is treated as unset.
 */
export function resolveOpenRouterTextModels(
  env: PipModelEnvReader,
): OpenRouterTextModels {
  const primary = nonEmpty(env('OPENROUTER_MODEL')) ??
    nonEmpty(env('AI_MODEL')) ??
    PIP_MODEL_DEFAULTS.textOpenRouter
  const fallback = nonEmpty(env('OPENROUTER_FALLBACK_MODEL')) ??
    PIP_MODEL_DEFAULTS.textOpenRouterFallback
  const vision = nonEmpty(env('OPENROUTER_VISION_MODEL')) ??
    PIP_MODEL_DEFAULTS.textOpenRouterVision
  return { primary, fallback, vision }
}

function nonEmpty(value: string | undefined): string | undefined {
  const trimmed = value?.trim()
  return trimmed ? trimmed : undefined
}
