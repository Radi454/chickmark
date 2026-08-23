import { assertEquals } from '@std/assert'

import {
  PIP_MODEL_DEFAULTS,
  resolveOpenRouterTextModels,
  resolvePipTextModel,
} from './pip_model_routing.ts'

Deno.test('Pip model defaults are pinned by workload', () => {
  assertEquals(PIP_MODEL_DEFAULTS, {
    text: 'gpt-5-nano',
    textOpenRouter: 'openai/gpt-oss-120b',
    textOpenRouterFallback: 'openai/gpt-oss-20b',
    textOpenRouterVision: 'google/gemma-4-31b-it',
    live: 'gpt-realtime-2.1-mini',
    voiceNoteTranscription: 'gpt-4o-mini-transcribe',
    voiceNoteSpeech: 'gpt-4o-mini-tts',
  })
})

Deno.test('text routing accepts only its workload-specific override', () => {
  const values: Record<string, string> = {
    OPENAI_TEXT_MODEL: '  account-approved-text  ',
    OPENAI_MODEL: 'unrelated-extraction-model',
  }
  assertEquals(
    resolvePipTextModel((name) => values[name]),
    'account-approved-text',
  )
  assertEquals(
    resolvePipTextModel((name) =>
      name === 'OPENAI_MODEL' ? 'unrelated-extraction-model' : undefined
    ),
    'gpt-5-nano',
  )
})

Deno.test('OpenRouter text routing prefers OPENROUTER_MODEL, then AI_MODEL, then the default', () => {
  assertEquals(
    resolveOpenRouterTextModels((name) => {
      const values: Record<string, string> = {
        OPENROUTER_MODEL: '  account/primary  ',
        AI_MODEL: 'account/legacy-shared',
      }
      return values[name]
    }),
    {
      primary: 'account/primary',
      fallback: 'openai/gpt-oss-20b',
      vision: 'google/gemma-4-31b-it',
    },
  )

  assertEquals(
    resolveOpenRouterTextModels((name) =>
      name === 'AI_MODEL' ? 'account/legacy-shared' : undefined
    ),
    {
      primary: 'account/legacy-shared',
      fallback: 'openai/gpt-oss-20b',
      vision: 'google/gemma-4-31b-it',
    },
  )

  assertEquals(
    resolveOpenRouterTextModels(() => undefined),
    {
      primary: 'openai/gpt-oss-120b',
      fallback: 'openai/gpt-oss-20b',
      vision: 'google/gemma-4-31b-it',
    },
  )
})

Deno.test('OpenRouter fallback routing prefers OPENROUTER_FALLBACK_MODEL, then the default', () => {
  assertEquals(
    resolveOpenRouterTextModels((name) =>
      name === 'OPENROUTER_FALLBACK_MODEL' ? '  account/fallback  ' : undefined
    ),
    {
      primary: 'openai/gpt-oss-120b',
      fallback: 'account/fallback',
      vision: 'google/gemma-4-31b-it',
    },
  )
})

Deno.test('OpenRouter vision routing prefers OPENROUTER_VISION_MODEL, then the default', () => {
  assertEquals(
    resolveOpenRouterTextModels((name) =>
      name === 'OPENROUTER_VISION_MODEL' ? '  account/vision  ' : undefined
    ),
    {
      primary: 'openai/gpt-oss-120b',
      fallback: 'openai/gpt-oss-20b',
      vision: 'account/vision',
    },
  )
})

Deno.test('OpenRouter routing treats blank overrides as unset', () => {
  assertEquals(
    resolveOpenRouterTextModels((name) => {
      const values: Record<string, string> = {
        OPENROUTER_MODEL: '   ',
        OPENROUTER_FALLBACK_MODEL: '   ',
        OPENROUTER_VISION_MODEL: '   ',
      }
      return values[name]
    }),
    {
      primary: 'openai/gpt-oss-120b',
      fallback: 'openai/gpt-oss-20b',
      vision: 'google/gemma-4-31b-it',
    },
  )
})
