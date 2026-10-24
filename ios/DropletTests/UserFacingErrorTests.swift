import Foundation
import Supabase
import Testing
@testable import Droplet

struct UserFacingErrorTests {
    @Test func decodesEdgeFunctionErrorBody() {
        let body = Data(#"{"error":{"code":"ITEM_LOGIN_REQUIRED","message":"Reconnect your bank to keep rounding up."}}"#.utf8)
        let error = UserFacingError.from(FunctionsError.httpError(code: 409, data: body))
        #expect(error.code == "ITEM_LOGIN_REQUIRED")
        #expect(error.message == "Reconnect your bank to keep rounding up.")
    }

    @Test func decodesPlaidRateLimitAsFriendlyMessage() {
        let message = "Plaid Sandbox allows only a few test purchases per minute. Wait a moment and try again."
        let body = Data(#"{"error":{"code":"RATE_LIMITED","message":"\#(message)"}}"#.utf8)
        let error = UserFacingError.from(FunctionsError.httpError(code: 429, data: body))
        #expect(error.code == "RATE_LIMITED")
        #expect(error.message == message)
    }

    @Test func undecodableFunctionErrorFallsBackToStatus() {
        let error = UserFacingError.from(FunctionsError.httpError(code: 502, data: Data("Bad Gateway".utf8)))
        #expect(error.code == nil)
        #expect(error.message == "Something went wrong (HTTP 502). Please try again.")
    }

    @Test func relayErrorHasFriendlyMessage() {
        #expect(UserFacingError.from(FunctionsError.relayError).message == "Couldn't reach Droplet's servers. Please try again.")
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .networkConnectionLost, .timedOut])
    func networkLossReadsAsOffline(code: URLError.Code) {
        let error = UserFacingError.from(URLError(code))
        #expect(error.message == "You're offline. Check your connection and try again.")
        #expect(error.code == nil)
    }

    @Test func otherErrorsUseLocalizedDescription() {
        let postgrest = PostgrestError(code: "42501", message: "permission denied for table profiles")
        #expect(UserFacingError.from(postgrest).message == "permission denied for table profiles")
        let other = URLError(.badServerResponse)
        #expect(UserFacingError.from(other).message == other.localizedDescription)
    }

    @Test func passesUserFacingErrorsThrough() {
        let original = UserFacingError(message: "Connect a bank first.", code: "NO_BANK")
        #expect(UserFacingError.from(original) == original)
    }

    @Test func eachErrorHasItsOwnIdentity() {
        let first = UserFacingError(message: "Same text")
        let second = UserFacingError(message: "Same text")
        #expect(first.id != second.id)
        #expect(first != second)
    }
}
