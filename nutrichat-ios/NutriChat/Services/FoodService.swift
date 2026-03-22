import Foundation
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "FoodService")

/// Protocol for mocking in tests.
protocol FoodServiceProtocol {
    func searchFood(query: String, limit: Int) async throws -> [FoodItem]
    func fetchFoodDetail(id: Int) async throws -> FoodItem
    func fetchByBarcode(code: String) async throws -> FoodItem
}

/// Response wrapper for food search results.
struct FoodSearchResponse: Codable {
    let items: [FoodItem]
    let total: Int
}

final class FoodService: FoodServiceProtocol {
    static let shared = FoodService()
    private init() {}

    /// Search for food items by query string.
    func searchFood(query: String, limit: Int = 20) async throws -> [FoodItem] {
        logger.info("Searching food: \(query, privacy: .public)")
        let response: FoodSearchResponse = try await APIClient.shared.request(
            .searchFood(query: query, limit: limit)
        )
        return response.items
    }

    /// Fetch details for a single food item.
    func fetchFoodDetail(id: Int) async throws -> FoodItem {
        logger.debug("Fetching food detail: \(id)")
        return try await APIClient.shared.request(.foodDetail(id: id))
    }

    /// Look up a food item by barcode.
    func fetchByBarcode(code: String) async throws -> FoodItem {
        logger.info("Barcode lookup: \(code, privacy: .public)")
        return try await APIClient.shared.request(.foodByBarcode(code: code))
    }
}
