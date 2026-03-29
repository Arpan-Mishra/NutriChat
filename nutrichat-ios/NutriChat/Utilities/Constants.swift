import Foundation

/// App-wide constants organised by namespace.
enum API {
    static let baseURL = "https://nutrichat-production.up.railway.app"
    static let apiVersion = "/api/v1"

    /// Full base path for all API requests.
    static var basePath: String { "\(baseURL)\(apiVersion)" }

    /// WhatsApp bot phone number (international format, no +).
    static let botPhone = "15551781677"
}

enum AppInfo {
    static let bundleID = "app.nutrichat.NutriChat"
    static let deepLinkScheme = "nutrichat"
    static let minIOSVersion = "17.0"
    static let privacyPolicyURL = "https://arpan-mishra.github.io/NutriChat/privacy-policy.html"
    static let supportURL = "https://github.com/Arpan-Mishra/NutriChat/issues"
    static let appVersion = "1.0.0"
}

enum Keychain {
    static let accessTokenKey = "nutrichat_access_token"
    static let refreshTokenKey = "nutrichat_refresh_token"
}
