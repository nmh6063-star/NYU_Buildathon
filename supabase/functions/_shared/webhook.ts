// Verifies the `Plaid-Verification` JWT on incoming Plaid webhooks (spec §7).
import { decodeProtectedHeader, importJWK, jwtVerify } from 'npm:jose@6.2.13'
import { constantTimeEqual } from './http.ts'

const MAX_AGE_SECONDS = 5 * 60
// The kid comes from an unverified header, so only well-formed ids ever reach getKey.
const KID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/

/**
 * True only when the header is an ES256 JWT signed by Plaid key `kid`, issued within 5 minutes
 * of `nowSeconds`, whose `request_body_sha256` equals the SHA-256 of the raw body. Never throws.
 * A `kid` outside [A-Za-z0-9_-]{1,64} is rejected before `getKey` is called.
 */
export async function verifyPlaidWebhook(
  rawBody: string,
  verificationHeader: string | null,
  getKey: (kid: string) => Promise<JsonWebKey>,
  nowSeconds: number = Math.floor(Date.now() / 1000),
): Promise<boolean> {
  if (!verificationHeader) return false
  try {
    const header = decodeProtectedHeader(verificationHeader)
    if (header.alg !== 'ES256' || typeof header.kid !== 'string' || !KID_PATTERN.test(header.kid)) {
      return false
    }
    const jwk = await getKey(header.kid)
    // Plaid sets expired_at on keys it has rotated out.
    const expiredAt = (jwk as { expired_at?: unknown }).expired_at
    if (expiredAt !== undefined && expiredAt !== null) return false
    const key = await importJWK(jwk, 'ES256')
    const { payload } = await jwtVerify(verificationHeader, key, {
      algorithms: ['ES256'],
      currentDate: new Date(nowSeconds * 1000),
    })
    if (typeof payload.iat !== 'number' || Math.abs(nowSeconds - payload.iat) > MAX_AGE_SECONDS) {
      return false
    }
    const claimed = payload.request_body_sha256
    if (typeof claimed !== 'string') return false
    return constantTimeEqual(await sha256Hex(rawBody), claimed)
  } catch {
    return false
  }
}

async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text))
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, '0')).join('')
}
