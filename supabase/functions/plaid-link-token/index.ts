// POST {} with a user JWT → {"link_token","expiration"} for Plaid Link (contract C1).
import { adminClient, requireUser } from '../_shared/db.ts'
import { errorResponse, json } from '../_shared/http.ts'
import { PlaidClient, rethrowAsHttp } from '../_shared/plaid.ts'

Deno.serve(async (req) => {
  try {
    const admin = adminClient()
    const userId = await requireUser(req, admin)
    const token = await PlaidClient.fromEnv()
      .linkTokenCreate({ userId, webhook: Deno.env.get('PLAID_WEBHOOK_URL') || undefined })
      .catch(rethrowAsHttp)
    console.log(`plaid-link-token user_id=${userId}`)
    return json(token)
  } catch (e) {
    return errorResponse(e)
  }
})
