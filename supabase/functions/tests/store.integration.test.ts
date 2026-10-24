// Runs only against a local `supabase start` stack, when DROPLET_DB_TESTS=1 (see Task 6).
import { assert, assertAlmostEquals, assertEquals, assertMatch } from 'jsr:@std/assert@1.0.19'
import { adminClient } from '../_shared/db.ts'
import type { TransactionRow } from '../_shared/roundup.ts'
import {
  findItemByPlaidId,
  ITEM_COLUMNS,
  listActiveItems,
  loadItemForUser,
  type PlaidItemRecord,
  supabaseSyncStore,
  syncItem,
} from '../_shared/sync.ts'

function row(id: string, amountCents: number, roundupCents: number): TransactionRow {
  return {
    plaid_transaction_id: id,
    merchant_name: 'Integration Cafe',
    amount_cents: amountCents,
    iso_currency_code: 'USD',
    date: '2026-10-24',
    pending: false,
    category: 'FOOD_AND_DRINK',
    roundup_cents: roundupCents,
    roundup_status: roundupCents > 0 ? 'pending' : 'skipped',
  }
}

Deno.test({
  name: 'supabaseSyncStore and syncItem against the local database',
  ignore: Deno.env.get('DROPLET_DB_TESTS') !== '1',
  fn: async (t) => {
    const admin = adminClient()
    const tag = crypto.randomUUID()
    const created = await admin.auth.admin.createUser({
      email: `it-${tag}@droplet.test`,
      password: crypto.randomUUID(),
      email_confirm: true,
      user_metadata: { display_name: 'Integration' },
    })
    if (created.error) throw created.error
    const userId = created.data.user.id
    try {
      const inserted = await admin
        .from('plaid_items')
        .insert({
          user_id: userId,
          item_id: `item-${tag}`,
          access_token: 'access-test-token',
          institution_name: 'First Platypus Bank',
          linked_on: '2026-10-24',
        })
        .select(ITEM_COLUMNS)
        .single()
      if (inserted.error) throw inserted.error
      const item = inserted.data as PlaidItemRecord
      const bank = await admin
        .from('bank_connections')
        .insert({ user_id: userId, institution_name: 'First Platypus Bank' })
      if (bank.error) throw bank.error
      const store = supabaseSyncStore(admin)

      await t.step('item lookups', async () => {
        assertEquals(await loadItemForUser(admin, userId), item)
        assertEquals(await findItemByPlaidId(admin, `item-${tag}`), item)
        assertEquals(await findItemByPlaidId(admin, 'item-unknown'), null)
        assert((await listActiveItems(admin)).some((i) => i.id === item.id))
      })

      await t.step('applyTransactions feeds pendingAndThreshold', async () => {
        await store.applyTransactions(userId, [
          row(`${tag}-a`, 567, 33),
          row(`${tag}-b`, 1342, 58),
          row(`${tag}-c`, 400, 0),
        ], [])
        assertEquals(await store.pendingAndThreshold(userId), {
          pendingCents: 91,
          thresholdCents: 500,
          targetAsset: 'SOL',
          paused: false,
        })
      })

      await t.step('removed ids reverse pending round-ups', async () => {
        await store.applyTransactions(userId, [], [`${tag}-b`])
        assertEquals((await store.pendingAndThreshold(userId)).pendingCents, 33)
        const { data } = await admin
          .from('transactions')
          .select('roundup_status, roundup_cents')
          .eq('plaid_transaction_id', `${tag}-b`)
          .single()
        assertEquals(data, { roundup_status: 'reversed', roundup_cents: 0 })
      })

      await t.step('sweep below the threshold returns null', async () => {
        assertEquals(await store.sweep(userId, 'SOL', '99.366035688829'), null)
      })

      await t.step('sweep at the threshold invests every pending drop', async () => {
        const update = await admin.from('profiles').update({ threshold_cents: 200 }).eq(
          'id',
          userId,
        )
        if (update.error) throw update.error
        await store.applyTransactions(userId, [row(`${tag}-d`, 1, 99), row(`${tag}-e`, 2, 98)], [])
        const investment = await store.sweep(userId, 'SOL', '99.366035688829')
        assert(investment)
        assertEquals(investment.asset_symbol, 'SOL')
        assertEquals(investment.amount_cents, 230)
        assertEquals(investment.price_usd, '99.366035688829')
        assertEquals(investment.mode, 'simulated')
        assertAlmostEquals(Number(investment.quantity), 2.3 / 99.366035688829, 1e-12)
        assertMatch(investment.created_at, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/)
        assertEquals((await store.pendingAndThreshold(userId)).pendingCents, 0)
        assertEquals(await store.sweep(userId, 'SOL', '99.366035688829'), null)
      })

      await t.step('setStatus and saveCursor update both tables', async () => {
        await store.setStatus(item.id, userId, 'login_required')
        const flagged = await admin.from('bank_connections').select('status').eq('user_id', userId)
          .single()
        assertEquals(flagged.data, { status: 'login_required' })
        await store.saveCursor(item.id, userId, 'cursor-1')
        const saved = await loadItemForUser(admin, userId)
        assertEquals([saved.cursor, saved.status], ['cursor-1', 'active'])
        const synced = await admin
          .from('bank_connections')
          .select('status, institution_name, last_synced_at')
          .eq('user_id', userId)
          .single()
        assertEquals(synced.data?.status, 'active')
        assertEquals(synced.data?.institution_name, 'First Platypus Bank')
        assert(synced.data?.last_synced_at)
      })

      await t.step('syncItem end to end with a fake Plaid page', async () => {
        const plaid = {
          transactionsSync: () =>
            Promise.resolve({
              added: [
                { transaction_id: `${tag}-f`, amount: 5.67, date: '2026-10-24' },
                { transaction_id: `${tag}-g`, amount: 1.01, date: '2026-10-24' },
                { transaction_id: `${tag}-h`, amount: 2.02, date: '2026-10-24' },
                { transaction_id: `${tag}-old`, amount: 9.99, date: '2026-10-01' },
              ].map((t) => ({ ...t, iso_currency_code: 'USD', pending: false, name: 'Fake' })),
              modified: [],
              removed: [],
              next_cursor: 'cursor-2',
              has_more: false,
            }),
        }
        const result = await syncItem(
          { plaid, store, price: () => Promise.resolve('99.366035688829') },
          await loadItemForUser(admin, userId),
        )
        assertEquals([result.added, result.modified, result.removed], [4, 0, 0])
        assertEquals(result.investment?.amount_cents, 230)
        assertEquals((await loadItemForUser(admin, userId)).cursor, 'cursor-2')
        const old = await admin.from('transactions').select('id').eq(
          'plaid_transaction_id',
          `${tag}-old`,
        )
        assertEquals(old.data, [])
      })
    } finally {
      const removed = await admin.auth.admin.deleteUser(userId)
      if (removed.error) console.error(`cleanup failed for ${userId}: ${removed.error.message}`)
    }
  },
})
