// Threshold check + price fetch in front of the atomic `sweep_drops` RPC (spec §4.3).
import type { InvestmentJson, SyncStore } from './sync.ts'

/**
 * Invests every pending drop once the total reaches the user's threshold. Returns null when
 * paused, below the threshold, or when the price fetch fails (the drops stay pending and the
 * next sync retries).
 */
export async function sweepIfReady(
  store: SyncStore,
  price: (symbol: string) => Promise<string>,
  userId: string,
): Promise<InvestmentJson | null> {
  const { pendingCents, thresholdCents, targetAsset, paused } = await store.pendingAndThreshold(
    userId,
  )
  if (paused || pendingCents < thresholdCents) return null
  let priceUsd: string
  try {
    priceUsd = await price(targetAsset)
  } catch (err) {
    console.warn(`sweep skipped for user_id=${userId}: ${err instanceof Error ? err.message : err}`)
    return null
  }
  return await store.sweep(userId, targetAsset, priceUsd)
}
