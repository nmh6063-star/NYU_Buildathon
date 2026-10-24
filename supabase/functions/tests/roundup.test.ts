import { assertEquals } from 'jsr:@std/assert@1.0.19'
import {
  EXCLUDED_CATEGORIES,
  type PlaidTransaction,
  roundupCents,
  toTransactionRow,
} from '../_shared/roundup.ts'

const LINKED_ON = '2026-10-24'

function plaidTxn(overrides: Partial<PlaidTransaction> = {}): PlaidTransaction {
  return {
    transaction_id: 'txn-1',
    amount: 5.67,
    iso_currency_code: 'USD',
    date: '2026-10-24',
    pending: false,
    merchant_name: 'Blue Bottle',
    name: 'BLUE BOTTLE COFFEE #42',
    personal_finance_category: { primary: 'FOOD_AND_DRINK' },
    ...overrides,
  }
}

Deno.test('roundupCents rounds up to the next dollar', () => {
  assertEquals(roundupCents(567), 33)
  assertEquals(roundupCents(1342), 58)
  assertEquals(roundupCents(2318), 82)
  assertEquals(roundupCents(1), 99)
})

Deno.test('roundupCents is 0 for whole dollars, zero and refunds', () => {
  assertEquals(roundupCents(400), 0)
  assertEquals(roundupCents(0), 0)
  assertEquals(roundupCents(-1200), 0)
})

Deno.test('EXCLUDED_CATEGORIES lists the five non-purchase categories', () => {
  assertEquals([...EXCLUDED_CATEGORIES].sort(), [
    'BANK_FEES',
    'INCOME',
    'LOAN_PAYMENTS',
    'TRANSFER_IN',
    'TRANSFER_OUT',
  ])
})

Deno.test('toTransactionRow maps a settled USD purchase to a pending round-up', () => {
  assertEquals(toTransactionRow(plaidTxn(), LINKED_ON), {
    plaid_transaction_id: 'txn-1',
    merchant_name: 'Blue Bottle',
    amount_cents: 567,
    iso_currency_code: 'USD',
    date: '2026-10-24',
    pending: false,
    category: 'FOOD_AND_DRINK',
    roundup_cents: 33,
    roundup_status: 'pending',
  })
})

Deno.test('toTransactionRow converts dollars to cents with Math.round', () => {
  assertEquals(toTransactionRow(plaidTxn({ amount: 5.67 }), LINKED_ON)?.amount_cents, 567)
  assertEquals(toTransactionRow(plaidTxn({ amount: 0.07 }), LINKED_ON)?.amount_cents, 7)
  assertEquals(toTransactionRow(plaidTxn({ amount: 19.99 }), LINKED_ON)?.amount_cents, 1999)
})

Deno.test('toTransactionRow skips pending transactions', () => {
  const row = toTransactionRow(plaidTxn({ pending: true }), LINKED_ON)
  assertEquals(row?.pending, true)
  assertEquals(row?.roundup_cents, 0)
  assertEquals(row?.roundup_status, 'skipped')
})

Deno.test('toTransactionRow skips non-USD and unknown currencies', () => {
  const cad = toTransactionRow(plaidTxn({ iso_currency_code: 'CAD' }), LINKED_ON)
  assertEquals(cad?.iso_currency_code, 'CAD')
  assertEquals(cad?.roundup_cents, 0)
  assertEquals(cad?.roundup_status, 'skipped')
  const unknown = toTransactionRow(plaidTxn({ iso_currency_code: null }), LINKED_ON)
  assertEquals(unknown?.iso_currency_code, 'XXX')
  assertEquals(unknown?.roundup_status, 'skipped')
})

Deno.test('toTransactionRow skips excluded categories', () => {
  for (const primary of EXCLUDED_CATEGORIES) {
    const row = toTransactionRow(plaidTxn({ personal_finance_category: { primary } }), LINKED_ON)
    assertEquals(row?.category, primary)
    assertEquals(row?.roundup_cents, 0)
    assertEquals(row?.roundup_status, 'skipped')
  }
})

Deno.test('toTransactionRow skips whole-dollar purchases and refunds', () => {
  const whole = toTransactionRow(plaidTxn({ amount: 4 }), LINKED_ON)
  assertEquals(whole?.roundup_cents, 0)
  assertEquals(whole?.roundup_status, 'skipped')
  const refund = toTransactionRow(plaidTxn({ amount: -12 }), LINKED_ON)
  assertEquals(refund?.amount_cents, -1200)
  assertEquals(refund?.roundup_status, 'skipped')
})

Deno.test('toTransactionRow returns null before linked_on and keeps the linked_on day', () => {
  assertEquals(toTransactionRow(plaidTxn({ date: '2026-10-23' }), LINKED_ON), null)
  assertEquals(toTransactionRow(plaidTxn({ date: '2026-10-24' }), LINKED_ON)?.date, '2026-10-24')
})

Deno.test('toTransactionRow falls back from merchant_name to name to "Purchase"', () => {
  assertEquals(
    toTransactionRow(plaidTxn({ merchant_name: null }), LINKED_ON)?.merchant_name,
    'BLUE BOTTLE COFFEE #42',
  )
  assertEquals(
    toTransactionRow(plaidTxn({ merchant_name: '', name: undefined }), LINKED_ON)?.merchant_name,
    'Purchase',
  )
  assertEquals(
    toTransactionRow(plaidTxn({ merchant_name: undefined, name: null }), LINKED_ON)?.merchant_name,
    'Purchase',
  )
})

Deno.test('toTransactionRow stores a null category when Plaid sends none', () => {
  const row = toTransactionRow(plaidTxn({ personal_finance_category: null }), LINKED_ON)
  assertEquals(row?.category, null)
  assertEquals(row?.roundup_status, 'pending')
})
