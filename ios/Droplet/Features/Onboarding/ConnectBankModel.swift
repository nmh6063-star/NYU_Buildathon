import Foundation
import Observation

/// Plaid Link flow: fetch a link token, present Link, exchange the public token.
@MainActor @Observable final class ConnectBankModel {
    enum Phase: Equatable {
        case idle
        case fetchingToken
        case ready(linkToken: String)
        case exchanging
        case done
    }

    private(set) var phase: Phase = .idle
    var error: UserFacingError?

    private let api: any DropletAPI

    init(api: any DropletAPI) {
        self.api = api
    }

    func prepare() async {
        if phase == .fetchingToken || phase == .exchanging { return }
        error = nil
        phase = .fetchingToken
        do {
            phase = .ready(linkToken: try await api.createLinkToken())
        } catch {
            phase = .idle
            self.error = UserFacingError.from(error)
        }
    }

    func handleSuccess(publicToken: String, institutionName: String?) async {
        error = nil
        phase = .exchanging
        do {
            _ = try await api.exchange(publicToken: publicToken, institutionName: institutionName)
            phase = .done
        } catch {
            phase = .idle
            self.error = UserFacingError.from(error)
        }
    }

    /// Shown when Link exits with an error that has no usable text (Plaid sends "" when it is not user-actionable).
    static let linkFallbackMessage = "Couldn't connect your bank. Please try again."

    /// `errorMessage` is nil when Link closed without an error, so no banner shows.
    /// A blank message still means an error, so it shows `linkFallbackMessage` instead of an empty banner.
    func handleExit(errorMessage: String?) {
        phase = .idle
        guard let errorMessage else {
            error = nil
            return
        }
        let trimmed = errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        error = UserFacingError(message: trimmed.isEmpty ? Self.linkFallbackMessage : trimmed)
    }
}
