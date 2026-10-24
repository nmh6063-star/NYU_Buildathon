import Foundation
import Testing
@testable import Droplet

struct AppConfigTests {
    @Test func readsValuesFromInfoDictionary() throws {
        let config = try #require(AppConfig.from(infoDictionary: [
            "SupabaseURL": "http://127.0.0.1:54321",
            "SupabasePublishableKey": "sb_publishable_dummy",
        ]))
        #expect(config.supabaseURL.absoluteString == "http://127.0.0.1:54321")
        #expect(config.supabaseKey == "sb_publishable_dummy")
    }

    @Test func rejectsURLTruncatedByXcconfigComment() {
        #expect(AppConfig.from(infoDictionary: [
            "SupabaseURL": "http:",
            "SupabasePublishableKey": "sb_publishable_dummy",
        ]) == nil)
    }

    @Test func rejectsMissingValues() {
        #expect(AppConfig.from(infoDictionary: ["SupabaseURL": "http://127.0.0.1:54321", "SupabasePublishableKey": ""]) == nil)
        #expect(AppConfig.from(infoDictionary: [:]) == nil)
    }

    @Test func hostAppBundleIsConfigured() {
        let config = AppConfig.fromBundle()
        #expect(config.supabaseURL.host() != nil)
        #expect(!config.supabaseKey.isEmpty)
    }
}
