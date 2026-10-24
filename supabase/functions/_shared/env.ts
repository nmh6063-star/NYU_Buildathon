// Environment access and the "today" rule shared by every function.

/** Returns the variable's value, or throws (→ 500 INTERNAL) when it is missing or empty. */
export function requireEnv(name: string): string {
  const value = Deno.env.get(name)
  if (!value) throw new Error(`Missing environment variable ${name}`)
  return value
}

/** Plaid API base URL for `env` (defaults to the PLAID_ENV variable). */
export function plaidBaseUrl(env: string = requireEnv('PLAID_ENV')): string {
  switch (env) {
    case 'sandbox':
      return 'https://sandbox.plaid.com'
    case 'production':
      return 'https://production.plaid.com'
    default:
      throw new Error(`Unsupported PLAID_ENV "${env}" (use sandbox or production)`)
  }
}

const NEW_YORK_DAY = new Intl.DateTimeFormat('en-US', {
  timeZone: 'America/New_York',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
})

/** The America/New_York calendar date of `now`, as YYYY-MM-DD. */
export function todayInNewYork(now: Date = new Date()): string {
  const parts = Object.fromEntries(
    NEW_YORK_DAY.formatToParts(now).map((part) => [part.type, part.value]),
  )
  return `${parts.year}-${parts.month}-${parts.day}`
}
