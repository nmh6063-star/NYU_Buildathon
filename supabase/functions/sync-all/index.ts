// pg_cron → POST {} every 15 minutes with header x-cron-secret (verify_jwt = false).
// Syncs every active item one at a time → {"items":n,"failed":n}.
import { adminClient } from '../_shared/db.ts'
import { requireEnv } from '../_shared/env.ts'
import { constantTimeEqual, errorResponse, HttpError, json } from '../_shared/http.ts'
import { listActiveItems, liveSyncDeps, syncItem } from '../_shared/sync.ts'

Deno.serve(async (req) => {
  try {
    if (!constantTimeEqual(req.headers.get('x-cron-secret') ?? '', requireEnv('CRON_SECRET'))) {
      throw new HttpError(401, 'UNAUTHORIZED', 'Invalid cron secret.')
    }
    const admin = adminClient()
    const items = await listActiveItems(admin)
    const deps = liveSyncDeps(admin)
    let failed = 0
    for (const item of items) {
      try {
        await syncItem(deps, item)
      } catch (err) {
        failed += 1
        const reason = err instanceof Error ? err.message : String(err)
        console.error(`sync-all user_id=${item.user_id} failed: ${reason}`)
      }
    }
    console.log(`sync-all items=${items.length} failed=${failed}`)
    return json({ items: items.length, failed })
  } catch (e) {
    return errorResponse(e)
  }
})
