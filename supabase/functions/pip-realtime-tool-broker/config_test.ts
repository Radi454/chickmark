import { assertEquals } from '@std/assert'

import { MIN_BROKER_SECRET_LENGTH, readBrokerSecret } from './config.ts'

const VALID = 'a'.repeat(MIN_BROKER_SECRET_LENGTH)

function env(values: Record<string, string>) {
  return (name: string) => values[name]
}

Deno.test('an unset secret reads as null so the broker fails closed', () => {
  assertEquals(readBrokerSecret(env({})), null)
})

Deno.test('a blank secret reads as null', () => {
  assertEquals(
    readBrokerSecret(env({ PIP_REALTIME_BROKER_SECRET: '   ' })),
    null,
  )
})

Deno.test('a placeholder that is too short to be a secret is rejected', () => {
  assertEquals(
    readBrokerSecret(env({ PIP_REALTIME_BROKER_SECRET: 'changeme' })),
    null,
  )
  assertEquals(
    readBrokerSecret(
      env({
        PIP_REALTIME_BROKER_SECRET: 'a'.repeat(MIN_BROKER_SECRET_LENGTH - 1),
      }),
    ),
    null,
  )
})

Deno.test('a long enough secret is returned trimmed', () => {
  assertEquals(
    readBrokerSecret(env({ PIP_REALTIME_BROKER_SECRET: ` ${VALID} ` })),
    VALID,
  )
})
