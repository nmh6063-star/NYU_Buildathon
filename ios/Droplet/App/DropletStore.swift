import Foundation
import Observation

struct DaySection: Identifiable, Equatable, Sendable {
    let day: Date
    let items: [Transaction]

    var id: Date { day }
}

/// Shared data for the three tabs. Views read it; mutations go through its async methods.
@MainActor @Observable final class DropletStore {
    private(set) var profile: Profile?
    private(set) var email: String?
    private(set) var assets: [Asset] = []
    private(set) var bank: BankConnection?
    private(set) var summary: DropSummary = .empty
    private(set) var transactions: [Transaction] = []
    private(set) var holdings: [Holding] = []
    private(set) var isLoading = false
    private(set) var isSyncing = false
    private(set) var lastInvestment: Investment?
    var error: UserFacingError?

    private let api: any DropletAPI

    init(api: any DropletAPI) {
        self.api = api
    }

    var totalInvestedCents: Int {
        holdings.reduce(0) { $0 + $1.investedCents }
    }

    var targetAsset: Asset? {
        assets.first { $0.symbol == profile?.targetAsset }
    }

    /// Transactions grouped by calendar day, newest day first; rows keep newest-first order.
    var transactionsByDay: [DaySection] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: transactions) { calendar.startOfDay(for: $0.day) }
        return groups.keys.sorted(by: >).map { DaySection(day: $0, items: groups[$0] ?? []) }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await fetchAll()
            error = nil
        } catch {
            capture(error)
        }
    }

    func sync() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            let result = try await api.sync()
            if let investment = result.investment { lastInvestment = investment }
        } catch {
            capture(error)
            try? await fetchAll()
            return
        }
        await load()
    }

    /// Returns true when the purchase was recorded.
    func simulatePurchase(merchant: String, amountCents: Int) async -> Bool {
        isSyncing = true
        defer { isSyncing = false }
        do {
            let result = try await api.simulatePurchase(merchant: merchant, amountCents: amountCents)
            if let investment = result.investment { lastInvestment = investment }
        } catch {
            capture(error)
            return false
        }
        await load()
        return true
    }

    func setThreshold(_ cents: Int) async {
        let previousSummary = summary
        summary = DropSummary(
            pendingCents: summary.pendingCents, thresholdCents: cents,
            lifetimeRoundupCents: summary.lifetimeRoundupCents, investedCents: summary.investedCents
        )
        let saved = await saveProfile(ProfilePatch(thresholdCents: cents)) { $0.thresholdCents = cents }
        if !saved { summary = previousSummary }
    }

    func setTargetAsset(_ symbol: String) async {
        await saveProfile(ProfilePatch(targetAsset: symbol)) { $0.targetAsset = symbol }
    }

    func setPaused(_ paused: Bool) async {
        await saveProfile(ProfilePatch(roundupsPaused: paused)) { $0.roundupsPaused = paused }
    }

    /// Always clears local state, even when the server call fails, so no stale data outlives the session.
    func signOut() async {
        defer { reset() }
        do {
            try await api.signOut()
        } catch {
            // Ignored: the deferred reset() runs either way.
        }
    }

    // MARK: Private

    private func fetchAll() async throws {
        let api = self.api
        async let profileValue = api.profile()
        async let emailValue = api.currentEmail()
        async let assetList = api.assets()
        async let bankValue = api.bankConnection()
        async let summaryValue = api.dropSummary()
        async let transactionList = api.transactions(limit: 200)
        async let holdingList = api.portfolio()

        let loaded = try await (
            profileValue, emailValue, assetList, bankValue, summaryValue, transactionList, holdingList
        )
        profile = loaded.0
        email = loaded.1
        assets = loaded.2.sorted { $0.sortOrder < $1.sortOrder }
        bank = loaded.3
        summary = loaded.4
        transactions = loaded.5.sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
        holdings = loaded.6.sorted { $0.investedCents > $1.investedCents }
    }

    /// Applies `change` to the local profile immediately, then persists `patch`.
    /// Reverts and sets `error` on failure; refreshes the summary on success.
    @discardableResult
    private func saveProfile(_ patch: ProfilePatch, optimistic change: (inout Profile) -> Void) async -> Bool {
        let previous = profile
        if var draft = profile {
            change(&draft)
            profile = draft
        }
        do {
            profile = try await api.updateProfile(patch)
        } catch {
            profile = previous
            capture(error)
            return false
        }
        do {
            summary = try await api.dropSummary()
        } catch {
            capture(error)
        }
        return true
    }

    private func capture(_ error: any Error) {
        if error is CancellationError { return }
        if let urlError = error as? URLError, urlError.code == .cancelled { return }
        self.error = UserFacingError.from(error)
    }

    private func reset() {
        profile = nil
        email = nil
        assets = []
        bank = nil
        summary = .empty
        transactions = []
        holdings = []
        lastInvestment = nil
        error = nil
    }
}
