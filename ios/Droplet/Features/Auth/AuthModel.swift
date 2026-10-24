import Foundation
import Observation

/// Sign-in / sign-up form state. On success AppModel re-routes via `sessionStates()`.
@MainActor @Observable final class AuthModel {
    enum Mode: Equatable {
        case signIn, signUp
    }

    var mode: Mode = .signUp
    var name = ""
    var email = ""
    var password = ""
    private(set) var isSubmitting = false
    var error: UserFacingError?

    private let api: any DropletAPI

    init(api: any DropletAPI) {
        self.api = api
    }

    var canSubmit: Bool {
        email.contains("@")
            && password.count >= 6
            && (mode == .signIn || !name.trimmingCharacters(in: .whitespaces).isEmpty)
            && !isSubmitting
    }

    func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch mode {
            case .signUp:
                try await api.signUp(
                    email: email, password: password, name: name.trimmingCharacters(in: .whitespaces)
                )
            case .signIn:
                try await api.signIn(email: email, password: password)
            }
        } catch {
            self.error = UserFacingError.from(error)
        }
    }
}
