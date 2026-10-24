import { assertEquals, assertThrows } from 'jsr:@std/assert@1.0.19'
import { plaidBaseUrl, requireEnv, todayInNewYork } from '../_shared/env.ts'

function withEnv(name: string, value: string | undefined, fn: () => void): void {
  const previous = Deno.env.get(name)
  if (value === undefined) Deno.env.delete(name)
  else Deno.env.set(name, value)
  try {
    fn()
  } finally {
    if (previous === undefined) Deno.env.delete(name)
    else Deno.env.set(name, previous)
  }
}

Deno.test('requireEnv returns the value when set', () => {
  withEnv('DROPLET_TEST_VAR', 'hello', () => {
    assertEquals(requireEnv('DROPLET_TEST_VAR'), 'hello')
  })
})

Deno.test('requireEnv throws when missing or empty', () => {
  withEnv('DROPLET_TEST_VAR', undefined, () => {
    assertThrows(() => requireEnv('DROPLET_TEST_VAR'), Error, 'DROPLET_TEST_VAR')
  })
  withEnv('DROPLET_TEST_VAR', '', () => {
    assertThrows(() => requireEnv('DROPLET_TEST_VAR'), Error, 'DROPLET_TEST_VAR')
  })
})

Deno.test('plaidBaseUrl maps sandbox and production', () => {
  assertEquals(plaidBaseUrl('sandbox'), 'https://sandbox.plaid.com')
  assertEquals(plaidBaseUrl('production'), 'https://production.plaid.com')
})

Deno.test('plaidBaseUrl rejects other environments', () => {
  assertThrows(() => plaidBaseUrl('development'), Error, 'PLAID_ENV')
})

Deno.test('plaidBaseUrl reads PLAID_ENV by default', () => {
  withEnv('PLAID_ENV', 'sandbox', () => {
    assertEquals(plaidBaseUrl(), 'https://sandbox.plaid.com')
  })
  withEnv('PLAID_ENV', undefined, () => {
    assertThrows(() => plaidBaseUrl(), Error, 'PLAID_ENV')
  })
})

Deno.test('todayInNewYork uses the America/New_York calendar day', () => {
  // 23:30 EDT on Oct 24 is already Oct 25 in UTC.
  assertEquals(todayInNewYork(new Date('2026-10-25T03:30:00Z')), '2026-10-24')
  assertEquals(todayInNewYork(new Date('2026-10-24T04:30:00Z')), '2026-10-24')
  // 23:59 EST on Dec 31.
  assertEquals(todayInNewYork(new Date('2026-01-01T04:59:00Z')), '2025-12-31')
  assertEquals(todayInNewYork(new Date('2026-03-05T17:00:00Z')), '2026-03-05')
})
