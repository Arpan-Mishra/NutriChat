import Foundation
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "FoodService")

/// Protocol for mocking in tests.
protocol FoodServiceProtocol {
    func searchFood(query: String, limit: Int) async throws -> [FoodSearchResult]
    func suggestFood(query: String, limit: Int) async throws -> [FoodSearchResult]
    func fetchFoodDetail(id: Int) async throws -> FoodItem
    func fetchByBarcode(code: String) async throws -> FoodSearchResult
}

/// A serving option for a food item (e.g. "1 cup" = 240g).
struct FoodServing: Codable, Identifiable, Hashable {
    let id: Int
    let servingDescription: String
    let servingSizeG: Double
    var metricServingAmount: Double?
    var metricServingUnit: String?
    let isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case servingDescription = "serving_description"
        case servingSizeG = "serving_size_g"
        case metricServingAmount = "metric_serving_amount"
        case metricServingUnit = "metric_serving_unit"
        case isDefault = "is_default"
    }
}

/// Search result from GET /food/search — lighter than full FoodItem.
struct FoodSearchResult: Codable, Identifiable, Hashable {
    let foodId: Int
    let foodName: String
    var brand: String?
    let source: String
    let caloriesPer100g: Double
    let proteinPer100g: Double
    let fatPer100g: Double
    let carbsPer100g: Double
    let servingSizeG: Double
    let servingDescription: String
    var servings: [FoodServing]?

    /// Identifiable conformance uses foodId.
    var id: Int { foodId }

    enum CodingKeys: String, CodingKey {
        case foodId = "food_id"
        case foodName = "food_name"
        case brand, source, servings
        case caloriesPer100g = "calories_per_100g"
        case proteinPer100g = "protein_per_100g"
        case fatPer100g = "fat_per_100g"
        case carbsPer100g = "carbs_per_100g"
        case servingSizeG = "serving_size_g"
        case servingDescription = "serving_description"
    }

    /// Compute macros for a given serving size in grams.
    func macros(forServingG grams: Double) -> (calories: Double, protein: Double, fat: Double, carbs: Double) {
        let factor = grams / 100.0
        return (
            calories: caloriesPer100g * factor,
            protein: proteinPer100g * factor,
            fat: fatPer100g * factor,
            carbs: carbsPer100g * factor
        )
    }
}

final class FoodService: FoodServiceProtocol {
    static let shared = FoodService()
    private init() {}

    /// Search for food items — full layered search (local + external APIs).
    func searchFood(query: String, limit: Int = 20) async throws -> [FoodSearchResult] {
        logger.info("Searching food: \(query, privacy: .public)")
        return try await APIClient.shared.request(.searchFood(query: query, limit: limit))
    }

    /// Typeahead suggestions — local DB only, fast.
    func suggestFood(query: String, limit: Int = 10) async throws -> [FoodSearchResult] {
        logger.debug("Suggesting food: \(query, privacy: .public)")
        return try await APIClient.shared.request(.suggestFood(query: query, limit: limit))
    }

    /// Fetch details for a single food item.
    func fetchFoodDetail(id: Int) async throws -> FoodItem {
        logger.debug("Fetching food detail: \(id)")
        return try await APIClient.shared.request(.foodDetail(id: id))
    }

    /// Look up a food item by barcode.
    func fetchByBarcode(code: String) async throws -> FoodSearchResult {
        logger.info("Barcode lookup: \(code, privacy: .public)")
        return try await APIClient.shared.request(.foodByBarcode(code: code))
    }
}
