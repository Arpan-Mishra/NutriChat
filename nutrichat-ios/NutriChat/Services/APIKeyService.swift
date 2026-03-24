import Foundation
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "APIKeyService")

/// Protocol for mocking in tests.
protocol APIKeyServiceProtocol {
    func listKeys() async throws -> [APIKeyResponse]
    func createKey(label: String) async throws -> APIKeyCreateResponse
    func revokeKey(id: Int) async throws
}

/// API key as returned by GET /apikeys.
struct APIKeyResponse: Codable, Identifiable {
    let id: Int
    let label: String
    let keyPrefix: String
    let createdAt: String
    var lastUsedAt: String?
    var revokedAt: String?

    var isActive: Bool { revokedAt == nil }

    enum CodingKeys: String, CodingKey {
        case id, label
        case keyPrefix = "key_prefix"
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
        case revokedAt = "revoked_at"
    }
}

/// Response from POST /apikeys — includes the raw key (shown once).
struct APIKeyCreateResponse: Codable {
    let id: Int
    let label: String
    let apiKey: String

    enum CodingKeys: String, CodingKey {
        case id, label
        case apiKey = "api_key"
    }
}

final class APIKeyService: APIKeyServiceProtocol {
    static let shared = APIKeyService()
    private init() {}

    /// List all API keys for the current user.
    func listKeys() async throws -> [APIKeyResponse] {
        logger.info("Fetching API keys")
        return try await APIClient.shared.request(.apiKeys)
    }

    /// Generate a new API key. The raw key is returned only once.
    func createKey(label: String) async throws -> APIKeyCreateResponse {
        logger.info("Creating API key with label: \(label, privacy: .public)")
        return try await APIClient.shared.request(.createApiKey(label: label))
    }

    /// Revoke an API key by ID.
    func revokeKey(id: Int) async throws {
        logger.info("Revoking API key \(id)")
        try await APIClient.shared.requestVoid(.revokeApiKey(id: id))
    }
}
