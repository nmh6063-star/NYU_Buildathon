// POST {"public_token","institution_name"} with a user JWT → SyncResult (contract C1).
// Exchanges the Link token, stores the item (linked today), then runs the first sync.
import { adminClient, requireUser } from '../_shared/db.ts'
import { todayInNewYork } from '../_shared/env.ts'
import { errorResponse, HttpError, json, readJson } from '../_shared/http.ts'
import { PlaidClient, rethrowAsHttp } from '../_shared/plaid.ts'
import { ITEM_COLUMNS, liveSyncDeps, type PlaidItemRecord, syncItem } from '../_shared/sync.ts'

interface ExchangeBody {
  public_token?: unknown
  institution_name?: unknown
}

Deno.serve(async (req) => {
  try {
    const admin = adminClient()
    const userId = await requireUser(req, admin)
    const body = await readJson<ExchangeBody>(req)
    if (typeof body.public_token !== 'string' || body.public_token === '') {
      throw new HttpError(400, 'BAD_REQUEST', 'public_token is required.')
    }
    const institutionName =
      typeof body.institution_name === 'string' && body.institution_name.trim() !== ''
        ? body.institution_name.trim()
        : null

    const plaid = PlaidClient.fromEnv()
    const exchanged = await plaid.exchangePublicToken(body.public_token).catch(rethrowAsHttp)
    const saved = await admin
      .from('plaid_items')
      .upsert({
        user_id: userId,
        item_id: exchanged.item_id,
        access_token: exchanged.access_token,
        institution_name: institutionName,
        linked_on: todayInNewYork(),
        cursor: null,
        status: 'active',
        updated_at: new Date().toISOString(),
      }, { onConflict: 'user_id' })
      .select(ITEM_COLUMNS)
      .single()
    if (saved.error) throw new Error(`plaid_items upsert failed: ${saved.error.message}`)
    const bank = await admin
      .from('bank_connections')
      .upsert({ user_id: userId, institution_name: institutionName, status: 'active' })
    if (bank.error) throw new Error(`bank_connections upsert failed: ${bank.error.message}`)
    console.log(`plaid-exchange user_id=${userId} item_id=${exchanged.item_id}`)

    return json(await syncItem(liveSyncDeps(admin, plaid), saved.data as PlaidItemRecord))
  } catch (e) {
    return errorResponse(e)
  }
})
