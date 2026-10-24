// Minimal Plaid REST client: only the five endpoints Droplet uses (spec §5).
import { plaidBaseUrl, requireEnv } from './env.ts'
import { HttpError } from './http.ts'
import type { PlaidTransaction } from './roundup.ts'

export class PlaidApiError extends Error {
  constructor(
    public errorCode: string,
    public errorType: string,
    message: string,
    public status: number,
  ) {
    super(message)
    this.name = 'PlaidApiError'
  }
}

/** Shown for any Plaid rate limit; the Sandbox test-purchase endpoint is the one users hit. */
const RATE_LIMITED_MESSAGE =
  'Plaid Sandbox allows only a few test purchases per minute. Wait a moment and try again.'

function isRateLimit(err: PlaidApiError): boolean {
  return err.status === 429 || err.errorType === 'RATE_LIMIT_EXCEEDED'
}

/**
 * Contract C1 mapping: ITEM_LOGIN_REQUIRED → 409, a Plaid rate limit → 429 RATE_LIMITED,
 * any other Plaid error → 502 PLAID_ERROR.
 */
export function plaidHttpError(err: PlaidApiError): HttpError {
  if (err.errorCode === 'ITEM_LOGIN_REQUIRED') {
    return new HttpError(409, 'ITEM_LOGIN_REQUIRED', 'Your bank needs you to sign in again.')
  }
  if (isRateLimit(err)) {
    return new HttpError(429, 'RATE_LIMITED', RATE_LIMITED_MESSAGE)
  }
  return new HttpError(502, 'PLAID_ERROR', err.message)
}

/** Use as `.catch(rethrowAsHttp)` on a direct Plaid call inside an Edge Function. */
export function rethrowAsHttp(err: unknown): never {
  throw err instanceof PlaidApiError ? plaidHttpError(err) : err
}

export interface TransactionsSyncPage {
  added: PlaidTransaction[]
  modified: PlaidTransaction[]
  removed: { transaction_id: string }[]
  next_cursor: string
  has_more: boolean
}

export interface SandboxTransaction {
  date_transacted: string
  date_posted: string
  amount: number
  description: string
}

export class PlaidClient {
  readonly #clientId: string
  readonly #secret: string
  readonly #baseUrl: string
  readonly #fetchFn: typeof fetch

  constructor(opts: { clientId: string; secret: string; baseUrl: string; fetchFn?: typeof fetch }) {
    this.#clientId = opts.clientId
    this.#secret = opts.secret
    this.#baseUrl = opts.baseUrl
    this.#fetchFn = opts.fetchFn ?? fetch
  }

  static fromEnv(fetchFn?: typeof fetch): PlaidClient {
    return new PlaidClient({
      clientId: requireEnv('PLAID_CLIENT_ID'),
      secret: requireEnv('PLAID_SECRET'),
      baseUrl: plaidBaseUrl(),
      fetchFn,
    })
  }

  async linkTokenCreate(
    args: { userId: string; webhook?: string },
  ): Promise<{ link_token: string; expiration: string }> {
    const data = await this.#post<{ link_token: string; expiration: string }>(
      '/link/token/create',
      {
        client_name: 'Droplet',
        language: 'en',
        country_codes: ['US'],
        user: { client_user_id: args.userId },
        products: ['transactions'],
        transactions: { days_requested: 30 },
        ...(args.webhook ? { webhook: args.webhook } : {}),
      },
    )
    return { link_token: data.link_token, expiration: data.expiration }
  }

  async exchangePublicToken(
    publicToken: string,
  ): Promise<{ access_token: string; item_id: string }> {
    const data = await this.#post<{ access_token: string; item_id: string }>(
      '/item/public_token/exchange',
      { public_token: publicToken },
    )
    return { access_token: data.access_token, item_id: data.item_id }
  }

  async transactionsSync(
    accessToken: string,
    cursor: string | null,
  ): Promise<TransactionsSyncPage> {
    const data = await this.#post<TransactionsSyncPage>('/transactions/sync', {
      access_token: accessToken,
      count: 500,
      ...(cursor ? { cursor } : {}),
    })
    return {
      added: data.added,
      modified: data.modified,
      removed: data.removed,
      next_cursor: data.next_cursor,
      has_more: data.has_more,
    }
  }

  async sandboxTransactionsCreate(accessToken: string, txns: SandboxTransaction[]): Promise<void> {
    await this.#post('/sandbox/transactions/create', {
      access_token: accessToken,
      transactions: txns,
    })
  }

  async webhookVerificationKey(keyId: string): Promise<JsonWebKey> {
    const data = await this.#post<{ key: JsonWebKey }>('/webhook_verification_key/get', {
      key_id: keyId,
    })
    return data.key
  }

  async #post<T>(path: string, body: Record<string, unknown>): Promise<T> {
    const res = await this.#fetchFn(`${this.#baseUrl}${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ client_id: this.#clientId, secret: this.#secret, ...body }),
    })
    const data = (await res.json().catch(() => null)) as Record<string, unknown> | null
    // Log the request id for support, never the request body (it carries the secret and tokens).
    console.log(`plaid ${path} status=${res.status} request_id=${data?.request_id ?? 'none'}`)
    if (!res.ok || data === null) {
      throw new PlaidApiError(
        String(data?.error_code ?? 'UNKNOWN'),
        String(data?.error_type ?? 'API_ERROR'),
        String(data?.error_message ?? `Plaid ${path} failed with HTTP ${res.status}`),
        res.status,
      )
    }
    return data as T
  }
}
