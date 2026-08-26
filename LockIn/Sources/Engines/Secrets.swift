import Foundation

/// API keys, read at runtime from `Secrets.plist` — which is gitignored and
/// never committed. Ship-time alternative is to move the call behind your own
/// proxy so the key never lives on the device at all; for a personal build,
/// a local plist is fine.
///
/// To set up: copy `Secrets.example.plist` to `Secrets.plist` in
/// `LockIn/Sources/Resources/` (and keep the `BundleResources/Secrets.plist`
/// symlink, or copy into `BundleResources/` so Xcode packs it).
enum Secrets {
    private static let values: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return plist
    }()

    static var spoonacularKey: String? {
        guard let key = values["SpoonacularAPIKey"] as? String,
              !key.isEmpty,
              key != "PASTE_YOUR_KEY_HERE"
        else { return nil }
        return key
    }

    /// Whether live recipe data is available at all. When false the app runs
    /// entirely on the built-in food database — no degraded behaviour, just
    /// fewer recipes.
    static var hasSpoonacular: Bool { spoonacularKey != nil }

    /// OAuth client ID from the Google Cloud console. Absent means the Google
    /// sign-in button stays hidden rather than failing when tapped.
    static var googleClientID: String? {
        guard let key = values["GoogleClientID"] as? String,
              !key.isEmpty,
              key != "PASTE_YOUR_GOOGLE_CLIENT_ID_HERE"
        else { return nil }
        return key
    }

    static var claudeAPIKey: String? {
        guard let key = values["ClaudeAPIKey"] as? String,
              !key.isEmpty,
              key != "PASTE_YOUR_CLAUDE_KEY_HERE"
        else { return nil }
        return key
    }

    static var hasClaude: Bool { claudeAPIKey != nil }

    /// Optional override; defaults to Haiku inside ClaudeClient.
    static var claudeModel: String? {
        guard let model = values["ClaudeModel"] as? String, !model.isEmpty else { return nil }
        return model
    }
}
