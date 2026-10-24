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

    func handleExit(errorMessage: String?) {
        phase = .idle
        error = errorMessage.map { UserFacingError(message: $0) }
    }
}
