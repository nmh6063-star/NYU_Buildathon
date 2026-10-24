import Foundation

// Wire models. Keys are snake_case on the wire; JSONDecoder.droplet / JSONEncoder.droplet convert them.

struct Asset: Codable, Sendable, Hashable, Identifiable {
    let symbol: String
    let name: String
    let chain: String
    let iconUrl: URL?
    let sortOrder: Int

    var id: String { symbol }
}

struct Profile: Codable, Sendable, Equatable {
    let id: UUID
    var displayName: String
    var thresholdCents: Int
    var targetAsset: String
    var roundupsPaused: Bool
}

/// PATCH body for `profiles`. Nil fields are omitted from the JSON.
struct ProfilePatch: Encodable, Sendable, Equatable {
    var displayName: String? = nil
    var thresholdCents: Int? = nil
    var targetAsset: String? = nil
    var roundupsPaused: Bool? = nil
}

enum BankStatus: String, Codable, Sendable {
    case active
    case loginRequired = "login_required"
    case error
}

struct BankConnection: Codable, Sendable, Equatable {
    let institutionName: String?
    let status: BankStatus
    let lastSyncedAt: Date?
}

enum RoundupStatus: String, Codable, Sendable {
    case pending, invested, skipped, reversed
}

struct Transaction: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    let merchantName: String
    let amountCents: Int
    /// Postgres `date`, formatted `yyyy-MM-dd`.
    let date: String
    let pending: Bool
    let roundupCents: Int
    let roundupStatus: RoundupStatus
    let createdAt: Date

    /// `date` as local midnight in `Calendar.current`; falls back to `createdAt` if `date` is malformed.
    var day: Date { DropletDates.localMidnight(fromDay: date) ?? createdAt }
}

struct DropSummary: Codable, Sendable, Equatable {
    let pendingCents: Int
    let thresholdCents: Int
    let lifetimeRoundupCents: Int
    let investedCents: Int

    var progress: Double { min(1, Double(pendingCents) / Double(max(thresholdCents, 1))) }
    var remainingCents: Int { max(0, thresholdCents - pendingCents) }

    static let empty = DropSummary(pendingCents: 0, thresholdCents: 500, lifetimeRoundupCents: 0, investedCents: 0)
}

struct Holding: Codable, Sendable, Identifiable, Equatable {
    let assetSymbol: String
    let assetName: String
    let iconUrl: URL?
    let investedCents: Int
    /// Decimal string, e.g. "0.053137".
    let quantity: String
    let lastInvestedAt: Date?

    var id: String { assetSymbol }
}

struct Investment: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let assetSymbol: String
    let amountCents: Int
    /// Decimal string, e.g. "99.366035688829".
    let priceUsd: String
    /// Decimal string, e.g. "0.053137".
    let quantity: String
    let mode: String
    let createdAt: Date
}

struct SyncResult: Codable, Sendable, Equatable {
    let added: Int
    let modified: Int
    let removed: Int
    let investment: Investment?
}

// MARK: - Edge Function bodies (contract C1)

/// `{}` for functions that take no input.
struct EmptyBody: Encodable, Sendable {}

/// `plaid-exchange` request. `institution_name` is sent as `null` when unknown.
struct ExchangeBody: Encodable, Sendable {
    let publicToken: String
    let institutionName: String?

    private enum CodingKeys: String, CodingKey { case publicToken, institutionName }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(publicToken, forKey: .publicToken)
        try container.encode(institutionName, forKey: .institutionName)
    }
}

/// `simulate-purchase` request.
struct SimulatePurchaseBody: Encodable, Sendable {
    let merchant: String
    let amountCents: Int
}

/// `plaid-link-token` response.
struct LinkTokenResponse: Decodable, Sendable {
    let linkToken: String
    let expiration: String
}
