// POST {"merchant","amount_cents"} with a user JWT → SyncResult (contract C1). Sandbox only.
// Stages a purchase posted today with /sandbox/transactions/create, then syncs until it lands.
import { adminClient, requireUser, type SupabaseClient } from '../_shared/db.ts'
import { todayInNewYork } from '../_shared/env.ts'
import { errorResponse, HttpError, json, readJson } from '../_shared/http.ts'
import { PlaidClient, rethrowAsHttp } from '../_shared/plaid.ts'
import { liveSyncDeps, loadItemForUser, syncItem, type SyncResult } from '../_shared/sync.ts'

interface PurchaseBody {
  merchant?: unknown
  amount_cents?: unknown
}

const MAX_ATTEMPTS = 4
const RETRY_DELAY_MS = 1500

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

/** Stored rows for this user, day and amount. Merchant is ignored: Plaid may rename it. */
async function countMatchingRows(
  admin: SupabaseClient,
  userId: string,
  date: string,
  amountCents: number,
): Promise<number> {
  const { count, error } = await admin
    .from('transactions')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', userId)
    .eq('date', date)
    .eq('amount_cents', amountCents)
  if (error) throw new Error(`transactions count failed: ${error.message}`)
  return count ?? 0
}

Deno.serve(async (req) => {
  try {
    const admin = adminClient()
    const userId = await requireUser(req, admin)
    if (Deno.env.get('PLAID_ENV') !== 'sandbox') {
      throw new HttpError(403, 'NOT_SANDBOX', 'Test purchases only work with the Plaid sandbox.')
    }
    const body = await readJson<PurchaseBody>(req)
    const merchant = typeof body.merchant === 'string' ? body.merchant.trim() : ''
    if (merchant.length < 1 || merchant.length > 60) {
      throw new HttpError(400, 'BAD_REQUEST', 'merchant must be 1 to 60 characters.')
    }
    const amountCents = body.amount_cents
    if (
      typeof amountCents !== 'number' || !Number.isInteger(amountCents) ||
      amountCents < 1 || amountCents > 100_000
    ) {
      throw new HttpError(400, 'BAD_REQUEST', 'amount_cents must be a whole number, 1 to 100000.')
    }

    const plaid = PlaidClient.fromEnv()
    const item = await loadItemForUser(admin, userId)
    const today = todayInNewYork()
    const countRows = () => countMatchingRows(admin, userId, today, amountCents)
    const before = await countRows()
    await plaid
      .sandboxTransactionsCreate(item.access_token, [
        {
          date_transacted: today,
          date_posted: today,
          amount: amountCents / 100,
          description: merchant,
        },
      ])
      .catch(rethrowAsHttp)

    // Plaid can take a moment to surface the new transaction on /transactions/sync, and a
    // webhook sync may store it first. So the test is "one more matching row", not `added`.
    const deps = liveSyncDeps(admin, plaid)
    let result: SyncResult = await syncItem(deps, item)
    let after = await countRows()
    for (let attempt = 2; attempt <= MAX_ATTEMPTS && after <= before; attempt++) {
      await delay(RETRY_DELAY_MS)
      const earlier = result.investment
      // Reload so each attempt continues from the cursor the previous one saved.
      result = await syncItem(deps, await loadItemForUser(admin, userId))
      result = { ...result, investment: result.investment ?? earlier }
      after = await countRows()
    }
    console.log(
      `simulate-purchase user_id=${userId} amount_cents=${amountCents} ` +
        `arrived=${after > before} added=${result.added}`,
    )
    return json(result)
  } catch (e) {
    return errorResponse(e)
  }
})
