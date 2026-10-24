import { assertEquals, assertRejects } from 'jsr:@std/assert@1.0.19'
import type { SupabaseClient } from '../_shared/db.ts'
import { HttpError } from '../_shared/http.ts'
import { PlaidApiError, type TransactionsSyncPage } from '../_shared/plaid.ts'
import type { PlaidTransaction, TransactionRow } from '../_shared/roundup.ts'
import {
  type InvestmentJson,
  loadItemForUser,
  type PlaidItemRecord,
  supabaseSyncStore,
  type SyncDeps,
  syncItem,
  type SyncStore,
} from '../_shared/sync.ts'

const ITEM: PlaidItemRecord = {
  id: 'row-1',
  user_id: 'user-1',
  item_id: 'item-1',
  access_token: 'access-test-token',
  cursor: 'c0',
  linked_on: '2026-10-24',
  status: 'active',
}

const INVESTMENT: InvestmentJson = {
  id: '6f1c2a9e-0d1b-4c33-9a57-0b6f3a2f9e10',
  asset_symbol: 'SOL',
  amount_cents: 528,
  price_usd: '99.366035688829',
  quantity: '0.053137',
  mode: 'simulated',
  created_at: '2026-10-24T16:03:11.482Z',
}

function txn(id: string, amount: number, date = '2026-10-24'): PlaidTransaction {
  return {
    transaction_id: id,
    amount,
    iso_currency_code: 'USD',
    date,
    pending: false,
    merchant_name: 'Shop',
    personal_finance_category: { primary: 'GENERAL_MERCHANDISE' },
  }
}

function page(fields: Partial<TransactionsSyncPage>): TransactionsSyncPage {
  return { added: [], modified: [], removed: [], next_cursor: 'c1', has_more: false, ...fields }
}

function plaidError(code: string, message = code): PlaidApiError {
  return new PlaidApiError(code, 'TRANSACTIONS_ERROR', message, 400)
}

function fakePlaid(steps: (TransactionsSyncPage | Error)[]) {
  const cursors: (string | null)[] = []
  const plaid: SyncDeps['plaid'] = {
    transactionsSync: (_accessToken, cursor) => {
      cursors.push(cursor)
      const step = steps.shift()
      if (!step) return Promise.reject(new Error('unexpected transactionsSync call'))
      return step instanceof Error ? Promise.reject(step) : Promise.resolve(step)
    },
  }
  return { plaid, cursors }
}

class FakeStore implements SyncStore {
  events: string[] = []
  applied: { userId: string; rows: TransactionRow[]; removedIds: string[] }[] = []
  savedCursors: string[] = []
  statuses: string[] = []
  summary = { pendingCents: 0, thresholdCents: 500, targetAsset: 'SOL', paused: false }

  applyTransactions(userId: string, rows: TransactionRow[], removedIds: string[]) {
    this.events.push('apply')
    this.applied.push({ userId, rows, removedIds })
    return Promise.resolve()
  }
  saveCursor(itemRowId: string, userId: string, cursor: string) {
    this.events.push(`saveCursor:${itemRowId}:${userId}`)
    this.savedCursors.push(cursor)
    return Promise.resolve()
  }
  setStatus(itemRowId: string, userId: string, status: 'active' | 'login_required' | 'error') {
    this.events.push(`setStatus:${itemRowId}:${userId}`)
    this.statuses.push(status)
    return Promise.resolve()
  }
  pendingAndThreshold() {
    this.events.push('pendingAndThreshold')
    return Promise.resolve(this.summary)
  }
  sweep(userId: string, asset: string, price: string) {
    this.events.push(`sweep:${userId}:${asset}:${price}`)
    return Promise.resolve(INVESTMENT)
  }
}

function deps(steps: (TransactionsSyncPage | Error)[], price: string | Error = '99.366035688829') {
  const { plaid, cursors } = fakePlaid(steps)
  const store = new FakeStore()
  const priced: string[] = []
  const syncDeps: SyncDeps = {
    plaid,
    store,
    price: (symbol) => {
      priced.push(symbol)
      return price instanceof Error ? Promise.reject(price) : Promise.resolve(price)
    },
  }
  return { syncDeps, store, cursors, priced }
}

Deno.test('syncItem maps added and modified rows, drops pre-link history, saves the cursor', async () => {
  const { syncDeps, store, cursors } = deps([
    page({
      added: [txn('t1', 5.67), txn('t-old', 3.5, '2026-10-20')],
      modified: [txn('t2', 13.42)],
      removed: [{ transaction_id: 't0' }],
      next_cursor: 'c1',
    }),
  ])
  const result = await syncItem(syncDeps, ITEM)
  assertEquals(result, { added: 2, modified: 1, removed: 1, investment: null })
  assertEquals(cursors, ['c0'])
  assertEquals(store.applied.length, 1)
  assertEquals(store.applied[0].userId, 'user-1')
  assertEquals(store.applied[0].rows.map((r) => [r.plaid_transaction_id, r.roundup_cents]), [
    ['t1', 33],
    ['t2', 58],
  ])
  assertEquals(store.applied[0].removedIds, ['t0'])
  assertEquals(store.savedCursors, ['c1'])
  assertEquals(store.events, ['apply', 'saveCursor:row-1:user-1', 'pendingAndThreshold'])
})

Deno.test('syncItem pages until has_more is false and applies once per page', async () => {
  const { syncDeps, store, cursors } = deps([
    page({ added: [txn('t1', 1.5)], next_cursor: 'c1', has_more: true }),
    page({ added: [txn('t2', 2.5)], removed: [{ transaction_id: 't9' }], next_cursor: 'c2' }),
  ])
  const result = await syncItem(syncDeps, ITEM)
  assertEquals(result, { added: 2, modified: 0, removed: 1, investment: null })
  assertEquals(cursors, ['c0', 'c1'])
  assertEquals(store.applied.map((a) => a.rows.length), [1, 1])
  assertEquals(store.savedCursors, ['c2'])
})

Deno.test('syncItem skips a pending row, then rounds up the posted row that replaces it', async () => {
  const { syncDeps, store } = deps([
    page({ added: [{ ...txn('p1', 5.67), pending: true }], next_cursor: 'c1', has_more: true }),
    page({ added: [txn('t1', 5.67)], removed: [{ transaction_id: 'p1' }], next_cursor: 'c2' }),
  ])
  const result = await syncItem(syncDeps, ITEM)
  assertEquals(result, { added: 2, modified: 0, removed: 1, investment: null })
  const summarize = (rows: TransactionRow[]) =>
    rows.map((r) => [r.plaid_transaction_id, r.pending, r.roundup_cents, r.roundup_status])
  assertEquals(summarize(store.applied[0].rows), [['p1', true, 0, 'skipped']])
  assertEquals(store.applied[0].removedIds, [])
  assertEquals(summarize(store.applied[1].rows), [['t1', false, 33, 'pending']])
  assertEquals(store.applied[1].removedIds, ['p1'])
  assertEquals(store.savedCursors, ['c2'])
})

Deno.test('syncItem starts from a null cursor on a new item', async () => {
  const { syncDeps, cursors } = deps([page({ next_cursor: 'c1' })])
  await syncItem(syncDeps, { ...ITEM, cursor: null })
  assertEquals(cursors, [null])
})

Deno.test('syncItem restarts from the original cursor after a mutation during pagination', async () => {
  const { syncDeps, store, cursors } = deps([
    page({ added: [txn('t1', 1.5)], next_cursor: 'c1', has_more: true }),
    plaidError('TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION'),
    page({ added: [txn('t1', 1.5), txn('t2', 2.5)], next_cursor: 'c3' }),
  ])
  const result = await syncItem(syncDeps, ITEM)
  assertEquals(cursors, ['c0', 'c1', 'c0'])
  assertEquals(result, { added: 2, modified: 0, removed: 0, investment: null })
  assertEquals(store.savedCursors, ['c3'])
  assertEquals(store.statuses, [])
})

Deno.test('syncItem restarts when the very first page hits a mutation', async () => {
  const { syncDeps, store, cursors } = deps([
    plaidError('TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION'),
    page({ added: [txn('t1', 1.5)], next_cursor: 'c1' }),
  ])
  const result = await syncItem(syncDeps, ITEM)
  assertEquals(cursors, ['c0', 'c0'])
  assertEquals(result.added, 1)
  assertEquals(store.savedCursors, ['c1'])
})

Deno.test('syncItem gives up after three restarts', async () => {
  const mutation = 'TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION'
  const { syncDeps, store, cursors } = deps([1, 2, 3, 4].map(() => plaidError(mutation)))
  const err = await assertRejects(() => syncItem(syncDeps, ITEM), HttpError)
  assertEquals([err.status, err.code], [502, 'PLAID_ERROR'])
  assertEquals(cursors.length, 4)
  assertEquals(store.statuses, ['error'])
  assertEquals(store.savedCursors, [])
})

Deno.test('syncItem marks the item login_required and throws 409 ITEM_LOGIN_REQUIRED', async () => {
  const { syncDeps, store } = deps([plaidError('ITEM_LOGIN_REQUIRED')])
  const err = await assertRejects(() => syncItem(syncDeps, ITEM), HttpError)
  assertEquals([err.status, err.code], [409, 'ITEM_LOGIN_REQUIRED'])
  assertEquals(store.statuses, ['login_required'])
  assertEquals(store.events, ['setStatus:row-1:user-1'])
})

Deno.test('syncItem marks other Plaid errors as error and throws 502 PLAID_ERROR', async () => {
  const { syncDeps, store } = deps([plaidError('INTERNAL_SERVER_ERROR', 'Plaid had a problem')])
  const err = await assertRejects(() => syncItem(syncDeps, ITEM), HttpError)
  assertEquals([err.status, err.code, err.message], [502, 'PLAID_ERROR', 'Plaid had a problem'])
  assertEquals(store.statuses, ['error'])
})

Deno.test('syncItem passes non-Plaid errors through without changing status', async () => {
  const { syncDeps, store } = deps([new TypeError('network down')])
  await assertRejects(() => syncItem(syncDeps, ITEM), TypeError, 'network down')
  assertEquals(store.statuses, [])
})

Deno.test('syncItem sweeps after saving the cursor once drops reach the threshold', async () => {
  const { syncDeps, store, priced } = deps([page({ added: [txn('t1', 5.67)], next_cursor: 'c1' })])
  store.summary.pendingCents = 528
  const result = await syncItem(syncDeps, ITEM)
  assertEquals(result.investment, INVESTMENT)
  assertEquals(priced, ['SOL'])
  assertEquals(store.events, [
    'apply',
    'saveCursor:row-1:user-1',
    'pendingAndThreshold',
    'sweep:user-1:SOL:99.366035688829',
  ])
})

Deno.test('syncItem still succeeds when the price fetch fails', async () => {
  const { syncDeps, store } = deps([page({ next_cursor: 'c1' })], new Error('timeout'))
  store.summary.pendingCents = 528
  const result = await syncItem(syncDeps, ITEM)
  assertEquals(result.investment, null)
  assertEquals(store.savedCursors, ['c1'])
})

function rpcAdmin(data: unknown, error: { message: string } | null = null) {
  const calls: { fn: string; args: unknown }[] = []
  const rpc = (fn: string, args: unknown) => {
    calls.push({ fn, args })
    return Promise.resolve({ data, error })
  }
  return { admin: { rpc } as unknown as SupabaseClient, calls }
}

Deno.test('supabaseSyncStore.applyTransactions calls apply_transactions', async () => {
  const { admin, calls } = rpcAdmin(null)
  const rows: TransactionRow[] = [{
    plaid_transaction_id: 't1',
    merchant_name: 'Shop',
    amount_cents: 567,
    iso_currency_code: 'USD',
    date: '2026-10-24',
    pending: false,
    category: null,
    roundup_cents: 33,
    roundup_status: 'pending',
  }]
  await supabaseSyncStore(admin).applyTransactions('user-1', rows, ['t0'])
  assertEquals(calls, [{
    fn: 'apply_transactions',
    args: { p_user: 'user-1', p_rows: rows, p_removed: ['t0'] },
  }])
})

Deno.test('supabaseSyncStore.applyTransactions throws on a database error', async () => {
  const { admin } = rpcAdmin(null, { message: 'permission denied' })
  await assertRejects(
    () => supabaseSyncStore(admin).applyTransactions('user-1', [], []),
    Error,
    'permission denied',
  )
})

Deno.test('supabaseSyncStore.sweep calls sweep_drops and parses the first row', async () => {
  const { admin, calls } = rpcAdmin([{
    id: INVESTMENT.id,
    asset_symbol: 'SOL',
    amount_cents: '528',
    price_usd: '99.366035688829',
    quantity: '0.053137',
    mode: 'simulated',
    created_at: '2026-10-24T16:03:11.482017+00:00',
  }])
  assertEquals(await supabaseSyncStore(admin).sweep('user-1', 'SOL', '99.366035688829'), INVESTMENT)
  assertEquals(calls, [{
    fn: 'sweep_drops',
    args: { p_user: 'user-1', p_asset: 'SOL', p_price: '99.366035688829' },
  }])
})

Deno.test('supabaseSyncStore.sweep returns null when nothing was invested', async () => {
  const { admin } = rpcAdmin([])
  assertEquals(await supabaseSyncStore(admin).sweep('user-1', 'SOL', '99.36'), null)
})

function itemsAdmin(data: unknown) {
  const log: unknown[][] = []
  const query = {
    select: (columns: string) => {
      log.push(['select', columns])
      return query
    },
    eq: (column: string, value: unknown) => {
      log.push(['eq', column, value])
      return query
    },
    maybeSingle: () => Promise.resolve({ data, error: null }),
  }
  const from = (table: string) => {
    log.push(['from', table])
    return query
  }
  return { admin: { from } as unknown as SupabaseClient, log }
}

Deno.test('loadItemForUser returns the user plaid_items row', async () => {
  const { admin, log } = itemsAdmin(ITEM)
  assertEquals(await loadItemForUser(admin, 'user-1'), ITEM)
  assertEquals(log[0], ['from', 'plaid_items'])
  assertEquals(log[2], ['eq', 'user_id', 'user-1'])
})

Deno.test('loadItemForUser throws 404 NO_BANK when the user has no bank', async () => {
  const { admin } = itemsAdmin(null)
  const err = await assertRejects(() => loadItemForUser(admin, 'user-1'), HttpError)
  assertEquals([err.status, err.code, err.message], [404, 'NO_BANK', 'Connect a bank first.'])
})
