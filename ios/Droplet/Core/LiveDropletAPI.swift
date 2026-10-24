import Foundation
import Supabase

/// `DropletAPI` backed by Supabase. RLS scopes every read to the signed-in user.
final class LiveDropletAPI: DropletAPI {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    convenience init(config: AppConfig) {
        self.init(client: SupabaseClient(
            supabaseURL: config.supabaseURL,
            supabaseKey: config.supabaseKey,
            options: SupabaseClientOptions(
                db: .init(encoder: .droplet, decoder: .droplet),
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        ))
    }

    // MARK: Auth

    func sessionStates() -> AsyncStream<SessionState> {
        let changes = client.auth.authStateChanges
        return AsyncStream { continuation in
            let task = Task {
                for await change in changes {
                    if let session = change.session, !session.isExpired {
                        continuation.yield(.signedIn(session.user.id))
                    } else {
                        continuation.yield(.signedOut)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func currentEmail() async -> String? {
        client.auth.currentUser?.email
    }

    func signUp(email: String, password: String, name: String) async throws {
        try await client.auth.signUp(email: email, password: password, data: ["display_name": .string(name)])
    }

    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    // MARK: Reads and profile

    func profile() async throws -> Profile {
        try await client.from("profiles").select().single().execute().value
    }

    func updateProfile(_ patch: ProfilePatch) async throws -> Profile {
        let uid = try await client.auth.session.user.id
        return try await client.from("profiles")
            .update(patch)
            .eq("id", value: uid)
            .select()
            .single()
            .execute()
            .value
    }

    func assets() async throws -> [Asset] {
        try await client.from("assets")
            .select()
            .eq("enabled", value: true)
            .order("sort_order")
            .execute()
            .value
    }

    func bankConnection() async throws -> BankConnection? {
        let rows: [BankConnection] = try await client.from("bank_connections")
            .select()
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    func transactions(limit: Int) async throws -> [Transaction] {
        try await client.from("transactions")
            .select("id,merchant_name,amount_cents,date,pending,roundup_cents,roundup_status,created_at")
            .order("date", ascending: false)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    func dropSummary() async throws -> DropSummary {
        try await client.from("drop_summary").select().single().execute().value
    }

    func portfolio() async throws -> [Holding] {
        try await client.from("portfolio_by_asset")
            .select()
            .order("invested_cents", ascending: false)
            .execute()
            .value
    }

    // MARK: Edge Functions (contract C1)

    func createLinkToken() async throws -> String {
        let response: LinkTokenResponse = try await invoke("plaid-link-token", body: EmptyBody())
        return response.linkToken
    }

    func exchange(publicToken: String, institutionName: String?) async throws -> SyncResult {
        try await invoke("plaid-exchange", body: ExchangeBody(publicToken: publicToken, institutionName: institutionName))
    }

    func sync() async throws -> SyncResult {
        try await invoke("plaid-sync", body: EmptyBody())
    }

    func simulatePurchase(merchant: String, amountCents: Int) async throws -> SyncResult {
        try await invoke("simulate-purchase", body: SimulatePurchaseBody(merchant: merchant, amountCents: amountCents))
    }

    private func invoke<Response: Decodable>(_ name: String, body: some Encodable & Sendable) async throws -> Response {
        try await client.functions.invoke(
            name,
            options: FunctionInvokeOptions(body: body, encoder: .droplet),
            decoder: .droplet
        )
    }
}
