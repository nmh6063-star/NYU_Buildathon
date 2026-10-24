import Foundation
import Testing
@testable import Droplet

@MainActor
struct ConnectBankModelTests {
    @Test func prepareFetchesALinkToken() async {
        let model = ConnectBankModel(api: PreviewDropletAPI(hasBank: false))
        #expect(model.phase == .idle)
        await model.prepare()
        guard case let .ready(token) = model.phase else {
            Issue.record("expected .ready, got \(model.phase)")
            return
        }
        #expect(token.hasPrefix("link-sandbox-"))
        #expect(model.error == nil)
    }

    @Test func prepareFailureReturnsToIdleWithError() async {
        let api = PreviewDropletAPI(hasBank: false)
        await api.fail(next: URLError(.notConnectedToInternet))
        let model = ConnectBankModel(api: api)
        await model.prepare()
        #expect(model.phase == .idle)
        #expect(model.error?.message == UserFacingError.offlineMessage)
    }

    @Test func successExchangesAndFinishes() async throws {
        let api = PreviewDropletAPI(hasBank: false)
        let model = ConnectBankModel(api: api)
        await model.prepare()
        await model.handleSuccess(publicToken: "public-sandbox-123", institutionName: "First Platypus Bank")
        #expect(model.phase == .done)
        #expect(model.error == nil)
        #expect(try await api.bankConnection()?.institutionName == "First Platypus Bank")
    }

    @Test func exchangeFailureReturnsToIdle() async {
        let api = PreviewDropletAPI(hasBank: false)
        let model = ConnectBankModel(api: api)
        await api.fail(next: UserFacingError(message: "Plaid is unavailable right now.", code: "PLAID_ERROR"))
        await model.handleSuccess(publicToken: "public-sandbox-123", institutionName: nil)
        #expect(model.phase == .idle)
        #expect(model.error?.code == "PLAID_ERROR")
    }

    @Test func exitShowsLinkErrorMessage() {
        let model = ConnectBankModel(api: PreviewDropletAPI(hasBank: false))
        model.handleExit(errorMessage: "The institution is down.")
        #expect(model.phase == .idle)
        #expect(model.error?.message == "The institution is down.")
        model.handleExit(errorMessage: nil)
        #expect(model.error == nil)
    }
}
