import { assertEquals, assertInstanceOf, assertRejects } from 'jsr:@std/assert@1.0.19'
import { fetchPrice } from '../_shared/prices.ts'

// Captured from GET https://api.truemarkets.co/v1/defi/market/prices?symbol=SOL
const SOL_RESPONSE = {
  symbol: 'SOL',
  candles: [
    {
      interval: '1h',
      openPrice: '100.36',
      closePrice: '99.36',
      highPrice: '100.39',
      lowPrice: '98.55',
    },
    {
      interval: '30s',
      openPrice: '99.39',
      closePrice: '99.366035688829',
      highPrice: '99.39',
      lowPrice: '99.33',
    },
  ],
}

type Call = { url: string; init?: RequestInit }

function fakeFetch(status: number, body: unknown, calls: Call[] = []): typeof fetch {
  return ((input: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(input), init })
    const text = typeof body === 'string' ? body : JSON.stringify(body)
    return Promise.resolve(new Response(text, { status }))
  }) as typeof fetch
}

function withCandles(candles: unknown[]): unknown {
  return { symbol: 'SOL', candles }
}

Deno.test('fetchPrice returns the 30s candle closePrice as a string', async () => {
  const calls: Call[] = []
  assertEquals(await fetchPrice('SOL', fakeFetch(200, SOL_RESPONSE, calls)), '99.366035688829')
  assertEquals(calls.length, 1)
  assertEquals(calls[0].url, 'https://api.truemarkets.co/v1/defi/market/prices?symbol=SOL')
  assertInstanceOf(calls[0].init?.signal, AbortSignal)
})

Deno.test('fetchPrice URL-encodes the symbol', async () => {
  const calls: Call[] = []
  await fetchPrice('A&B', fakeFetch(200, SOL_RESPONSE, calls))
  assertEquals(calls[0].url, 'https://api.truemarkets.co/v1/defi/market/prices?symbol=A%26B')
})

Deno.test('fetchPrice times out after 5 seconds', async () => {
  const original = AbortSignal.timeout
  const seen: number[] = []
  AbortSignal.timeout = (ms: number) => {
    seen.push(ms)
    return original.call(AbortSignal, ms)
  }
  try {
    await fetchPrice('SOL', fakeFetch(200, SOL_RESPONSE))
  } finally {
    AbortSignal.timeout = original
  }
  assertEquals(seen, [5000])
})

Deno.test('fetchPrice throws on a non-200 response', async () => {
  await assertRejects(() => fetchPrice('SOL', fakeFetch(503, 'unavailable')), Error, '503')
})

Deno.test('fetchPrice throws on a body that is not JSON', async () => {
  await assertRejects(() => fetchPrice('SOL', fakeFetch(200, '<html>')), Error)
})

Deno.test('fetchPrice throws when there is no 30s candle', async () => {
  const body = withCandles([SOL_RESPONSE.candles[0]])
  await assertRejects(() => fetchPrice('SOL', fakeFetch(200, body)), Error, '30s')
  await assertRejects(() => fetchPrice('SOL', fakeFetch(200, { symbol: 'SOL' })), Error, '30s')
})

Deno.test('fetchPrice throws on a missing, malformed or non-positive price', async () => {
  for (const closePrice of [undefined, 99.4, 'abc', '', '0', '0.000', '-1']) {
    const body = withCandles([{ interval: '30s', closePrice }])
    await assertRejects(() => fetchPrice('SOL', fakeFetch(200, body)), Error, 'closePrice')
  }
})
