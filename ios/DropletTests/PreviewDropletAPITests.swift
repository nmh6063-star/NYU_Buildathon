import Foundation
import Testing
@testable import Droplet

struct PreviewDropletAPITests {
    private func seed(thresholdCents: Int = 500, paused: Bool = false) -> PreviewSeed {
        var seed = PreviewSeed.empty
        seed.profile.thresholdCents = thresholdCents
        seed.profile.roundupsPaused = paused
        seed.summary = DropSummary(pendingCents: 0, thresholdCents: thresholdCents, lifetimeRoundupCents: 0, investedCents: 0)
        return seed
    }

    @Test func demoSeedIsInternallyConsistent() {
        let demo = PreviewSeed.demo
        let pending = demo.transactions.filter { $0.roundupStatus == .pending }.reduce(0) { $0 + $1.roundupCents }
        let invested = demo.holdings.reduce(0) { $0 + $1.investedCents }
        #expect(demo.summary.pendingCents == 321)
        #expect(demo.summary.pendingCents == pending)
        #expect(demo.summary.investedCents == invested)
        #expect(demo.summary.lifetimeRoundupCents == pending + invested)
        #expect(demo.summary.thresholdCents == demo.profile.thresholdCents)
        #expect(demo.assets.map(\.symbol) == ["SOL", "ETH", "CBBTC", "AAVE", "JUP", "RENDER"])
        for transaction in demo.transactions where transaction.roundupStatus == .pending || transaction.roundupStatus == .invested {
            #expect(transaction.roundupCents == Money.roundupCents(forAmountCents: transaction.amountCents))
        }
    }

    @Test func readsReturnSeededData() async throws {
        let api = PreviewDropletAPI()
        #expect(try await api.profile() == PreviewSeed.demo.profile)
        #expect(try await api.dropSummary() == PreviewSeed.demo.summary)
        #expect(try await api.bankConnection()?.status == .active)
        #expect(await api.currentEmail() == "alex@example.com")
        #expect(try await api.transactions(limit: 3).count == 3)

        let all = try await api.transactions(limit: 200)
        #expect(all.count == PreviewSeed.demo.transactions.count)
        #expect(zip(all, all.dropFirst()).allSatisfy { ($0.date, $0.createdAt) >= ($1.date, $1.createdAt) })

        let holdings = try await api.portfolio()
        #expect(holdings.map(\.investedCents) == [1096, 527, 503])
    }

    @Test func purchaseBelowThresholdAddsPendingDrop() async throws {
        let api = PreviewDropletAPI(seed: seed())
        let result = try await api.simulatePurchase(merchant: "Blue Bottle", amountCents: 567)
        #expect(result.added == 1)
        #expect(result.investment == nil)

        let newest = try #require(try await api.transactions(limit: 1).first)
        #expect(newest.merchantName == "Blue Bottle")
        #expect(newest.amountCents == 567)
        #expect(newest.roundupCents == 33)
        #expect(newest.roundupStatus == .pending)
        #expect(newest.date == DropletDates.dayString(.now))

        let summary = try await api.dropSummary()
        #expect(summary.pendingCents == 33)
        #expect(summary.lifetimeRoundupCents == 33)
        #expect(summary.investedCents == 0)
    }

    @Test func wholeDollarPurchaseIsSkipped() async throws {
        let api = PreviewDropletAPI(seed: seed())
        _ = try await api.simulatePurchase(merchant: "Shell", amountCents: 4000)
        let newest = try #require(try await api.transactions(limit: 1).first)
        #expect(newest.roundupCents == 0)
        #expect(newest.roundupStatus == .skipped)
        #expect(try await api.dropSummary().pendingCents == 0)
    }

    @Test func crossingThresholdSweepsEveryPendingDrop() async throws {
        let api = PreviewDropletAPI(seed: seed(thresholdCents: 200))
        _ = try await api.simulatePurchase(merchant: "Corner Store", amountCents: 101)
        let second = try await api.simulatePurchase(merchant: "Corner Store", amountCents: 101)
        #expect(second.investment == nil)
        let result = try await api.simulatePurchase(merchant: "Blue Bottle", amountCents: 567)

        let investment = try #require(result.investment)
        #expect(investment.assetSymbol == "SOL")
        #expect(investment.amountCents == 231)
        #expect(investment.mode == "simulated")
        #expect(investment.priceUsd == "182.44")
        let quantity = try #require(Decimal(string: investment.quantity))
        let price = try #require(Decimal(string: investment.priceUsd))
        #expect(abs(NSDecimalNumber(decimal: quantity * price).doubleValue - 2.31) < 0.000_001)

        let summary = try await api.dropSummary()
        #expect(summary.pendingCents == 0)
        #expect(summary.investedCents == 231)
        #expect(summary.lifetimeRoundupCents == 231)
        #expect(try await api.transactions(limit: 10).allSatisfy { $0.roundupStatus == .invested })

        let holdings = try await api.portfolio()
        #expect(holdings.count == 1)
        #expect(holdings.first?.assetSymbol == "SOL")
        #expect(holdings.first?.assetName == "Solana")
        #expect(holdings.first?.investedCents == 231)
        #expect(holdings.first?.quantity == investment.quantity)
    }

    @Test func sweepAddsToAnExistingHolding() async throws {
        let api = PreviewDropletAPI()
        let first = try await api.simulatePurchase(merchant: "Sweetgreen", amountCents: 1001)
        #expect(first.investment == nil)
        let second = try await api.simulatePurchase(merchant: "Uber", amountCents: 2318)
        let investment = try #require(second.investment)
        #expect(investment.amountCents == 321 + 99 + 82)
        let sol = try #require(try await api.portfolio().first { $0.assetSymbol == "SOL" })
        #expect(sol.investedCents == 1096 + 502)
    }

    @Test func pausedRoundupsAccumulateUntilResumed() async throws {
        let api = PreviewDropletAPI(seed: seed(thresholdCents: 200, paused: true))
        for _ in 0..<3 {
            let result = try await api.simulatePurchase(merchant: "Corner Store", amountCents: 101)
            #expect(result.investment == nil)
        }
        #expect(try await api.dropSummary().pendingCents == 297)

        _ = try await api.updateProfile(ProfilePatch(roundupsPaused: false))
        let synced = try await api.sync()
        #expect(synced.investment?.amountCents == 297)
    }

    @Test func updateProfileAppliesOnlySetFields() async throws {
        let api = PreviewDropletAPI()
        let updated = try await api.updateProfile(ProfilePatch(thresholdCents: 1000, targetAsset: "ETH"))
        #expect(updated.thresholdCents == 1000)
        #expect(updated.targetAsset == "ETH")
        #expect(updated.displayName == PreviewSeed.demo.profile.displayName)
        #expect(updated.roundupsPaused == false)
        #expect(try await api.dropSummary().thresholdCents == 1000)
        await #expect(throws: UserFacingError.self) { try await api.updateProfile(ProfilePatch(thresholdCents: 300)) }
        await #expect(throws: UserFacingError.self) { try await api.updateProfile(ProfilePatch(targetAsset: "DOGE")) }
    }

    @Test func failNextThrowsOnceThenClears() async throws {
        let api = PreviewDropletAPI()
        await api.fail(next: URLError(.notConnectedToInternet))
        await #expect(throws: URLError.self) { try await api.profile() }
        #expect(try await api.profile() == PreviewSeed.demo.profile)
    }

    @Test func recordsCallsInOrder() async throws {
        let api = PreviewDropletAPI()
        _ = try await api.profile()
        _ = try await api.assets()
        _ = try await api.sync()
        #expect(await api.calls == ["profile", "assets", "sync"])
    }

    @Test func sessionStatesYieldCurrentStateThenChanges() async throws {
        let api = PreviewDropletAPI(signedIn: false, hasBank: false)
        var states = api.sessionStates().makeAsyncIterator()
        #expect(await states.next() == .signedOut)

        try await api.signUp(email: "sam@example.com", password: "hunter22", name: "Sam")
        #expect(await states.next() == .signedIn(PreviewSeed.userID))
        #expect(await api.currentEmail() == "sam@example.com")
        #expect(try await api.profile().displayName == "Sam")
        #expect(try await api.bankConnection() == nil)

        try await api.signOut()
        #expect(await states.next() == .signedOut)
        #expect(await api.currentEmail() == nil)
    }

    @Test func rejectsWeakCredentials() async {
        let api = PreviewDropletAPI(signedIn: false)
        await #expect(throws: UserFacingError.self) { try await api.signIn(email: "sam@example.com", password: "123") }
        await #expect(throws: UserFacingError.self) { try await api.signUp(email: "not-an-email", password: "hunter22", name: "Sam") }
    }

    @Test func syncWithoutBankThrowsNoBank() async {
        let api = PreviewDropletAPI(hasBank: false)
        await #expect(throws: UserFacingError.self) { try await api.sync() }
        do {
            _ = try await api.sync()
        } catch {
            #expect(UserFacingError.from(error).code == "NO_BANK")
        }
    }

    @Test func loginRequiredBankBlocksSync() async {
        let api = PreviewDropletAPI()
        await api.setBankConnection(BankConnection(institutionName: "First Platypus Bank", status: .loginRequired, lastSyncedAt: nil))
        do {
            _ = try await api.sync()
            Issue.record("sync should fail while the bank needs re-linking")
        } catch {
            #expect(UserFacingError.from(error).code == "ITEM_LOGIN_REQUIRED")
        }
    }

    @Test func exchangeLinksTheBank() async throws {
        let api = PreviewDropletAPI(hasBank: false)
        #expect(try await api.createLinkToken().hasPrefix("link-sandbox-"))
        _ = try await api.exchange(publicToken: "public-sandbox-123", institutionName: "First Platypus Bank")
        let bank = try #require(try await api.bankConnection())
        #expect(bank.institutionName == "First Platypus Bank")
        #expect(bank.status == .active)
        #expect(bank.lastSyncedAt != nil)
    }

    @Test func rejectsInvalidPurchases() async {
        let api = PreviewDropletAPI()
        await #expect(throws: UserFacingError.self) { try await api.simulatePurchase(merchant: " ", amountCents: 500) }
        await #expect(throws: UserFacingError.self) { try await api.simulatePurchase(merchant: "Blue Bottle", amountCents: 0) }
        await #expect(throws: UserFacingError.self) { try await api.simulatePurchase(merchant: "Blue Bottle", amountCents: 100_001) }
    }
}
