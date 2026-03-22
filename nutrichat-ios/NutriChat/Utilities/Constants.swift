import Foundation

/// App-wide constants organised by namespace.
enum API {
    static let baseURL = "https://nutrichat-production.up.railway.app"
    static let apiVersion = "/api/v1"

    /// Full base path for all API requests.
    static var basePath: String { "\(baseURL)\(apiVersion)" }

    /// WhatsApp bot phone number (international format, no +).
    static let botPhone = "YOUR_BOT_PHONE_NUMBER"
}

enum App {
    static let bundleID = "app.nutrichat.NutriChat"
    static let deepLinkScheme = "nutrichat"
    static let minIOSVersion = "17.0"
}

enum Keychain {
    static let accessTokenKey = "nutrichat_access_token"
    static let refreshTokenKey = "nutrichat_refresh_token"
}
