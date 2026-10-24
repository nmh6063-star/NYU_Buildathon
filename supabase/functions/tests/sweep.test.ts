import { assertEquals } from 'jsr:@std/assert@1.0.19'
import { sweepIfReady } from '../_shared/sweep.ts'
import type { InvestmentJson, SyncStore } from '../_shared/sync.ts'

const USER = 'user-1'
const INVESTMENT: InvestmentJson = {
  id: '6f1c2a9e-0d1b-4c33-9a57-0b6f3a2f9e10',
  asset_symbol: 'SOL',
  amount_cents: 528,
  price_usd: '99.366035688829',
  quantity: '0.053137',
  mode: 'simulated',
  created_at: '2026-10-24T16:03:11.482Z',
}

type Summary = Awaited<ReturnType<SyncStore['pendingAndThreshold']>>

function fakeStore(summary: Summary, result: InvestmentJson | null = INVESTMENT) {
  const sweeps: { userId: string; asset: string; price: string }[] = []
  const store: SyncStore = {
    applyTransactions: () => Promise.resolve(),
    saveCursor: () => Promise.resolve(),
    setStatus: () => Promise.resolve(),
    pendingAndThreshold: () => Promise.resolve(summary),
    sweep: (userId, asset, price) => {
      sweeps.push({ userId, asset, price })
      return Promise.resolve(result)
    },
  }
  return { store, sweeps }
}

function fakePrice(value: string | Error) {
  const asked: string[] = []
  const price = (symbol: string): Promise<string> => {
    asked.push(symbol)
    return value instanceof Error ? Promise.reject(value) : Promise.resolve(value)
  }
  return { price, asked }
}

const READY: Summary = { pendingCents: 528, thresholdCents: 500, targetAsset: 'SOL', paused: false }

Deno.test('sweepIfReady does nothing below the threshold', async () => {
  const { store, sweeps } = fakeStore({ ...READY, pendingCents: 499 })
  const { price, asked } = fakePrice('99.36')
  assertEquals(await sweepIfReady(store, price, USER), null)
  assertEquals(asked, [])
  assertEquals(sweeps, [])
})

Deno.test('sweepIfReady does nothing while round-ups are paused', async () => {
  const { store, sweeps } = fakeStore({ ...READY, paused: true })
  const { price, asked } = fakePrice('99.36')
  assertEquals(await sweepIfReady(store, price, USER), null)
  assertEquals(asked, [])
  assertEquals(sweeps, [])
})

Deno.test('sweepIfReady prices the target asset and sweeps at the threshold', async () => {
  const { store, sweeps } = fakeStore({ ...READY, pendingCents: 500, targetAsset: 'ETH' })
  const { price, asked } = fakePrice('2295.96')
  assertEquals(await sweepIfReady(store, price, USER), INVESTMENT)
  assertEquals(asked, ['ETH'])
  assertEquals(sweeps, [{ userId: USER, asset: 'ETH', price: '2295.96' }])
})

Deno.test('sweepIfReady returns null and skips the sweep when the price fetch fails', async () => {
  const { store, sweeps } = fakeStore(READY)
  const { price } = fakePrice(new Error('True Markets price for SOL: HTTP 503'))
  assertEquals(await sweepIfReady(store, price, USER), null)
  assertEquals(sweeps, [])
})

Deno.test('sweepIfReady returns null when the database sweep invests nothing', async () => {
  const { store } = fakeStore(READY, null)
  const { price } = fakePrice('99.36')
  assertEquals(await sweepIfReady(store, price, USER), null)
})
