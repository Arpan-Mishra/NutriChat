import Foundation
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "APIClient")

// MARK: - APIError

/// Errors surfaced by the networking layer.
enum APIError: LocalizedError {
    case unauthorized
    case notFound
    case serverError(Int)
    case decodingError(Error)
    case networkUnavailable
    case badRequest(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Your session has expired. Please sign in again."
        case .notFound:
            "The requested resource was not found."
        case .serverError(let code):
            "Server error (\(code)). Please try again later."
        case .decodingError(let error):
            "Data format error: \(error.localizedDescription)"
        case .networkUnavailable:
            "No internet connection. Please check your network."
        case .badRequest(let message):
            message
        }
    }
}

// MARK: - Endpoint

/// Describes an API endpoint — method, path, optional body and query params.
struct Endpoint {
    let method: String
    let path: String
    var body: Encodable?
    var queryItems: [URLQueryItem]?

    /// Full URL constructed from base path + endpoint path + query items.
    var url: URL? {
        var components = URLComponents(string: "\(API.basePath)\(path)")
        components?.queryItems = queryItems
        return components?.url
    }
}

// MARK: - Endpoint Factory

extension Endpoint {
    // Auth
    static func otpRequest(phoneNumber: String) -> Endpoint {
        Endpoint(method: "POST", path: "/auth/otp/request", body: ["phone_number": phoneNumber])
    }

    static func otpVerify(phoneNumber: String, code: String) -> Endpoint {
        Endpoint(method: "POST", path: "/auth/otp/verify", body: ["phone_number": phoneNumber, "code": code])
    }

    static func refreshToken(_ token: String) -> Endpoint {
        Endpoint(method: "POST", path: "/auth/refresh", body: ["refresh_token": token])
    }

    // Users
    static var me: Endpoint {
        Endpoint(method: "GET", path: "/users/me")
    }

    static func updateProfile(_ fields: [String: Any]) -> Endpoint {
        Endpoint(method: "PATCH", path: "/users/me", body: AnyCodable(fields))
    }

    static var tdee: Endpoint {
        Endpoint(method: "GET", path: "/users/me/tdee")
    }

    // Food
    static func searchFood(query: String, limit: Int = 20) -> Endpoint {
        Endpoint(
            method: "GET",
            path: "/food/search",
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
    }

    static func suggestFood(query: String, limit: Int = 10) -> Endpoint {
        Endpoint(
            method: "GET",
            path: "/food/suggest",
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
    }

    static func foodDetail(id: Int) -> Endpoint {
        Endpoint(method: "GET", path: "/food/\(id)")
    }

    static func foodByBarcode(code: String) -> Endpoint {
        Endpoint(method: "GET", path: "/food/barcode/\(code)")
    }

    // Diary
    static func diaryDay(date: Date) -> Endpoint {
        Endpoint(method: "GET", path: "/diary/\(date.apiDateString)")
    }

    static func createEntry(_ body: Encodable) -> Endpoint {
        Endpoint(method: "POST", path: "/diary/entries", body: body)
    }

    static func updateEntry(id: Int, body: Encodable) -> Endpoint {
        Endpoint(method: "PATCH", path: "/diary/entries/\(id)", body: body)
    }

    static func deleteEntry(id: Int) -> Endpoint {
        Endpoint(method: "DELETE", path: "/diary/entries/\(id)")
    }

    // Goals
    static var goals: Endpoint {
        Endpoint(method: "GET", path: "/goals/", queryItems: [URLQueryItem(name: "active_only", value: "true")])
    }

    static func updateGoals(_ body: Encodable) -> Endpoint {
        Endpoint(method: "PATCH", path: "/goals/", body: body)
    }

    // Stats
    static func dailyStats(date: Date) -> Endpoint {
        Endpoint(method: "GET", path: "/stats/daily", queryItems: [URLQueryItem(name: "date", value: date.apiDateString)])
    }

    static func weeklyStats(startDate: Date) -> Endpoint {
        Endpoint(
            method: "GET",
            path: "/stats/weekly",
            queryItems: [URLQueryItem(name: "start_date", value: startDate.apiDateString)]
        )
    }

    // Weight
    static func logWeight(_ weightKg: Double) -> Endpoint {
        Endpoint(method: "POST", path: "/weight/", body: ["weight_kg": weightKg])
    }

    static func weightHistory(limit: Int = 30) -> Endpoint {
        Endpoint(
            method: "GET",
            path: "/weight/",
            queryItems: [URLQueryItem(name: "limit", value: String(limit))]
        )
    }

    // API Keys
    static var apiKeys: Endpoint {
        Endpoint(method: "GET", path: "/apikeys/")
    }

    static func createApiKey(label: String) -> Endpoint {
        Endpoint(method: "POST", path: "/apikeys/", body: ["label": label])
    }

    static func revokeApiKey(id: Int) -> Endpoint {
        Endpoint(method: "DELETE", path: "/apikeys/\(id)")
    }
}

// MARK: - APIClient

/// Singleton HTTP client. All requests go through here. JWT injected automatically.
final class APIClient: Sendable {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    /// Generic request — decodes response into `T`.
    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        guard let url = endpoint.url else {
            throw APIError.badRequest("Invalid URL")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = endpoint.method

        // Inject JWT if available
        if let token = KeychainService.accessToken {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Encode body
        if let body = endpoint.body {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try encodeBody(body)
        }

        logger.debug("\(endpoint.method) \(url.absoluteString, privacy: .public)")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            logger.error("Network error: \(error.localizedDescription, privacy: .public)")
            throw APIError.networkUnavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkUnavailable
        }

        // Handle 401 — attempt token refresh once
        if httpResponse.statusCode == 401 {
            if let refreshed = try? await attemptTokenRefresh() {
                KeychainService.accessToken = refreshed
                // Retry original request with new token
                urlRequest.setValue("Bearer \(refreshed)", forHTTPHeaderField: "Authorization")
                let (retryData, retryResponse) = try await session.data(for: urlRequest)
                guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                    throw APIError.networkUnavailable
                }
                return try handleResponse(data: retryData, statusCode: retryHTTP.statusCode)
            }
            throw APIError.unauthorized
        }

        return try handleResponse(data: data, statusCode: httpResponse.statusCode)
    }

    /// Fire-and-forget request for DELETE endpoints that return no body.
    func requestVoid(_ endpoint: Endpoint) async throws {
        let _: EmptyResponse = try await request(endpoint)
    }

    // MARK: - Private

    private func handleResponse<T: Decodable>(data: Data, statusCode: Int) throws -> T {
        switch statusCode {
        case 200...299:
            // 204 No Content — return empty decoded object if possible
            if data.isEmpty, let empty = EmptyResponse() as? T {
                return empty
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                logger.error("Decoding error: \(error.localizedDescription, privacy: .public)")
                throw APIError.decodingError(error)
            }
        case 400:
            let detail = extractDetail(from: data)
            throw APIError.badRequest(detail)
        case 404:
            throw APIError.notFound
        case 401:
            throw APIError.unauthorized
        default:
            logger.error("Server error: \(statusCode)")
            throw APIError.serverError(statusCode)
        }
    }

    private func attemptTokenRefresh() async throws -> String? {
        guard let refreshToken = KeychainService.refreshToken else { return nil }

        let endpoint = Endpoint.refreshToken(refreshToken)
        guard let url = endpoint.url else { return nil }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try encodeBody(endpoint.body!)

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        let tokenResponse = try decoder.decode(TokenResponse.self, from: data)
        KeychainService.refreshToken = tokenResponse.refreshToken
        logger.info("Token refreshed successfully")
        return tokenResponse.accessToken
    }

    private func encodeBody(_ body: Encodable) throws -> Data {
        if let anyCodable = body as? AnyCodable {
            return try JSONSerialization.data(withJSONObject: anyCodable.value)
        }
        return try encoder.encode(body)
    }

    private func extractDetail(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = json["detail"] as? String {
            return detail
        }
        return "Bad request"
    }
}

// MARK: - Helper Types

/// For decoding token responses from auth endpoints.
struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
    }
}

/// For endpoints that return empty or minimal responses.
struct EmptyResponse: Codable {}

/// Wrapper to encode arbitrary [String: Any] dictionaries.
struct AnyCodable: Encodable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        // Encoding handled by JSONSerialization in APIClient
    }
}
