import Foundation
import Testing
@testable import Droplet

struct CodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.droplet.decode(T.self, from: Data(json.utf8))
    }

    private func encode(_ value: some Encodable) throws -> String {
        String(decoding: try JSONEncoder.droplet.encode(value), as: UTF8.self)
    }

    private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        ))!
    }

    @Test func decodesAssets() throws {
        let assets = try decode([Asset].self, """
        [{"symbol":"SOL","name":"Solana","chain":"solana","tm_asset_id":"495e07ac-fa3e-4179-85b7-b1e8cece3dc4",
          "icon_url":"https://coin-images.coingecko.com/coins/images/4128/large/solana.png?1718769756",
          "sort_order":1,"enabled":true},
         {"symbol":"ETH","name":"Ethereum","chain":"base","tm_asset_id":"28e9d809-26ec-4269-ba55-b1cd1e052cd8",
          "icon_url":null,"sort_order":2,"enabled":true}]
        """)
        #expect(assets.count == 2)
        #expect(assets[0].id == "SOL")
        #expect(assets[0].name == "Solana")
        #expect(assets[0].chain == "solana")
        #expect(assets[0].sortOrder == 1)
        #expect(assets[0].iconUrl?.host() == "coin-images.coingecko.com")
        #expect(assets[1].iconUrl == nil)
    }

    @Test func decodesProfile() throws {
        let profile = try decode(Profile.self, """
        {"id":"6f1c3a52-9d4b-4e8a-b7c1-2d5e8f9a0b13","display_name":"Alex","threshold_cents":500,
         "target_asset":"SOL","roundups_paused":false,"created_at":"2026-10-24T16:03:11.482123+00:00"}
        """)
        #expect(profile == Profile(
            id: UUID(uuidString: "6F1C3A52-9D4B-4E8A-B7C1-2D5E8F9A0B13")!,
            displayName: "Alex", thresholdCents: 500, targetAsset: "SOL", roundupsPaused: false
        ))
    }

    @Test func decodesBankConnections() throws {
        let linked = try decode(BankConnection.self, """
        {"user_id":"6f1c3a52-9d4b-4e8a-b7c1-2d5e8f9a0b13","institution_name":"First Platypus Bank",
         "status":"login_required","last_synced_at":"2026-10-24T16:03:11.482123+00:00"}
        """)
        #expect(linked.institutionName == "First Platypus Bank")
        #expect(linked.status == .loginRequired)
        let syncedAt = try #require(linked.lastSyncedAt)
        #expect(abs(syncedAt.timeIntervalSince(utc(2026, 10, 24, 16, 3, 11)) - 0.482123) < 0.000_01)

        let fresh = try decode(BankConnection.self, """
        {"user_id":"6f1c3a52-9d4b-4e8a-b7c1-2d5e8f9a0b13","institution_name":null,"status":"active","last_synced_at":null}
        """)
        #expect(fresh == BankConnection(institutionName: nil, status: .active, lastSyncedAt: nil))
    }

    @Test func decodesTransactions() throws {
        let transactions = try decode([Transaction].self, """
        [{"id":"0b6f7f0e-3c1d-4a51-9a39-5a4f3b2f9d10","merchant_name":"Blue Bottle","amount_cents":567,
          "date":"2026-10-24","pending":false,"roundup_cents":33,"roundup_status":"pending",
          "created_at":"2026-10-24T16:03:11.482123+00:00"},
         {"id":"8d1d4c55-0f0e-4b7e-8a53-2b0cf4a9e7a1","merchant_name":"Shell","amount_cents":4000,
          "date":"2026-10-23","pending":true,"roundup_cents":0,"roundup_status":"skipped",
          "created_at":"2026-10-23T09:00:00Z"}]
        """)
        #expect(transactions.count == 2)
        #expect(transactions[0].merchantName == "Blue Bottle")
        #expect(transactions[0].amountCents == 567)
        #expect(transactions[0].date == "2026-10-24")
        #expect(transactions[0].roundupCents == 33)
        #expect(transactions[0].roundupStatus == .pending)
        #expect(transactions[1].pending)
        #expect(transactions[1].roundupStatus == .skipped)
        #expect(transactions[1].createdAt == utc(2026, 10, 23, 9, 0, 0))

        let day = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: transactions[0].day)
        #expect(day.year == 2026)
        #expect(day.month == 10)
        #expect(day.day == 24)
        #expect(day.hour == 0)
        #expect(day.minute == 0)
    }

    @Test(arguments: ["pending", "invested", "skipped", "reversed"])
    func decodesEveryRoundupStatus(raw: String) throws {
        #expect(try decode(RoundupStatus.self, "\"\(raw)\"").rawValue == raw)
    }

    @Test func transactionDayFallsBackToCreatedAt() {
        let createdAt = utc(2026, 10, 24, 16, 3, 11)
        let transaction = Transaction(
            id: UUID(), merchantName: "Corner Store", amountCents: 100, date: "garbage",
            pending: false, roundupCents: 0, roundupStatus: .skipped, createdAt: createdAt
        )
        #expect(transaction.day == createdAt)
    }

    @Test func decodesDropSummary() throws {
        let summary = try decode(DropSummary.self, """
        {"user_id":"6f1c3a52-9d4b-4e8a-b7c1-2d5e8f9a0b13","pending_cents":321,"threshold_cents":500,
         "lifetime_roundup_cents":1849,"invested_cents":1528}
        """)
        #expect(summary == DropSummary(pendingCents: 321, thresholdCents: 500, lifetimeRoundupCents: 1849, investedCents: 1528))
        #expect(summary.remainingCents == 179)
        #expect(abs(summary.progress - 0.642) < 0.000_1)
    }

    @Test func summaryMathClampsAndNeverDividesByZero() {
        let over = DropSummary(pendingCents: 731, thresholdCents: 500, lifetimeRoundupCents: 731, investedCents: 0)
        #expect(over.progress == 1)
        #expect(over.remainingCents == 0)
        let zero = DropSummary(pendingCents: 0, thresholdCents: 0, lifetimeRoundupCents: 0, investedCents: 0)
        #expect(zero.progress == 0)
        #expect(DropSummary.empty == DropSummary(pendingCents: 0, thresholdCents: 500, lifetimeRoundupCents: 0, investedCents: 0))
    }

    @Test func decodesPortfolioRows() throws {
        let holdings = try decode([Holding].self, """
        [{"user_id":"6f1c3a52-9d4b-4e8a-b7c1-2d5e8f9a0b13","asset_symbol":"SOL","asset_name":"Solana",
          "icon_url":"https://coin-images.coingecko.com/coins/images/4128/large/solana.png?1718769756",
          "invested_cents":1056,"quantity":"0.106274","last_invested_at":"2026-10-24T16:03:11Z"}]
        """)
        #expect(holdings.count == 1)
        #expect(holdings[0].id == "SOL")
        #expect(holdings[0].assetName == "Solana")
        #expect(holdings[0].investedCents == 1056)
        #expect(holdings[0].quantity == "0.106274")
        #expect(holdings[0].lastInvestedAt == utc(2026, 10, 24, 16, 3, 11))
    }

    @Test func decodesSyncResultWithInvestment() throws {
        let result = try decode(SyncResult.self, """
        {"added":2,"modified":0,"removed":0,
         "investment":{"id":"6f1c3a52-9d4b-4e8a-b7c1-2d5e8f9a0b13","asset_symbol":"SOL","amount_cents":528,
           "price_usd":"99.366035688829","quantity":"0.053137000000000000","mode":"simulated",
           "created_at":"2026-10-24T16:03:11.482Z"}}
        """)
        #expect(result.added == 2)
        #expect(result.modified == 0)
        #expect(result.removed == 0)
        let investment = try #require(result.investment)
        #expect(investment.id == UUID(uuidString: "6F1C3A52-9D4B-4E8A-B7C1-2D5E8F9A0B13"))
        #expect(investment.assetSymbol == "SOL")
        #expect(investment.amountCents == 528)
        #expect(investment.priceUsd == "99.366035688829")
        #expect(investment.quantity == "0.053137000000000000")
        #expect(investment.mode == "simulated")
        #expect(abs(investment.createdAt.timeIntervalSince(utc(2026, 10, 24, 16, 3, 11)) - 0.482) < 0.001)
    }

    @Test func decodesSyncResultWithoutInvestment() throws {
        let result = try decode(SyncResult.self, #"{"added":0,"modified":1,"removed":1,"investment":null}"#)
        #expect(result == SyncResult(added: 0, modified: 1, removed: 1, investment: nil))
    }

    @Test func decodesLinkTokenResponse() throws {
        let response = try decode(LinkTokenResponse.self, #"{"link_token":"link-sandbox-af1a0311","expiration":"2026-10-24T20:00:00Z"}"#)
        #expect(response.linkToken == "link-sandbox-af1a0311")
        #expect(response.expiration == "2026-10-24T20:00:00Z")
    }

    @Test func decodesPostgresDateAsLocalMidnight() throws {
        struct Probe: Decodable { let on: Date }
        let probe = try decode(Probe.self, #"{"on":"2026-10-24"}"#)
        #expect(probe.on == Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 24)))
    }

    @Test func rejectsUnknownDateFormats() {
        struct Probe: Decodable { let on: Date }
        #expect(throws: DecodingError.self) {
            try JSONDecoder.droplet.decode(Probe.self, from: Data(#"{"on":"24/10/2026"}"#.utf8))
        }
    }

    @Test func profilePatchEncodesOnlySetFieldsInSnakeCase() throws {
        #expect(try encode(ProfilePatch(thresholdCents: 1000)) == #"{"threshold_cents":1000}"#)
        #expect(try encode(ProfilePatch(targetAsset: "ETH")) == #"{"target_asset":"ETH"}"#)
        #expect(try encode(ProfilePatch(displayName: "Sam", roundupsPaused: true))
            == #"{"display_name":"Sam","roundups_paused":true}"#)
        #expect(try encode(ProfilePatch()) == "{}")
    }

    @Test func functionBodiesMatchContract() throws {
        #expect(try encode(EmptyBody()) == "{}")
        #expect(try encode(ExchangeBody(publicToken: "public-sandbox-123", institutionName: "First Platypus Bank"))
            == #"{"institution_name":"First Platypus Bank","public_token":"public-sandbox-123"}"#)
        #expect(try encode(ExchangeBody(publicToken: "public-sandbox-123", institutionName: nil))
            == #"{"institution_name":null,"public_token":"public-sandbox-123"}"#)
        #expect(try encode(SimulatePurchaseBody(merchant: "Blue Bottle", amountCents: 567))
            == #"{"amount_cents":567,"merchant":"Blue Bottle"}"#)
    }
}
