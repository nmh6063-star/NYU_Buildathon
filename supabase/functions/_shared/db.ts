// Service-role Supabase client and user-JWT check.
import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2.118.0'
import { requireEnv } from './env.ts'
import { HttpError } from './http.ts'

export type { SupabaseClient }

/** Service-role client (bypasses RLS). No session is stored or refreshed. */
export function adminClient(): SupabaseClient {
  return createClient(requireEnv('SUPABASE_URL'), requireEnv('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  })
}

/** Returns the signed-in user's id, or throws HttpError(401, 'UNAUTHORIZED'). */
export async function requireUser(req: Request, admin: SupabaseClient): Promise<string> {
  const match = /^Bearer\s+(\S+)$/i.exec(req.headers.get('Authorization') ?? '')
  if (!match) throw new HttpError(401, 'UNAUTHORIZED', 'Sign in to continue.')
  const { data, error } = await admin.auth.getUser(match[1])
  if (error || !data.user) {
    throw new HttpError(401, 'UNAUTHORIZED', 'Your session has expired. Sign in again.')
  }
  return data.user.id
}
