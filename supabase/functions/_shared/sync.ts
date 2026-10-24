// Plaid → database sync for one item (spec §4.2) and its Supabase-backed store.
import type { SupabaseClient } from './db.ts'
import { HttpError } from './http.ts'
import { PlaidApiError, PlaidClient, plaidHttpError, type TransactionsSyncPage } from './plaid.ts'
import { fetchPrice } from './prices.ts'
import { toTransactionRow, type TransactionRow } from './roundup.ts'
import { sweepIfReady } from './sweep.ts'

export interface InvestmentJson {
  id: string
  asset_symbol: string
  amount_cents: number
  price_usd: string
  quantity: string
  mode: string
  created_at: string
}

export interface SyncResult {
  added: number
  modified: number
  removed: number
  investment: InvestmentJson | null
}

export interface PlaidItemRecord {
  id: string
  user_id: string
  item_id: string
  access_token: string
  cursor: string | null
  linked_on: string
  status: string
}

export interface SyncStore {
  applyTransactions(userId: string, rows: TransactionRow[], removedIds: string[]): Promise<void>
  saveCursor(itemRowId: string, userId: string, cursor: string): Promise<void>
  setStatus(
    itemRowId: string,
    userId: string,
    status: 'active' | 'login_required' | 'error',
  ): Promise<void>
  pendingAndThreshold(
    userId: string,
  ): Promise<{ pendingCents: number; thresholdCents: number; targetAsset: string; paused: boolean }>
  sweep(userId: string, asset: string, price: string): Promise<InvestmentJson | null>
}

export interface SyncDeps {
  plaid: Pick<PlaidClient, 'transactionsSync'>
  store: SyncStore
  price: (symbol: string) => Promise<string>
}

const MUTATION_DURING_PAGINATION = 'TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION'
const MAX_RESTARTS = 3

/** Pulls every page since the stored cursor, applies it, saves the cursor, then sweeps. */
export async function syncItem(deps: SyncDeps, item: PlaidItemRecord): Promise<SyncResult> {
  let cursor = item.cursor
  let restarts = 0
  let counts = { added: 0, modified: 0, removed: 0 }
  let page: TransactionsSyncPage
  for (;;) {
    try {
      page = await deps.plaid.transactionsSync(item.access_token, cursor)
    } catch (err) {
      if (
        err instanceof PlaidApiError && err.errorCode === MUTATION_DURING_PAGINATION &&
        restarts < MAX_RESTARTS
      ) {
        // Plaid: restart the whole pagination from the cursor this run began with.
        restarts += 1
        cursor = item.cursor
        counts = { added: 0, modified: 0, removed: 0 }
        continue
      }
      throw await failSync(deps.store, item, err)
    }
    const rows = [...page.added, ...page.modified]
      .map((t) => toTransactionRow(t, item.linked_on))
      .filter((row): row is TransactionRow => row !== null)
    const removedIds = page.removed.map((r) => r.transaction_id)
    await deps.store.applyTransactions(item.user_id, rows, removedIds)
    counts.added += page.added.length
    counts.modified += page.modified.length
    counts.removed += page.removed.length
    if (!page.has_more) break
    cursor = page.next_cursor
  }

  await deps.store.saveCursor(item.id, item.user_id, page.next_cursor)
  const investment = await sweepIfReady(deps.store, deps.price, item.user_id)
  console.log(
    `sync user_id=${item.user_id} added=${counts.added} modified=${counts.modified} ` +
      `removed=${counts.removed} invested_cents=${investment?.amount_cents ?? 0}`,
  )
  return { ...counts, investment }
}

async function failSync(store: SyncStore, item: PlaidItemRecord, err: unknown): Promise<unknown> {
  if (!(err instanceof PlaidApiError)) return err
  const status = err.errorCode === 'ITEM_LOGIN_REQUIRED' ? 'login_required' : 'error'
  await store.setStatus(item.id, item.user_id, status)
  return plaidHttpError(err)
}

/** Production dependencies: Plaid from env, this database, live True Markets prices. */
export function liveSyncDeps(
  admin: SupabaseClient,
  plaid: PlaidClient = PlaidClient.fromEnv(),
): SyncDeps {
  return { plaid, store: supabaseSyncStore(admin), price: (symbol) => fetchPrice(symbol) }
}

interface SweepRow {
  id: string
  asset_symbol: string
  amount_cents: number | string
  price_usd: string
  quantity: string
  mode: string
  created_at: string
}

function check(what: string, error: { message: string } | null): void {
  if (error) throw new Error(`${what} failed: ${error.message}`)
}

export function supabaseSyncStore(admin: SupabaseClient): SyncStore {
  return {
    async applyTransactions(userId, rows, removedIds) {
      const { error } = await admin.rpc('apply_transactions', {
        p_user: userId,
        p_rows: rows,
        p_removed: removedIds,
      })
      check('apply_transactions', error)
    },

    async saveCursor(itemRowId, userId, cursor) {
      const now = new Date().toISOString()
      const item = await admin
        .from('plaid_items')
        .update({ cursor, status: 'active', updated_at: now })
        .eq('id', itemRowId)
      check('plaid_items cursor update', item.error)
      const bank = await admin
        .from('bank_connections')
        .upsert({ user_id: userId, status: 'active', last_synced_at: now })
      check('bank_connections upsert', bank.error)
    },

    async setStatus(itemRowId, userId, status) {
      const item = await admin
        .from('plaid_items')
        .update({ status, updated_at: new Date().toISOString() })
        .eq('id', itemRowId)
      check('plaid_items status update', item.error)
      const bank = await admin.from('bank_connections').update({ status }).eq('user_id', userId)
      check('bank_connections status update', bank.error)
    },

    async pendingAndThreshold(userId) {
      const [summary, profile] = await Promise.all([
        admin
          .from('drop_summary')
          .select('pending_cents, threshold_cents')
          .eq('user_id', userId)
          .single(),
        admin.from('profiles').select('target_asset, roundups_paused').eq('id', userId).single(),
      ])
      check('drop_summary read', summary.error)
      check('profiles read', profile.error)
      if (!summary.data || !profile.data) throw new Error(`no profile for user_id=${userId}`)
      return {
        pendingCents: Number(summary.data.pending_cents),
        thresholdCents: Number(summary.data.threshold_cents),
        targetAsset: String(profile.data.target_asset),
        paused: Boolean(profile.data.roundups_paused),
      }
    },

    async sweep(userId, asset, price) {
      const { data, error } = await admin.rpc('sweep_drops', {
        p_user: userId,
        p_asset: asset,
        p_price: price,
      })
      check('sweep_drops', error)
      const row = (data as SweepRow[] | null)?.[0]
      if (!row) return null
      return {
        id: row.id,
        asset_symbol: row.asset_symbol,
        amount_cents: Number(row.amount_cents),
        price_usd: row.price_usd,
        quantity: row.quantity,
        mode: row.mode,
        created_at: new Date(row.created_at).toISOString(),
      }
    },
  }
}

export const ITEM_COLUMNS = 'id, user_id, item_id, access_token, cursor, linked_on, status'

/** The user's Plaid item, or HttpError(404, 'NO_BANK'). */
export async function loadItemForUser(
  admin: SupabaseClient,
  userId: string,
): Promise<PlaidItemRecord> {
  const { data, error } = await admin
    .from('plaid_items')
    .select(ITEM_COLUMNS)
    .eq('user_id', userId)
    .maybeSingle()
  check('plaid_items read', error)
  if (!data) throw new HttpError(404, 'NO_BANK', 'Connect a bank first.')
  return data as PlaidItemRecord
}

/** The item a Plaid webhook refers to, or null when Droplet does not know it. */
export async function findItemByPlaidId(
  admin: SupabaseClient,
  itemId: string,
): Promise<PlaidItemRecord | null> {
  const { data, error } = await admin
    .from('plaid_items')
    .select(ITEM_COLUMNS)
    .eq('item_id', itemId)
    .maybeSingle()
  check('plaid_items read', error)
  return (data as PlaidItemRecord | null) ?? null
}

/** Every item in good standing, oldest first (used by sync-all). */
export async function listActiveItems(admin: SupabaseClient): Promise<PlaidItemRecord[]> {
  const { data, error } = await admin
    .from('plaid_items')
    .select(ITEM_COLUMNS)
    .eq('status', 'active')
    .order('created_at', { ascending: true })
  check('plaid_items list', error)
  return (data ?? []) as PlaidItemRecord[]
}
