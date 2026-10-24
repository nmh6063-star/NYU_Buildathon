// JSON responses and the error shape from contract C1: {"error":{"code","message"}}.

export class HttpError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message)
    this.name = 'HttpError'
  }
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

/** HttpError → its status and code. Anything else → 500 INTERNAL, logged but not exposed. */
export function errorResponse(err: unknown): Response {
  if (err instanceof HttpError) {
    if (err.status >= 500) console.error(`${err.code}: ${err.message}`)
    return json({ error: { code: err.code, message: err.message } }, err.status)
  }
  console.error('Unhandled error:', err)
  return json({ error: { code: 'INTERNAL', message: 'Something went wrong. Try again.' } }, 500)
}

/** Parses a JSON object body. Throws HttpError(400, 'BAD_REQUEST') for anything else. */
export async function readJson<T>(req: Request): Promise<T> {
  let body: unknown
  try {
    body = await req.json()
  } catch {
    throw new HttpError(400, 'BAD_REQUEST', 'The request body must be JSON.')
  }
  if (typeof body !== 'object' || body === null || Array.isArray(body)) {
    throw new HttpError(400, 'BAD_REQUEST', 'The request body must be a JSON object.')
  }
  return body as T
}

/** String equality whose running time does not depend on where the strings first differ. */
export function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return diff === 0
}
