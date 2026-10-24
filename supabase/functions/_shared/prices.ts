// Live asset price from True Markets' public market-data endpoint (no auth, no key).

const PRICES_URL = 'https://api.truemarkets.co/v1/defi/market/prices'
const TIMEOUT_MS = 5000
const DECIMAL = /^\d+(\.\d+)?$/

interface Candle {
  interval?: string
  closePrice?: unknown
}

/** USD price of `symbol` as a decimal string: the closePrice of the "30s" candle. */
export async function fetchPrice(symbol: string, fetchFn: typeof fetch = fetch): Promise<string> {
  const url = `${PRICES_URL}?symbol=${encodeURIComponent(symbol)}`
  const res = await fetchFn(url, {
    headers: { Accept: 'application/json' },
    signal: AbortSignal.timeout(TIMEOUT_MS),
  })
  if (!res.ok) {
    await res.body?.cancel()
    throw new Error(`True Markets price for ${symbol}: HTTP ${res.status}`)
  }
  const body = (await res.json()) as { candles?: Candle[] }
  const candle = body.candles?.find((c) => c.interval === '30s')
  if (!candle) throw new Error(`True Markets price for ${symbol}: no 30s candle`)
  const price = candle.closePrice
  if (typeof price !== 'string' || !DECIMAL.test(price) || !(Number(price) > 0)) {
    throw new Error(`True Markets price for ${symbol}: bad closePrice ${JSON.stringify(price)}`)
  }
  return price
}
