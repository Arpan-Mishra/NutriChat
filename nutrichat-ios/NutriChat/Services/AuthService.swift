import Foundation
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "AuthService")

/// Protocol for mocking in tests.
protocol AuthServiceProtocol {
    func requestOTP(phoneNumber: String) async throws -> OTPRequestResponse
    func verifyOTP(phoneNumber: String, code: String) async throws -> TokenResponse
    func refreshToken() async throws
    func logout()
}

/// Response from OTP request endpoint.
struct OTPRequestResponse: Codable {
    let message: String
    let expiresIn: Int?
    /// Only present in debug/dev mode — nil in production.
    let otpDebug: String?

    enum CodingKeys: String, CodingKey {
        case message
        case expiresIn = "expires_in"
        case otpDebug = "otp_debug"
    }
}

/// Response from GET /users/me/tdee endpoint.
struct TDEEResponse: Codable {
    let bmr: Double
    let tdee: Double
    let recommendedCalories: Int
    let method: String
    let goalType: String?

    enum CodingKeys: String, CodingKey {
        case bmr, tdee, method
        case recommendedCalories = "recommended_calories"
        case goalType = "goal_type"
    }
}

final class AuthService: AuthServiceProtocol {
    static let shared = AuthService()
    private init() {}

    /// Request an OTP code for the given phone number.
    func requestOTP(phoneNumber: String) async throws -> OTPRequestResponse {
        logger.info("Requesting OTP for phone: \(phoneNumber.prefix(4), privacy: .public)****")
        return try await APIClient.shared.request(.otpRequest(phoneNumber: phoneNumber))
    }

    /// Verify OTP and receive JWT tokens. Stores tokens in Keychain.
    func verifyOTP(phoneNumber: String, code: String) async throws -> TokenResponse {
        logger.info("Verifying OTP for phone: \(phoneNumber.prefix(4), privacy: .public)****")
        let response: TokenResponse = try await APIClient.shared.request(
            .otpVerify(phoneNumber: phoneNumber, code: code)
        )
        KeychainService.accessToken = response.accessToken
        KeychainService.refreshToken = response.refreshToken
        logger.info("OTP verified, tokens stored")
        return response
    }

    /// Refresh the access token using the stored refresh token.
    func refreshToken() async throws {
        guard let token = KeychainService.refreshToken else {
            throw APIError.unauthorized
        }
        let response: TokenResponse = try await APIClient.shared.request(.refreshToken(token))
        KeychainService.accessToken = response.accessToken
        KeychainService.refreshToken = response.refreshToken
        logger.info("Tokens refreshed")
    }

    /// Clear all tokens and sign out.
    func logout() {
        KeychainService.clearTokens()
        logger.info("User logged out")
    }

    /// Check if user has a valid access token stored.
    var isAuthenticated: Bool {
        KeychainService.accessToken != nil
    }
}
