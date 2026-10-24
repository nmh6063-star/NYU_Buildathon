import { assertEquals, assertInstanceOf, assertRejects, assertThrows } from 'jsr:@std/assert@1.0.19'
import { HttpError } from '../_shared/http.ts'
import { PlaidApiError, PlaidClient, plaidHttpError, rethrowAsHttp } from '../_shared/plaid.ts'

type Call = { url: string; method?: string; contentType: string | null; body: unknown }
type Reply = { status?: number; body: unknown }

function fakePlaid(replies: Reply[]): { client: PlaidClient; calls: Call[] } {
  const calls: Call[] = []
  const fetchFn = ((input: string | URL | Request, init?: RequestInit) => {
    calls.push({
      url: String(input),
      method: init?.method,
      contentType: new Headers(init?.headers).get('Content-Type'),
      body: JSON.parse(String(init?.body)),
    })
    const reply = replies.shift() ?? { body: {} }
    const text = typeof reply.body === 'string' ? reply.body : JSON.stringify(reply.body)
    return Promise.resolve(new Response(text, { status: reply.status ?? 200 }))
  }) as typeof fetch
  const client = new PlaidClient({
    clientId: 'client-123',
    secret: 'secret-abc',
    baseUrl: 'https://sandbox.plaid.com',
    fetchFn,
  })
  return { client, calls }
}

const CREDENTIALS = { client_id: 'client-123', secret: 'secret-abc' }

Deno.test('linkTokenCreate posts the spec fields with credentials', async () => {
  const { client, calls } = fakePlaid([{
    body: {
      link_token: 'link-sandbox-1',
      expiration: '2026-10-24T20:00:00Z',
      request_id: 'req-1',
    },
  }])
  const result = await client.linkTokenCreate({
    userId: 'user-1',
    webhook: 'https://example.supabase.co/functions/v1/plaid-webhook',
  })
  assertEquals(result, { link_token: 'link-sandbox-1', expiration: '2026-10-24T20:00:00Z' })
  assertEquals(calls.length, 1)
  assertEquals(calls[0].url, 'https://sandbox.plaid.com/link/token/create')
  assertEquals(calls[0].method, 'POST')
  assertEquals(calls[0].contentType, 'application/json')
  assertEquals(calls[0].body, {
    ...CREDENTIALS,
    client_name: 'Droplet',
    language: 'en',
    country_codes: ['US'],
    user: { client_user_id: 'user-1' },
    products: ['transactions'],
    transactions: { days_requested: 30 },
    webhook: 'https://example.supabase.co/functions/v1/plaid-webhook',
  })
})

Deno.test('linkTokenCreate omits webhook when none is configured', async () => {
  const { client, calls } = fakePlaid([{ body: { link_token: 'l', expiration: 'e' } }])
  await client.linkTokenCreate({ userId: 'user-1' })
  assertEquals('webhook' in (calls[0].body as Record<string, unknown>), false)
})

Deno.test('exchangePublicToken returns the access token and item id', async () => {
  const { client, calls } = fakePlaid([{
    body: { access_token: 'access-test-token', item_id: 'item-1', request_id: 'req-2' },
  }])
  assertEquals(await client.exchangePublicToken('public-test-token'), {
    access_token: 'access-test-token',
    item_id: 'item-1',
  })
  assertEquals(calls[0].url, 'https://sandbox.plaid.com/item/public_token/exchange')
  assertEquals(calls[0].body, { ...CREDENTIALS, public_token: 'public-test-token' })
})

Deno.test('transactionsSync omits a null cursor and asks for 500 rows', async () => {
  const page = {
    added: [{
      transaction_id: 't1',
      amount: 5.67,
      iso_currency_code: 'USD',
      date: '2026-10-24',
      pending: false,
    }],
    modified: [],
    removed: [{ transaction_id: 't0' }],
    next_cursor: 'cursor-1',
    has_more: false,
    accounts: [],
    request_id: 'req-3',
  }
  const { client, calls } = fakePlaid([{ body: page }])
  assertEquals(await client.transactionsSync('access-test-token', null), {
    added: page.added,
    modified: [],
    removed: [{ transaction_id: 't0' }],
    next_cursor: 'cursor-1',
    has_more: false,
  })
  assertEquals(calls[0].url, 'https://sandbox.plaid.com/transactions/sync')
  assertEquals(calls[0].body, { ...CREDENTIALS, access_token: 'access-test-token', count: 500 })
})

Deno.test('transactionsSync sends the stored cursor', async () => {
  const { client, calls } = fakePlaid([{
    body: { added: [], modified: [], removed: [], next_cursor: 'c2', has_more: false },
  }])
  await client.transactionsSync('access-test-token', 'c1')
  assertEquals(calls[0].body, {
    ...CREDENTIALS,
    access_token: 'access-test-token',
    count: 500,
    cursor: 'c1',
  })
})

Deno.test('sandboxTransactionsCreate posts the transactions', async () => {
  const { client, calls } = fakePlaid([{ body: { request_id: 'req-4' } }])
  const txns = [{
    date_transacted: '2026-10-24',
    date_posted: '2026-10-24',
    amount: 5.67,
    description: 'Blue Bottle',
  }]
  await client.sandboxTransactionsCreate('access-test-token', txns)
  assertEquals(calls[0].url, 'https://sandbox.plaid.com/sandbox/transactions/create')
  assertEquals(calls[0].body, {
    ...CREDENTIALS,
    access_token: 'access-test-token',
    transactions: txns,
  })
})

Deno.test('webhookVerificationKey returns the JWK', async () => {
  const key = { kty: 'EC', crv: 'P-256', x: 'x', y: 'y', alg: 'ES256', kid: 'kid-1' }
  const { client, calls } = fakePlaid([{ body: { key, request_id: 'req-5' } }])
  assertEquals(await client.webhookVerificationKey('kid-1'), key)
  assertEquals(calls[0].url, 'https://sandbox.plaid.com/webhook_verification_key/get')
  assertEquals(calls[0].body, { ...CREDENTIALS, key_id: 'kid-1' })
})

Deno.test('a non-2xx response throws PlaidApiError with the Plaid error fields', async () => {
  const { client } = fakePlaid([{
    status: 400,
    body: {
      error_type: 'ITEM_ERROR',
      error_code: 'ITEM_LOGIN_REQUIRED',
      error_message: 'the login details of this item have changed',
      request_id: 'req-6',
    },
  }])
  const err = await assertRejects(() => client.transactionsSync('a', null), PlaidApiError)
  assertEquals(err.errorCode, 'ITEM_LOGIN_REQUIRED')
  assertEquals(err.errorType, 'ITEM_ERROR')
  assertEquals(err.message, 'the login details of this item have changed')
  assertEquals(err.status, 400)
})

Deno.test('a non-JSON response throws PlaidApiError', async () => {
  const { client } = fakePlaid([{ status: 502, body: '<html>bad gateway</html>' }])
  const err = await assertRejects(() => client.exchangePublicToken('p'), PlaidApiError)
  assertEquals(err.errorCode, 'UNKNOWN')
  assertEquals(err.status, 502)
  const ok = fakePlaid([{ status: 200, body: 'not json' }])
  await assertRejects(() => ok.client.exchangePublicToken('p'), PlaidApiError)
})

Deno.test('plaidHttpError maps login-required to 409 and the rest to 502', () => {
  const login = plaidHttpError(new PlaidApiError('ITEM_LOGIN_REQUIRED', 'ITEM_ERROR', 'm', 400))
  assertEquals([login.status, login.code], [409, 'ITEM_LOGIN_REQUIRED'])
  const other = plaidHttpError(new PlaidApiError('RATE_LIMIT_EXCEEDED', 'RATE_LIMIT', 'slow', 429))
  assertEquals([other.status, other.code, other.message], [502, 'PLAID_ERROR', 'slow'])
})

Deno.test('rethrowAsHttp converts PlaidApiError and passes other errors through', () => {
  const plaid = new PlaidApiError('INVALID_FIELD', 'INVALID_REQUEST', 'bad field', 400)
  const err = assertThrows(() => rethrowAsHttp(plaid), HttpError)
  assertEquals([err.status, err.code], [502, 'PLAID_ERROR'])
  const plain = new TypeError('boom')
  assertInstanceOf(assertThrows(() => rethrowAsHttp(plain)), TypeError)
})

Deno.test('fromEnv reads PLAID_CLIENT_ID, PLAID_SECRET and PLAID_ENV', async () => {
  const names = ['PLAID_CLIENT_ID', 'PLAID_SECRET', 'PLAID_ENV']
  const saved = names.map((name) => Deno.env.get(name))
  try {
    for (const name of names) Deno.env.delete(name)
    assertThrows(() => PlaidClient.fromEnv(), Error, 'PLAID_CLIENT_ID')
    Deno.env.set('PLAID_CLIENT_ID', 'env-client')
    Deno.env.set('PLAID_SECRET', 'env-secret')
    Deno.env.set('PLAID_ENV', 'sandbox')
    const urls: string[] = []
    let sent: unknown
    const fetchFn = ((input: string | URL | Request, init?: RequestInit) => {
      urls.push(String(input))
      sent = JSON.parse(String(init?.body))
      return Promise.resolve(Response.json({ access_token: 'a', item_id: 'i' }))
    }) as typeof fetch
    await PlaidClient.fromEnv(fetchFn).exchangePublicToken('p')
    assertEquals(urls, ['https://sandbox.plaid.com/item/public_token/exchange'])
    assertEquals(sent, { client_id: 'env-client', secret: 'env-secret', public_token: 'p' })
  } finally {
    names.forEach((name, i) => {
      const value = saved[i]
      if (value === undefined) Deno.env.delete(name)
      else Deno.env.set(name, value)
    })
  }
})
