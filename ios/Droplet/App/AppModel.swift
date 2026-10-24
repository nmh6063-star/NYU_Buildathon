import Foundation
import Observation

/// Top-level routing: launching -> auth -> connectBank -> main, driven by the auth session.
@MainActor @Observable final class AppModel {
    enum Route: Equatable {
        case launching, auth, connectBank, main
    }

    private(set) var route: Route = .launching
    let api: any DropletAPI

    init(api: any DropletAPI) {
        self.api = api
    }

    /// Runs for the app's lifetime (call from `.task`). Re-routes on every session change.
    func start() async {
        var last: SessionState?
        for await state in api.sessionStates() {
            guard state != last else { continue }
            last = state
            switch state {
            case .signedOut:
                route = .auth
            case .signedIn:
                route = await routeForSignedInUser()
            }
        }
    }

    /// Called by the onboarding flow once Plaid Link and the exchange succeed.
    func bankLinked() {
        route = .main
    }

    private func routeForSignedInUser() async -> Route {
        do {
            return try await api.bankConnection() == nil ? .connectBank : .main
        } catch {
            // Offline or a transient failure: show the tabs; DropletStore surfaces the error.
            return .main
        }
    }
}
