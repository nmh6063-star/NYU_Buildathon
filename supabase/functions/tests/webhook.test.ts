import { assertEquals } from 'jsr:@std/assert@1.0.19'
import { exportJWK, generateKeyPair, type JWTPayload, SignJWT } from 'npm:jose@6.2.13'
import { verifyPlaidWebhook } from '../_shared/webhook.ts'

// Plaid hashes the exact bytes it sends (pretty-printed with 2-space indentation).
const BODY = `{
  "environment": "sandbox",
  "item_id": "item-1",
  "webhook_code": "SYNC_UPDATES_AVAILABLE",
  "webhook_type": "TRANSACTIONS"
}`
const NOW = 1_793_000_000

const plaidKeys = await generateKeyPair('ES256')
const otherKeys = await generateKeyPair('ES256')
// Shape of /webhook_verification_key/get → key.
const PLAID_JWK = {
  ...(await exportJWK(plaidKeys.publicKey)),
  alg: 'ES256',
  kid: 'kid-1',
  use: 'sig',
  created_at: 1_700_000_000,
  expired_at: null,
}

async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text))
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, '0')).join('')
}

const BODY_SHA256 = await sha256Hex(BODY)

async function sign(
  claims: JWTPayload,
  opts: { kid?: string; iat?: number | null; key?: CryptoKey } = {},
): Promise<string> {
  const jwt = new SignJWT(claims).setProtectedHeader({
    alg: 'ES256',
    typ: 'JWT',
    ...(opts.kid === '' ? {} : { kid: opts.kid ?? 'kid-1' }),
  })
  if (opts.iat !== null) jwt.setIssuedAt(opts.iat ?? NOW)
  return await jwt.sign(opts.key ?? plaidKeys.privateKey)
}

function keyLookup(jwk: JsonWebKey = PLAID_JWK) {
  const asked: string[] = []
  const getKey = (kid: string): Promise<JsonWebKey> => {
    asked.push(kid)
    return kid === 'kid-1' ? Promise.resolve(jwk) : Promise.reject(new Error(`unknown ${kid}`))
  }
  return { getKey, asked }
}

Deno.test('verifyPlaidWebhook accepts a valid Plaid signature', async () => {
  const token = await sign({ request_body_sha256: BODY_SHA256 })
  const { getKey, asked } = keyLookup()
  assertEquals(await verifyPlaidWebhook(BODY, token, getKey, NOW), true)
  assertEquals(asked, ['kid-1'])
})

Deno.test('verifyPlaidWebhook rejects a tampered body', async () => {
  const token = await sign({ request_body_sha256: BODY_SHA256 })
  const tampered = BODY.replace('item-1', 'item-2')
  assertEquals(await verifyPlaidWebhook(tampered, token, keyLookup().getKey, NOW), false)
})

Deno.test('verifyPlaidWebhook rejects a body hash that differs only in whitespace', async () => {
  const token = await sign({ request_body_sha256: BODY_SHA256 })
  const compact = JSON.stringify(JSON.parse(BODY))
  assertEquals(await verifyPlaidWebhook(compact, token, keyLookup().getKey, NOW), false)
})

Deno.test('verifyPlaidWebhook rejects a token signed by another key', async () => {
  const token = await sign({ request_body_sha256: BODY_SHA256 }, { key: otherKeys.privateKey })
  assertEquals(await verifyPlaidWebhook(BODY, token, keyLookup().getKey, NOW), false)
})

Deno.test('verifyPlaidWebhook enforces the 5 minute iat window', async () => {
  const claims = { request_body_sha256: BODY_SHA256 }
  const { getKey } = keyLookup()
  const fresh = await sign(claims, { iat: NOW - 299 })
  assertEquals(await verifyPlaidWebhook(BODY, fresh, getKey, NOW), true)
  const stale = await sign(claims, { iat: NOW - 301 })
  assertEquals(await verifyPlaidWebhook(BODY, stale, getKey, NOW), false)
  const future = await sign(claims, { iat: NOW + 301 })
  assertEquals(await verifyPlaidWebhook(BODY, future, getKey, NOW), false)
  const missing = await sign(claims, { iat: null })
  assertEquals(await verifyPlaidWebhook(BODY, missing, getKey, NOW), false)
})

Deno.test('verifyPlaidWebhook requires ES256 and does not fetch a key otherwise', async () => {
  const secret = new TextEncoder().encode('a-shared-secret-that-is-32-bytes!')
  const hs256 = await new SignJWT({ request_body_sha256: BODY_SHA256 })
    .setProtectedHeader({ alg: 'HS256', kid: 'kid-1' })
    .setIssuedAt(NOW)
    .sign(secret)
  const { getKey, asked } = keyLookup()
  assertEquals(await verifyPlaidWebhook(BODY, hs256, getKey, NOW), false)
  assertEquals(asked, [])
})

Deno.test('verifyPlaidWebhook requires a kid', async () => {
  const token = await sign({ request_body_sha256: BODY_SHA256 }, { kid: '' })
  const { getKey, asked } = keyLookup()
  assertEquals(await verifyPlaidWebhook(BODY, token, getKey, NOW), false)
  assertEquals(asked, [])
})

Deno.test('verifyPlaidWebhook rejects a malformed kid without fetching a key', async () => {
  const { getKey, asked } = keyLookup()
  for (const kid of ['../kid-1', 'kid 1', 'kid-1\n', 'k'.repeat(65)]) {
    const token = await sign({ request_body_sha256: BODY_SHA256 }, { kid })
    assertEquals(await verifyPlaidWebhook(BODY, token, getKey, NOW), false)
  }
  assertEquals(asked, [])
})

Deno.test('verifyPlaidWebhook rejects an unknown kid', async () => {
  const token = await sign({ request_body_sha256: BODY_SHA256 }, { kid: 'kid-404' })
  assertEquals(await verifyPlaidWebhook(BODY, token, keyLookup().getKey, NOW), false)
})

Deno.test('verifyPlaidWebhook rejects an expired Plaid key', async () => {
  const token = await sign({ request_body_sha256: BODY_SHA256 })
  const expired = { ...PLAID_JWK, expired_at: 1_790_000_000 } as JsonWebKey
  assertEquals(await verifyPlaidWebhook(BODY, token, keyLookup(expired).getKey, NOW), false)
})

Deno.test('verifyPlaidWebhook rejects a token without request_body_sha256', async () => {
  const token = await sign({})
  assertEquals(await verifyPlaidWebhook(BODY, token, keyLookup().getKey, NOW), false)
})

Deno.test('verifyPlaidWebhook rejects a missing or malformed header', async () => {
  const { getKey } = keyLookup()
  assertEquals(await verifyPlaidWebhook(BODY, null, getKey, NOW), false)
  assertEquals(await verifyPlaidWebhook(BODY, '', getKey, NOW), false)
  assertEquals(await verifyPlaidWebhook(BODY, 'not-a-jwt', getKey, NOW), false)
})
