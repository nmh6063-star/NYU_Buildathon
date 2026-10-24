import Foundation

enum SessionState: Sendable, Equatable {
    case signedOut
    case signedIn(UUID)
}

/// Everything the UI needs from the backend. `LiveDropletAPI` talks to Supabase;
/// `PreviewDropletAPI` is an in-memory fake for previews and tests.
protocol DropletAPI: Sendable {
    /// Yields the current state first, then every change.
    func sessionStates() -> AsyncStream<SessionState>
    func currentEmail() async -> String?
    func signUp(email: String, password: String, name: String) async throws
    func signIn(email: String, password: String) async throws
    func signOut() async throws

    func profile() async throws -> Profile
    func updateProfile(_ patch: ProfilePatch) async throws -> Profile
    func assets() async throws -> [Asset]
    func bankConnection() async throws -> BankConnection?

    func createLinkToken() async throws -> String
    func exchange(publicToken: String, institutionName: String?) async throws -> SyncResult
    func sync() async throws -> SyncResult
    func simulatePurchase(merchant: String, amountCents: Int) async throws -> SyncResult

    func transactions(limit: Int) async throws -> [Transaction]
    func dropSummary() async throws -> DropSummary
    func portfolio() async throws -> [Holding]
}
