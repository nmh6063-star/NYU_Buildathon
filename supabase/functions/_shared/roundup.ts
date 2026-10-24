// Round-up rule and the Plaid transaction → `p_rows` mapping (contract C2).

export const EXCLUDED_CATEGORIES: ReadonlySet<string> = new Set([
  'TRANSFER_IN',
  'TRANSFER_OUT',
  'LOAN_PAYMENTS',
  'BANK_FEES',
  'INCOME',
])

/** Cents needed to reach the next whole dollar. 0 for whole dollars, zero and refunds. */
export function roundupCents(amountCents: number): number {
  if (amountCents <= 0) return 0
  return (100 - (amountCents % 100)) % 100
}

/** The subset of a Plaid `/transactions/sync` transaction that Droplet reads. */
export interface PlaidTransaction {
  transaction_id: string
  amount: number
  iso_currency_code: string | null
  date: string
  pending: boolean
  merchant_name?: string | null
  name?: string | null
  personal_finance_category?: { primary?: string | null } | null
}

/** One element of `apply_transactions(p_rows)`. */
export interface TransactionRow {
  plaid_transaction_id: string
  merchant_name: string
  amount_cents: number
  iso_currency_code: string
  date: string
  pending: boolean
  category: string | null
  roundup_cents: number
  roundup_status: 'pending' | 'skipped'
}

/**
 * Maps a Plaid transaction to a database row. Returns null for transactions dated before the
 * day the bank was linked, so history from before Droplet never produces drops.
 */
export function toTransactionRow(t: PlaidTransaction, linkedOn: string): TransactionRow | null {
  if (t.date < linkedOn) return null
  const amountCents = Math.round(t.amount * 100)
  // Plaid sends a null ISO code for unofficial currencies; 'XXX' is ISO 4217 "no currency".
  const currency = t.iso_currency_code ?? 'XXX'
  const category = t.personal_finance_category?.primary ?? null
  const eligible = !t.pending &&
    currency === 'USD' &&
    amountCents > 0 &&
    (category === null || !EXCLUDED_CATEGORIES.has(category))
  const roundup = eligible ? roundupCents(amountCents) : 0
  return {
    plaid_transaction_id: t.transaction_id,
    merchant_name: t.merchant_name || t.name || 'Purchase',
    amount_cents: amountCents,
    iso_currency_code: currency,
    date: t.date,
    pending: t.pending,
    category,
    roundup_cents: roundup,
    roundup_status: roundup > 0 ? 'pending' : 'skipped',
  }
}
