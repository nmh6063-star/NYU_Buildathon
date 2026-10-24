import Foundation
import Testing
@testable import Droplet

@MainActor
struct AuthModelTests {
    @Test func signUpNeedsNameEmailAndPassword() {
        let model = AuthModel(api: PreviewDropletAPI(signedIn: false))
        #expect(model.mode == .signUp)
        #expect(!model.canSubmit)
        model.email = "sam@example.com"
        model.password = "hunter22"
        #expect(!model.canSubmit)
        model.name = "   "
        #expect(!model.canSubmit)
        model.name = "Sam"
        #expect(model.canSubmit)
        model.password = "12345"
        #expect(!model.canSubmit)
    }

    @Test func signInDoesNotNeedName() {
        let model = AuthModel(api: PreviewDropletAPI(signedIn: false))
        model.mode = .signIn
        model.email = "sam@example.com"
        model.password = "hunter22"
        #expect(model.canSubmit)
        model.email = "sam.example.com"
        #expect(!model.canSubmit)
    }

    @Test func submitSignsUpWithTrimmedFields() async throws {
        let api = PreviewDropletAPI(signedIn: false, hasBank: false)
        let model = AuthModel(api: api)
        model.name = " Sam "
        model.email = " sam@example.com "
        model.password = "hunter22"
        await model.submit()
        #expect(model.error == nil)
        #expect(model.isSubmitting == false)
        #expect(await api.calls == ["signUp"])
        #expect(await api.currentEmail() == "sam@example.com")
        #expect(try await api.profile().displayName == "Sam")
    }

    @Test func submitSignsIn() async {
        let api = PreviewDropletAPI(signedIn: false)
        let model = AuthModel(api: api)
        model.mode = .signIn
        model.email = "alex@example.com"
        model.password = "hunter22"
        await model.submit()
        #expect(model.error == nil)
        #expect(await api.calls == ["signIn"])
        #expect(await api.currentEmail() == "alex@example.com")
    }

    @Test func failureSetsErrorAndKeepsTheForm() async {
        let api = PreviewDropletAPI(signedIn: false)
        await api.fail(next: UserFacingError(message: "Invalid login credentials"))
        let model = AuthModel(api: api)
        model.mode = .signIn
        model.email = "alex@example.com"
        model.password = "wrong-password"
        await model.submit()
        #expect(model.error?.message == "Invalid login credentials")
        #expect(model.isSubmitting == false)
        #expect(model.email == "alex@example.com")
        #expect(model.canSubmit)
    }

    @Test func submitDoesNothingWhenInvalid() async {
        let api = PreviewDropletAPI(signedIn: false)
        let model = AuthModel(api: api)
        await model.submit()
        #expect(await api.calls.isEmpty)
    }
}
