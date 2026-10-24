import { assertEquals, assertRejects, assertThrows } from 'jsr:@std/assert@1.0.19'
import { adminClient, requireUser, type SupabaseClient } from '../_shared/db.ts'
import { HttpError } from '../_shared/http.ts'

type GetUserResult = { data: { user: { id: string } | null }; error: { message: string } | null }

function fakeAdmin(result: GetUserResult, seen: string[] = []): SupabaseClient {
  const auth = {
    getUser: (jwt: string): Promise<GetUserResult> => {
      seen.push(jwt)
      return Promise.resolve(result)
    },
  }
  return { auth } as unknown as SupabaseClient
}

function request(headers: Record<string, string> = {}): Request {
  return new Request('http://localhost/fn', { method: 'POST', headers, body: '{}' })
}

const USER_ID = '7d0f8a52-5c6e-4b8e-9a51-2f1d3c4b5a69'

Deno.test('requireUser returns the user id for a valid bearer token', async () => {
  const seen: string[] = []
  const admin = fakeAdmin({ data: { user: { id: USER_ID } }, error: null }, seen)
  assertEquals(await requireUser(request({ Authorization: 'Bearer user-jwt' }), admin), USER_ID)
  assertEquals(seen, ['user-jwt'])
})

Deno.test('requireUser rejects a missing or malformed Authorization header', async () => {
  const seen: string[] = []
  const admin = fakeAdmin({ data: { user: { id: USER_ID } }, error: null }, seen)
  const cases: Record<string, string>[] = [
    {},
    { Authorization: 'Basic abc' },
    { Authorization: 'Bearer ' },
  ]
  for (const headers of cases) {
    const err = await assertRejects(() => requireUser(request(headers), admin), HttpError)
    assertEquals(err.status, 401)
    assertEquals(err.code, 'UNAUTHORIZED')
  }
  assertEquals(seen, [])
})

Deno.test('requireUser rejects a token that Supabase Auth does not accept', async () => {
  const admin = fakeAdmin({ data: { user: null }, error: { message: 'invalid JWT' } })
  const err = await assertRejects(
    () => requireUser(request({ Authorization: 'Bearer anon-key' }), admin),
    HttpError,
  )
  assertEquals(err.status, 401)
  assertEquals(err.code, 'UNAUTHORIZED')
})

Deno.test('adminClient needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY', () => {
  const url = Deno.env.get('SUPABASE_URL')
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  try {
    Deno.env.delete('SUPABASE_URL')
    Deno.env.delete('SUPABASE_SERVICE_ROLE_KEY')
    assertThrows(() => adminClient(), Error, 'SUPABASE_URL')
    Deno.env.set('SUPABASE_URL', 'http://127.0.0.1:54321')
    Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'test-service-role-key')
    assertEquals(typeof adminClient().from, 'function')
  } finally {
    if (url === undefined) Deno.env.delete('SUPABASE_URL')
    else Deno.env.set('SUPABASE_URL', url)
    if (key === undefined) Deno.env.delete('SUPABASE_SERVICE_ROLE_KEY')
    else Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', key)
  }
})
