import Foundation
import Testing
@testable import Droplet

/// Polls `condition` on the main actor until it holds or `timeout` passes.
@MainActor
private func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

@MainActor
struct AppModelTests {
    @Test func startsLaunching() {
        #expect(AppModel(api: PreviewDropletAPI()).route == .launching)
    }

    @Test func signedOutRoutesToAuth() async {
        let model = AppModel(api: PreviewDropletAPI(signedIn: false))
        let task = Task { await model.start() }
        defer { task.cancel() }
        #expect(await eventually { model.route == .auth })
    }

    @Test func signedInWithBankRoutesToMain() async {
        let model = AppModel(api: PreviewDropletAPI(signedIn: true, hasBank: true))
        let task = Task { await model.start() }
        defer { task.cancel() }
        #expect(await eventually { model.route == .main })
    }

    @Test func signedInWithoutBankRoutesToConnectBank() async {
        let model = AppModel(api: PreviewDropletAPI(signedIn: true, hasBank: false))
        let task = Task { await model.start() }
        defer { task.cancel() }
        #expect(await eventually { model.route == .connectBank })
    }

    @Test func signUpLinkBankThenSignOut() async throws {
        let api = PreviewDropletAPI(signedIn: false)
        let model = AppModel(api: api)
        let task = Task { await model.start() }
        defer { task.cancel() }
        #expect(await eventually { model.route == .auth })

        try await api.signUp(email: "sam@example.com", password: "hunter22", name: "Sam")
        #expect(await eventually { model.route == .connectBank })

        model.bankLinked()
        #expect(model.route == .main)

        try await api.signOut()
        #expect(await eventually { model.route == .auth })
    }

    @Test func signInWithExistingBankRoutesToMain() async throws {
        let api = PreviewDropletAPI(signedIn: false, hasBank: true)
        let model = AppModel(api: api)
        let task = Task { await model.start() }
        defer { task.cancel() }
        #expect(await eventually { model.route == .auth })

        try await api.signIn(email: "alex@example.com", password: "hunter22")
        #expect(await eventually { model.route == .main })
    }

    @Test func bankLookupFailureFallsBackToMain() async {
        let api = PreviewDropletAPI(signedIn: true, hasBank: false)
        await api.fail(next: URLError(.notConnectedToInternet))
        let model = AppModel(api: api)
        let task = Task { await model.start() }
        defer { task.cancel() }
        #expect(await eventually { model.route == .main })
    }
}
