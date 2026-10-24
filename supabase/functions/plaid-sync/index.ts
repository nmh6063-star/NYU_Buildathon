// POST {} with a user JWT → SyncResult (contract C1). Pull-to-refresh and "Sync now".
import { adminClient, requireUser } from '../_shared/db.ts'
import { errorResponse, json } from '../_shared/http.ts'
import { liveSyncDeps, loadItemForUser, syncItem } from '../_shared/sync.ts'

Deno.serve(async (req) => {
  try {
    const admin = adminClient()
    const userId = await requireUser(req, admin)
    const item = await loadItemForUser(admin, userId)
    return json(await syncItem(liveSyncDeps(admin), item))
  } catch (e) {
    return errorResponse(e)
  }
})
