import { assertEquals, assertInstanceOf, assertRejects } from 'jsr:@std/assert@1.0.19'
import { constantTimeEqual, errorResponse, HttpError, json, readJson } from '../_shared/http.ts'

function post(body: string): Request {
  return new Request('http://localhost/fn', { method: 'POST', body })
}

Deno.test('HttpError carries status, code and message', () => {
  const err = new HttpError(404, 'NO_BANK', 'Connect a bank first.')
  assertInstanceOf(err, Error)
  assertEquals(err.status, 404)
  assertEquals(err.code, 'NO_BANK')
  assertEquals(err.message, 'Connect a bank first.')
  assertEquals(err.name, 'HttpError')
})

Deno.test('json returns a JSON response, 200 by default', async () => {
  const res = json({ ok: true })
  assertEquals(res.status, 200)
  assertEquals(res.headers.get('Content-Type'), 'application/json')
  assertEquals(await res.json(), { ok: true })
  assertEquals(json({}, 201).status, 201)
})

Deno.test('errorResponse maps HttpError to its status and code', async () => {
  const res = errorResponse(new HttpError(409, 'ITEM_LOGIN_REQUIRED', 'Reconnect your bank.'))
  assertEquals(res.status, 409)
  assertEquals(await res.json(), {
    error: { code: 'ITEM_LOGIN_REQUIRED', message: 'Reconnect your bank.' },
  })
})

Deno.test('errorResponse hides unexpected errors behind 500 INTERNAL', async () => {
  for (const err of [new Error('db password is hunter2'), 'boom', null]) {
    const res = errorResponse(err)
    assertEquals(res.status, 500)
    assertEquals(await res.json(), {
      error: { code: 'INTERNAL', message: 'Something went wrong. Try again.' },
    })
  }
})

Deno.test('readJson parses a JSON object', async () => {
  assertEquals(await readJson<{ a: number }>(post('{"a":1}')), { a: 1 })
})

Deno.test('readJson rejects invalid JSON and non-objects with 400 BAD_REQUEST', async () => {
  for (const body of ['not json', '', '[]', 'null', '42']) {
    const err = await assertRejects(() => readJson(post(body)), HttpError)
    assertEquals(err.status, 400)
    assertEquals(err.code, 'BAD_REQUEST')
  }
})

Deno.test('constantTimeEqual is true only for identical strings', () => {
  assertEquals(constantTimeEqual('k7Qz-41', 'k7Qz-41'), true)
  assertEquals(constantTimeEqual('k7Qz-41', 'k7Qz-42'), false)
  assertEquals(constantTimeEqual('k7Qz-41', 'k7Qz-410'), false)
  assertEquals(constantTimeEqual('', 'k7Qz-41'), false)
  assertEquals(constantTimeEqual('', ''), true)
})
