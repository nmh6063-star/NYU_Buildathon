import Foundation

/// Supabase connection settings, injected through Config.xcconfig -> Info.plist.
struct AppConfig: Sendable {
    let supabaseURL: URL
    let supabaseKey: String

    static func fromBundle(_ bundle: Bundle = .main) -> AppConfig {
        guard let config = from(infoDictionary: bundle.infoDictionary ?? [:]) else {
            preconditionFailure(
                "SupabaseURL / SupabasePublishableKey are missing from Info.plist. "
                    + "Run scripts/make-ios-config.sh, then rebuild."
            )
        }
        return config
    }

    /// Nil when either value is missing, or when the URL has no host
    /// (for example "http:" because an xcconfig `//` started a comment).
    static func from(infoDictionary info: [String: Any]) -> AppConfig? {
        guard let rawURL = info["SupabaseURL"] as? String,
              let url = URL(string: rawURL), url.host() != nil,
              let key = info["SupabasePublishableKey"] as? String, !key.isEmpty
        else { return nil }
        return AppConfig(supabaseURL: url, supabaseKey: key)
    }
}
