// Plaid → POST webhook (verify_jwt = false). Authenticated by the Plaid-Verification JWT.
// Only TRANSACTIONS / SYNC_UPDATES_AVAILABLE triggers work; everything else is acknowledged.
// A known item gets {"ok":true} straight away, and its sync runs in the background.
import { adminClient, type SupabaseClient } from '../_shared/db.ts'
import { errorResponse, HttpError, json } from '../_shared/http.ts'
import { PlaidClient } from '../_shared/plaid.ts'
import { findItemByPlaidId, liveSyncDeps, type PlaidItemRecord, syncItem } from '../_shared/sync.ts'
import { verifyPlaidWebhook } from '../_shared/webhook.ts'

// Supabase Edge Runtime global: keeps the worker alive until the promise settles.
declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void } | undefined

interface PlaidWebhook {
  webhook_type?: string
  webhook_code?: string
  item_id?: string
}

const KEY_TTL_MS = 24 * 60 * 60 * 1000
const FAILED_LOOKUP_TTL_MS = 60 * 1000
const MAX_FAILED_LOOKUPS = 1000

// Per function instance. Keys are refetched after 24 h, so a rotated key's expired_at is seen.
// A kid whose lookup failed is not looked up again for 60 s.
const keyCache = new Map<string, { key: JsonWebKey; fetchedAt: number }>()
const failedLookups = new Map<string, number>()

async function cachedKey(plaid: PlaidClient, kid: string): Promise<JsonWebKey> {
  const now = Date.now()
  const cached = keyCache.get(kid)
  if (cached && now - cached.fetchedAt < KEY_TTL_MS) return cached.key
  const failedAt = failedLookups.get(kid)
  if (failedAt !== undefined && now - failedAt < FAILED_LOOKUP_TTL_MS) {
    throw new Error('webhook key lookup failed recently')
  }
  try {
    const key = await plaid.webhookVerificationKey(kid)
    keyCache.set(kid, { key, fetchedAt: now })
    failedLookups.delete(kid)
    return key
  } catch (err) {
    if (failedLookups.size >= MAX_FAILED_LOOKUPS) failedLookups.clear()
    failedLookups.set(kid, now)
    throw err
  }
}

/** Never rejects: a failure is logged with the item_id only. */
async function syncQuietly(
  admin: SupabaseClient,
  plaid: PlaidClient,
  item: PlaidItemRecord,
): Promise<void> {
  try {
    await syncItem(liveSyncDeps(admin, plaid), item)
  } catch {
    console.error(`plaid-webhook sync failed item_id=${item.item_id}`)
  }
}

Deno.serve(async (req) => {
  try {
    const rawBody = await req.text()
    const plaid = PlaidClient.fromEnv()
    const verified = await verifyPlaidWebhook(
      rawBody,
      req.headers.get('Plaid-Verification'),
      (kid) => cachedKey(plaid, kid),
    )
    if (!verified) throw new HttpError(401, 'UNAUTHORIZED', 'Invalid webhook signature.')

    const event = JSON.parse(rawBody) as PlaidWebhook
    if (
      event.webhook_type !== 'TRANSACTIONS' ||
      event.webhook_code !== 'SYNC_UPDATES_AVAILABLE' ||
      !event.item_id
    ) {
      return json({ ok: true })
    }
    const admin = adminClient()
    const item = await findItemByPlaidId(admin, event.item_id)
    if (!item) {
      console.log(`plaid-webhook ignoring unknown item_id=${event.item_id}`)
      return json({ ok: true })
    }
    const sync = syncQuietly(admin, plaid, item)
    if (typeof EdgeRuntime === 'undefined') await sync
    else EdgeRuntime.waitUntil(sync)
    return json({ ok: true })
  } catch (e) {
    return errorResponse(e)
  }
})
