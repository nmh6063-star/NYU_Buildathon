import Foundation

/// Fixture data for `PreviewDropletAPI`.
struct PreviewSeed: Sendable {
    var profile: Profile
    var assets: [Asset]
    var transactions: [Transaction]
    var holdings: [Holding]
    var summary: DropSummary

    static let userID = UUID(uuidString: "6F1C3A52-9D4B-4E8A-B7C1-2D5E8F9A0B13")!

    static let curatedAssets: [Asset] = [
        Asset(symbol: "SOL", name: "Solana", chain: "solana",
              iconUrl: URL(string: "https://coin-images.coingecko.com/coins/images/4128/large/solana.png?1718769756"), sortOrder: 1),
        Asset(symbol: "ETH", name: "Ethereum", chain: "base",
              iconUrl: URL(string: "https://coin-images.coingecko.com/coins/images/279/large/ethereum.png?1696501628"), sortOrder: 2),
        Asset(symbol: "CBBTC", name: "Bitcoin (cbBTC)", chain: "base",
              iconUrl: URL(string: "https://coin-images.coingecko.com/coins/images/40143/large/cbbtc.webp?1726136727"), sortOrder: 3),
        Asset(symbol: "AAVE", name: "Aave", chain: "base",
              iconUrl: URL(string: "https://coin-images.coingecko.com/coins/images/12645/large/aave-token-round.png?1720472354"), sortOrder: 4),
        Asset(symbol: "JUP", name: "Jupiter", chain: "solana",
              iconUrl: URL(string: "https://coin-images.coingecko.com/coins/images/34188/large/jup.png?1704266489"), sortOrder: 5),
        Asset(symbol: "RENDER", name: "Render", chain: "solana",
              iconUrl: URL(string: "https://coin-images.coingecko.com/coins/images/11636/large/rndr.png?1696511529"), sortOrder: 6),
    ]

    /// A linked user part-way to their next drop: $3.21 of $5.00 pending, three holdings.
    static let demo: PreviewSeed = {
        let transactions: [Transaction] = [
            purchase("Shake Shack", 1875, hoursAgo: 0.5, .skipped, pending: true),
            purchase("Blue Bottle Coffee", 567, hoursAgo: 3, .pending),
            purchase("Sweetgreen", 1342, hoursAgo: 26, .pending),
            purchase("Uber", 2318, hoursAgo: 30, .pending),
            purchase("Joe's Pizza", 1251, hoursAgo: 46, .pending),
            purchase("Whole Foods Market", 3401, hoursAgo: 49, .pending),
            purchase("Shell", 4000, hoursAgo: 58, .skipped),
            purchase("Duane Reade", 1311, hoursAgo: 70, .invested),
            purchase("Lyft", 1312, hoursAgo: 73, .reversed),
            purchase("Uber", 1823, hoursAgo: 80, .invested),
            purchase("CVS Pharmacy", 2836, hoursAgo: 95, .invested),
            purchase("Pret A Manger", 1207, hoursAgo: 99, .invested),
            purchase("Trader Joe's", 3247, hoursAgo: 118, .invested),
            purchase("Chipotle", 1089, hoursAgo: 123, .invested),
            purchase("Starbucks", 615, hoursAgo: 140, .invested),
            purchase("Target", 2675, hoursAgo: 145, .invested),
            purchase("Netflix", 1549, hoursAgo: 150, .invested),
        ]
        let holdings: [Holding] = [
            holding("SOL", investedCents: 1096, quantity: "0.060074545", daysAgo: 3),
            holding("ETH", investedCents: 527, quantity: "0.001344388", daysAgo: 9),
            holding("CBBTC", investedCents: 503, quantity: "0.000046041", daysAgo: 16),
        ]
        let pending = transactions.filter { $0.roundupStatus == .pending }.reduce(0) { $0 + $1.roundupCents }
        let invested = holdings.reduce(0) { $0 + $1.investedCents }
        return PreviewSeed(
            profile: Profile(id: userID, displayName: "Alex Rivera", thresholdCents: 500, targetAsset: "SOL", roundupsPaused: false),
            assets: curatedAssets,
            transactions: transactions,
            holdings: holdings,
            summary: DropSummary(
                pendingCents: pending, thresholdCents: 500,
                lifetimeRoundupCents: pending + invested, investedCents: invested
            )
        )
    }()

    /// A brand-new user: default settings, no activity.
    static let empty = PreviewSeed(
        profile: Profile(id: userID, displayName: "", thresholdCents: 500, targetAsset: "SOL", roundupsPaused: false),
        assets: curatedAssets,
        transactions: [],
        holdings: [],
        summary: .empty
    )

    /// Timestamps count back from now so the seed never contains future rows.
    private static func purchase(
        _ merchant: String, _ amountCents: Int, hoursAgo: Double, _ status: RoundupStatus, pending: Bool = false
    ) -> Transaction {
        let createdAt = Date.now.addingTimeInterval(-hoursAgo * 3600)
        let roundup = (status == .pending || status == .invested) ? Money.roundupCents(forAmountCents: amountCents) : 0
        return Transaction(
            id: UUID(), merchantName: merchant, amountCents: amountCents, date: DropletDates.dayString(createdAt),
            pending: pending, roundupCents: roundup, roundupStatus: status, createdAt: createdAt
        )
    }

    private static func holding(_ symbol: String, investedCents: Int, quantity: String, daysAgo: Int) -> Holding {
        let asset = curatedAssets.first { $0.symbol == symbol }!
        return Holding(
            assetSymbol: symbol, assetName: asset.name, iconUrl: asset.iconUrl, investedCents: investedCents,
            quantity: quantity, lastInvestedAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)
        )
    }
}

/// In-memory `DropletAPI` for SwiftUI previews and unit tests. Mirrors the server rules:
/// round-ups accumulate as pending drops and sweep into the target asset at the threshold.
actor PreviewDropletAPI: DropletAPI {
    /// Made-up fill prices for previews only.
    static let prices: [String: String] = [
        "SOL": "182.44", "ETH": "3920.17", "CBBTC": "109250.5", "AAVE": "268.9", "JUP": "0.5128", "RENDER": "3.62",
    ]

    private static let posix = Locale(identifier: "en_US_POSIX")

    private var session: SessionState
    private var email: String?
    private var profileValue: Profile
    private var assetList: [Asset]
    private var bank: BankConnection?
    private var transactionList: [Transaction]
    private var holdingList: [Holding]
    private var summary: DropSummary
    private var nextError: (any Error)?
    private var observers: [UUID: AsyncStream<SessionState>.Continuation] = [:]

    /// Method names in call order, for tests.
    private(set) var calls: [String] = []

    init(signedIn: Bool = true, hasBank: Bool = true, seed: PreviewSeed = .demo) {
        session = signedIn ? .signedIn(seed.profile.id) : .signedOut
        email = signedIn ? "alex@example.com" : nil
        profileValue = seed.profile
        assetList = seed.assets
        bank = hasBank ? BankConnection(institutionName: "First Platypus Bank", status: .active, lastSyncedAt: .now) : nil
        transactionList = seed.transactions
        holdingList = seed.holdings
        summary = seed.summary
    }

    // MARK: Test and preview controls

    /// The next throwing call throws `error`, then the failure clears.
    func fail(next error: (any Error)?) {
        nextError = error
    }

    /// Replaces the bank connection, e.g. to preview the `login_required` state.
    func setBankConnection(_ connection: BankConnection?) {
        bank = connection
    }

    // MARK: Auth

    nonisolated func sessionStates() -> AsyncStream<SessionState> {
        let (stream, continuation) = AsyncStream<SessionState>.makeStream()
        let id = UUID()
        continuation.onTermination = { _ in
            Task { await self.removeObserver(id) }
        }
        Task { await self.addObserver(continuation, id: id) }
        return stream
    }

    func currentEmail() async -> String? {
        calls.append("currentEmail")
        return session == .signedOut ? nil : email
    }

    func signUp(email: String, password: String, name: String) async throws {
        try record("signUp")
        try validate(email: email, password: password)
        self.email = email
        profileValue.displayName = name
        bank = nil
        setSession(.signedIn(profileValue.id))
    }

    func signIn(email: String, password: String) async throws {
        try record("signIn")
        try validate(email: email, password: password)
        self.email = email
        setSession(.signedIn(profileValue.id))
    }

    func signOut() async throws {
        try record("signOut")
        email = nil
        setSession(.signedOut)
    }

    // MARK: Reads and profile

    func profile() async throws -> Profile {
        try record("profile")
        return profileValue
    }

    func updateProfile(_ patch: ProfilePatch) async throws -> Profile {
        try record("updateProfile")
        if let threshold = patch.thresholdCents, ![200, 500, 1000].contains(threshold) {
            throw UserFacingError(message: "Choose a $2, $5 or $10 threshold.", code: "BAD_REQUEST")
        }
        if let symbol = patch.targetAsset, !assetList.contains(where: { $0.symbol == symbol }) {
            throw UserFacingError(message: "\(symbol) isn't available.", code: "BAD_REQUEST")
        }
        if let displayName = patch.displayName { profileValue.displayName = displayName }
        if let threshold = patch.thresholdCents { profileValue.thresholdCents = threshold }
        if let symbol = patch.targetAsset { profileValue.targetAsset = symbol }
        if let paused = patch.roundupsPaused { profileValue.roundupsPaused = paused }
        summary = DropSummary(
            pendingCents: summary.pendingCents, thresholdCents: profileValue.thresholdCents,
            lifetimeRoundupCents: summary.lifetimeRoundupCents, investedCents: summary.investedCents
        )
        return profileValue
    }

    func assets() async throws -> [Asset] {
        try record("assets")
        return assetList.sorted { $0.sortOrder < $1.sortOrder }
    }

    func bankConnection() async throws -> BankConnection? {
        try record("bankConnection")
        return bank
    }

    func transactions(limit: Int) async throws -> [Transaction] {
        try record("transactions")
        let newestFirst = transactionList.sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
        return Array(newestFirst.prefix(max(0, limit)))
    }

    func dropSummary() async throws -> DropSummary {
        try record("dropSummary")
        return summary
    }

    func portfolio() async throws -> [Holding] {
        try record("portfolio")
        return holdingList.sorted { $0.investedCents > $1.investedCents }
    }

    // MARK: Edge Functions

    func createLinkToken() async throws -> String {
        try record("createLinkToken")
        return "link-sandbox-" + UUID().uuidString.lowercased()
    }

    func exchange(publicToken: String, institutionName: String?) async throws -> SyncResult {
        try record("exchange")
        bank = BankConnection(institutionName: institutionName, status: .active, lastSyncedAt: .now)
        return SyncResult(added: transactionList.count, modified: 0, removed: 0, investment: sweepIfReady())
    }

    func sync() async throws -> SyncResult {
        try record("sync")
        let linked = try requireBank()
        bank = BankConnection(institutionName: linked.institutionName, status: .active, lastSyncedAt: .now)
        return SyncResult(added: 0, modified: 0, removed: 0, investment: sweepIfReady())
    }

    func simulatePurchase(merchant: String, amountCents: Int) async throws -> SyncResult {
        try record("simulatePurchase")
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...60).contains(name.count), (1...100_000).contains(amountCents) else {
            throw UserFacingError(
                message: "Enter a merchant and an amount from $0.01 to $1,000.00.", code: "BAD_REQUEST"
            )
        }
        let linked = try requireBank()
        let now = Date.now
        let roundup = Money.roundupCents(forAmountCents: amountCents)
        transactionList.insert(
            Transaction(
                id: UUID(), merchantName: name, amountCents: amountCents, date: DropletDates.dayString(now),
                pending: false, roundupCents: roundup, roundupStatus: roundup > 0 ? .pending : .skipped, createdAt: now
            ),
            at: 0
        )
        summary = DropSummary(
            pendingCents: summary.pendingCents + roundup, thresholdCents: summary.thresholdCents,
            lifetimeRoundupCents: summary.lifetimeRoundupCents + roundup, investedCents: summary.investedCents
        )
        bank = BankConnection(institutionName: linked.institutionName, status: .active, lastSyncedAt: now)
        return SyncResult(added: 1, modified: 0, removed: 0, investment: sweepIfReady())
    }

    // MARK: Helpers

    private func record(_ name: String) throws {
        calls.append(name)
        if let error = nextError {
            nextError = nil
            throw error
        }
    }

    private func validate(email: String, password: String) throws {
        guard email.contains("@") else {
            throw UserFacingError(message: "Unable to validate email address: invalid format")
        }
        guard password.count >= 6 else {
            throw UserFacingError(message: "Password should be at least 6 characters.")
        }
    }

    private func requireBank() throws -> BankConnection {
        guard let bank else {
            throw UserFacingError(message: "Connect a bank first.", code: "NO_BANK")
        }
        if bank.status == .loginRequired {
            throw UserFacingError(message: "Reconnect your bank to keep rounding up.", code: "ITEM_LOGIN_REQUIRED")
        }
        return bank
    }

    private func addObserver(_ continuation: AsyncStream<SessionState>.Continuation, id: UUID) {
        calls.append("sessionStates")
        observers[id] = continuation
        continuation.yield(session)
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    private func setSession(_ state: SessionState) {
        session = state
        for continuation in observers.values {
            continuation.yield(state)
        }
    }

    /// Mirrors `sweep_drops`: invest every pending drop once the total reaches the threshold.
    private func sweepIfReady() -> Investment? {
        let amount = summary.pendingCents
        let symbol = profileValue.targetAsset
        guard !profileValue.roundupsPaused, amount > 0, amount >= profileValue.thresholdCents,
              let priceText = Self.prices[symbol],
              let price = Decimal(string: priceText, locale: Self.posix)
        else { return nil }

        let quantity = Self.rounded(Decimal(amount) / 100 / price, scale: 18)
        let investment = Investment(
            id: UUID(), assetSymbol: symbol, amountCents: amount, priceUsd: priceText,
            quantity: "\(quantity)", mode: "simulated", createdAt: .now
        )

        transactionList = transactionList.map { transaction in
            guard transaction.roundupStatus == .pending else { return transaction }
            return Transaction(
                id: transaction.id, merchantName: transaction.merchantName, amountCents: transaction.amountCents,
                date: transaction.date, pending: transaction.pending, roundupCents: transaction.roundupCents,
                roundupStatus: .invested, createdAt: transaction.createdAt
            )
        }

        if let index = holdingList.firstIndex(where: { $0.assetSymbol == symbol }) {
            let current = holdingList[index]
            let total = (Decimal(string: current.quantity, locale: Self.posix) ?? 0) + quantity
            holdingList[index] = Holding(
                assetSymbol: symbol, assetName: current.assetName, iconUrl: current.iconUrl,
                investedCents: current.investedCents + amount, quantity: "\(total)", lastInvestedAt: investment.createdAt
            )
        } else {
            let asset = assetList.first { $0.symbol == symbol }
            holdingList.append(Holding(
                assetSymbol: symbol, assetName: asset?.name ?? symbol, iconUrl: asset?.iconUrl,
                investedCents: amount, quantity: "\(quantity)", lastInvestedAt: investment.createdAt
            ))
        }
        holdingList.sort { $0.investedCents > $1.investedCents }

        summary = DropSummary(
            pendingCents: 0, thresholdCents: summary.thresholdCents,
            lifetimeRoundupCents: summary.lifetimeRoundupCents, investedCents: summary.investedCents + amount
        )
        return investment
    }

    private static func rounded(_ value: Decimal, scale: Int) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }
}
