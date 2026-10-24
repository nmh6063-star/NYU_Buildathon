import Foundation
import Testing
@testable import Droplet

@MainActor
struct DropletStoreTests {
    private func transaction(_ merchant: String, _ cents: Int, date: String, hour: Int) -> Transaction {
        let midnight = DropletDates.localMidnight(fromDay: date)!
        let roundup = Money.roundupCents(forAmountCents: cents)
        return Transaction(
            id: UUID(), merchantName: merchant, amountCents: cents, date: date, pending: false,
            roundupCents: roundup, roundupStatus: roundup > 0 ? .pending : .skipped,
            createdAt: midnight.addingTimeInterval(TimeInterval(hour * 3600))
        )
    }

    @Test func loadPopulatesEverything() async {
        let store = DropletStore(api: PreviewDropletAPI())
        await store.load()
        #expect(store.profile == PreviewSeed.demo.profile)
        #expect(store.email == "alex@example.com")
        #expect(store.assets.map(\.symbol) == ["SOL", "ETH", "CBBTC", "AAVE", "JUP", "RENDER"])
        #expect(store.bank?.institutionName == "First Platypus Bank")
        #expect(store.summary == PreviewSeed.demo.summary)
        #expect(store.transactions.count == PreviewSeed.demo.transactions.count)
        #expect(zip(store.transactions, store.transactions.dropFirst()).allSatisfy {
            ($0.date, $0.createdAt) >= ($1.date, $1.createdAt)
        })
        #expect(store.holdings.map(\.assetSymbol) == ["SOL", "ETH", "CBBTC"])
        #expect(store.totalInvestedCents == 1096 + 527 + 503)
        #expect(store.targetAsset?.symbol == "SOL")
        #expect(store.isLoading == false)
        #expect(store.error == nil)
    }

    @Test func loadFetchesEveryResource() async {
        let api = PreviewDropletAPI()
        let store = DropletStore(api: api)
        await store.load()
        let calls = Set(await api.calls)
        #expect(calls == ["profile", "currentEmail", "assets", "bankConnection", "dropSummary", "transactions", "portfolio"])
    }

    @Test func loadFailureKeepsDataAndMapsError() async {
        let api = PreviewDropletAPI()
        let store = DropletStore(api: api)
        await store.load()
        await api.fail(next: URLError(.notConnectedToInternet))
        await store.load()
        #expect(store.error?.message == UserFacingError.offlineMessage)
        #expect(store.profile == PreviewSeed.demo.profile)
        #expect(store.transactions.count == PreviewSeed.demo.transactions.count)

        await store.load()
        #expect(store.error == nil)
    }

    @Test func cancellationIsNotShownAsAnError() async {
        let api = PreviewDropletAPI()
        await api.fail(next: CancellationError())
        let store = DropletStore(api: api)
        await store.load()
        #expect(store.error == nil)
    }

    @Test func groupsTransactionsByDayNewestFirst() async {
        var seed = PreviewSeed.empty
        seed.transactions = [
            transaction("Blue Bottle", 567, date: "2026-10-24", hour: 9),
            transaction("Sweetgreen", 1342, date: "2026-10-23", hour: 12),
            transaction("Uber", 2318, date: "2026-10-24", hour: 18),
            transaction("Shell", 4000, date: "2026-10-22", hour: 7),
        ]
        let store = DropletStore(api: PreviewDropletAPI(seed: seed))
        await store.load()

        let sections = store.transactionsByDay
        #expect(sections.map { DropletDates.dayString($0.day) } == ["2026-10-24", "2026-10-23", "2026-10-22"])
        #expect(sections[0].items.map(\.merchantName) == ["Uber", "Blue Bottle"])
        #expect(sections[1].items.map(\.merchantName) == ["Sweetgreen"])
        #expect(sections.allSatisfy { $0.id == $0.day && $0.day == Calendar.current.startOfDay(for: $0.day) })
    }

    @Test func setThresholdUpdatesProfileAndSummary() async throws {
        let api = PreviewDropletAPI()
        let store = DropletStore(api: api)
        await store.load()
        await store.setThreshold(1000)
        #expect(store.profile?.thresholdCents == 1000)
        #expect(store.summary.thresholdCents == 1000)
        #expect(store.error == nil)
        #expect(Array(await api.calls.suffix(2)) == ["updateProfile", "dropSummary"])
        #expect(try await api.profile().thresholdCents == 1000)
    }

    @Test func failedThresholdChangeReverts() async {
        let api = PreviewDropletAPI()
        let store = DropletStore(api: api)
        await store.load()
        await api.fail(next: URLError(.timedOut))
        await store.setThreshold(200)
        #expect(store.profile?.thresholdCents == 500)
        #expect(store.summary.thresholdCents == 500)
        #expect(store.error?.message == UserFacingError.offlineMessage)
    }

    @Test func setTargetAssetAndPause() async throws {
        let api = PreviewDropletAPI()
        let store = DropletStore(api: api)
        await store.load()
        await store.setTargetAsset("ETH")
        #expect(store.profile?.targetAsset == "ETH")
        #expect(store.targetAsset?.name == "Ethereum")
        await store.setPaused(true)
        #expect(store.profile?.roundupsPaused == true)
        #expect(try await api.profile().roundupsPaused)
        #expect(try await api.profile().targetAsset == "ETH")
    }

    @Test func simulatePurchaseRecordsTheDrop() async {
        let store = DropletStore(api: PreviewDropletAPI())
        await store.load()
        let recorded = await store.simulatePurchase(merchant: "Blue Bottle", amountCents: 567)
        #expect(recorded)
        #expect(store.isSyncing == false)
        #expect(store.transactions.first?.merchantName == "Blue Bottle")
        #expect(store.transactions.first?.roundupCents == 33)
        #expect(store.summary.pendingCents == 321 + 33)
        #expect(store.lastInvestment == nil)
    }

    @Test func purchaseCrossingThresholdSetsLastInvestment() async throws {
        let store = DropletStore(api: PreviewDropletAPI())
        await store.load()
        let first = await store.simulatePurchase(merchant: "Uber", amountCents: 2318)
        #expect(first)
        #expect(store.lastInvestment == nil)

        let second = await store.simulatePurchase(merchant: "Sweetgreen", amountCents: 1001)
        #expect(second)
        let investment = try #require(store.lastInvestment)
        #expect(investment.amountCents == 321 + 82 + 99)
        #expect(investment.assetSymbol == "SOL")
        #expect(store.summary.pendingCents == 0)
        #expect(store.totalInvestedCents == 1096 + 527 + 503 + 502)
    }

    @Test func failedPurchaseReturnsFalse() async {
        let store = DropletStore(api: PreviewDropletAPI())
        await store.load()
        let recorded = await store.simulatePurchase(merchant: "", amountCents: 500)
        #expect(!recorded)
        #expect(store.error?.code == "BAD_REQUEST")
        #expect(store.isSyncing == false)
    }

    @Test func syncSweepsAfterLoweringThreshold() async {
        let store = DropletStore(api: PreviewDropletAPI())
        await store.load()
        await store.setThreshold(200)
        await store.sync()
        #expect(store.lastInvestment?.amountCents == 321)
        #expect(store.summary.pendingCents == 0)
        #expect(store.holdings.first { $0.assetSymbol == "SOL" }?.investedCents == 1096 + 321)
        #expect(store.isSyncing == false)
        #expect(store.error == nil)
    }

    @Test func syncFailureSurfacesCodeAndRefreshesBank() async {
        let api = PreviewDropletAPI()
        let store = DropletStore(api: api)
        await store.load()
        await api.setBankConnection(BankConnection(institutionName: "First Platypus Bank", status: .loginRequired, lastSyncedAt: nil))
        await store.sync()
        #expect(store.error?.code == "ITEM_LOGIN_REQUIRED")
        #expect(store.bank?.status == .loginRequired)
        #expect(store.isSyncing == false)
    }

    @Test func signOutClearsState() async {
        let api = PreviewDropletAPI()
        let store = DropletStore(api: api)
        await store.load()
        await store.signOut()
        #expect(store.profile == nil)
        #expect(store.email == nil)
        #expect(store.transactions.isEmpty)
        #expect(store.holdings.isEmpty)
        #expect(store.summary == .empty)
        #expect(await api.currentEmail() == nil)
    }

    @Test func signOutClearsStateEvenWhenTheServerCallFails() async {
        let api = PreviewDropletAPI()
        let store = DropletStore(api: api)
        await store.load()
        await api.fail(next: URLError(.notConnectedToInternet))
        await store.signOut()
        #expect(await api.calls.last == "signOut")
        #expect(store.profile == nil)
        #expect(store.email == nil)
        #expect(store.bank == nil)
        #expect(store.transactions.isEmpty)
        #expect(store.holdings.isEmpty)
        #expect(store.summary == .empty)
        #expect(store.error == nil)
    }
}
