import Foundation
import Supabase

/// An error ready to show in an ErrorBanner.
struct UserFacingError: Error, Equatable, Identifiable, Sendable {
    let id: UUID
    let message: String
    /// The contract C1 error code (e.g. "ITEM_LOGIN_REQUIRED"), when the server sent one.
    let code: String?

    init(message: String, code: String? = nil) {
        self.id = UUID()
        self.message = message
        self.code = code
    }

    static let offlineMessage = "You're offline. Check your connection and try again."

    static func from(_ error: any Error) -> UserFacingError {
        if let error = error as? UserFacingError {
            return error
        }
        if let error = error as? FunctionsError {
            switch error {
            case let .httpError(status, data):
                if let envelope = try? JSONDecoder.droplet.decode(ErrorEnvelope.self, from: data) {
                    return UserFacingError(message: envelope.error.message, code: envelope.error.code)
                }
                return UserFacingError(message: "Something went wrong (HTTP \(status)). Please try again.")
            case .relayError:
                return UserFacingError(message: "Couldn't reach Droplet's servers. Please try again.")
            }
        }
        if let error = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(error.code) {
            return UserFacingError(message: offlineMessage)
        }
        return UserFacingError(message: error.localizedDescription)
    }
}

/// `{"error":{"code":"<CODE>","message":"<human text>"}}` (contract C1).
private struct ErrorEnvelope: Decodable {
    struct Body: Decodable {
        let code: String
        let message: String
    }

    let error: Body
}
