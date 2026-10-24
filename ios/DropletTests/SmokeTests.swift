import Foundation
import Testing
@testable import Droplet

struct SmokeTests {
    @Test func infoPlistCarriesSupabaseConfig() throws {
        let url = try #require(Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String)
        #expect(url.hasPrefix("http"))
        #expect(url.contains("://"), "Config.xcconfig must write the URL as http:/$()/host")
        let key = try #require(Bundle.main.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String)
        #expect(!key.isEmpty)
    }

    @Test func displayNameIsDroplet() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "Droplet")
    }
}
