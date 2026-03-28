import Foundation
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "DiaryService")

/// Protocol for mocking in tests.
protocol DiaryServiceProtocol {
    func fetchDay(date: Date) async throws -> DiaryDay
    func createEntry(_ entry: MealEntryCreate) async throws -> MealEntry
    func updateEntry(id: Int, update: MealEntryUpdate) async throws -> MealEntry
    func deleteEntry(id: Int) async throws
    func fetchRecentFoods(limit: Int) async throws -> [MealEntry]
}

/// Full diary day response — matches backend `DayDiaryResponse`.
/// Backend groups entries by meal type in a `meals` dict.
struct DiaryDay: Decodable {
    let date: String
    let meals: [String: [MealEntry]]
    let totals: [String: Double]
    let goals: [String: Double]
    let progressPct: [String: Double]

    enum CodingKeys: String, CodingKey {
        case date, meals, totals, goals
        case progressPct = "progress_pct"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        meals = try container.decode([String: [MealEntry]].self, forKey: .meals)
        totals = try container.decode([String: Double].self, forKey: .totals)

        // Goals and progress_pct may contain null values — decode and drop nulls
        goals = Self.decodeNullableDict(container: container, key: .goals)
        progressPct = Self.decodeNullableDict(container: container, key: .progressPct)
    }

    /// Decode a JSON dict that may contain null values, dropping nulls.
    private static func decodeNullableDict(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> [String: Double] {
        guard let raw = try? container.decode([String: Double?].self, forKey: key) else {
            return [:]
        }
        return raw.compactMapValues { $0 }
    }

    /// All entries flattened into a single array.
    var allEntries: [MealEntry] {
        meals.values.flatMap { $0 }
    }

    /// Entries for a specific meal type.
    func entries(for mealType: MealType) -> [MealEntry] {
        meals[mealType.rawValue] ?? []
    }

    // MARK: - Totals helpers

    var totalCalories: Double { totals["calories"] ?? 0 }
    var totalProteinG: Double { totals["protein_g"] ?? 0 }
    var totalFatG: Double { totals["fat_g"] ?? 0 }
    var totalCarbsG: Double { totals["carbs_g"] ?? 0 }

    // MARK: - Goal helpers

    var calorieGoal: Double? { goals["calorie_goal"] }
    var proteinGoal: Double? { goals["protein_goal"] }
    var fatGoal: Double? { goals["fat_goal"] }
    var carbsGoal: Double? { goals["carbs_goal"] }
}

/// Request body for creating a meal entry.
struct MealEntryCreate: Codable {
    let mealType: String
    var foodItemId: Int?
    var foodDescription: String?
    var servingSizeG: Double?
    var servingUnit: String?
    var servingQuantity: Double?
    var calories: Double?
    var proteinG: Double?
    var fatG: Double?
    var carbsG: Double?
    let loggedDate: String
    let source: String

    enum CodingKeys: String, CodingKey {
        case mealType = "meal_type"
        case foodItemId = "food_item_id"
        case foodDescription = "food_description"
        case servingSizeG = "serving_size_g"
        case servingUnit = "serving_unit"
        case servingQuantity = "serving_quantity"
        case calories
        case proteinG = "protein_g"
        case fatG = "fat_g"
        case carbsG = "carbs_g"
        case loggedDate = "logged_date"
        case source
    }
}

/// Request body for updating a meal entry.
struct MealEntryUpdate: Codable {
    var servingSizeG: Double?
    var mealType: String?
    var calories: Double?
    var proteinG: Double?
    var fatG: Double?
    var carbsG: Double?

    enum CodingKeys: String, CodingKey {
        case servingSizeG = "serving_size_g"
        case mealType = "meal_type"
        case calories
        case proteinG = "protein_g"
        case fatG = "fat_g"
        case carbsG = "carbs_g"
    }
}

final class DiaryService: DiaryServiceProtocol {
    static let shared = DiaryService()
    private init() {}

    /// Fetch all entries for a given day.
    func fetchDay(date: Date) async throws -> DiaryDay {
        logger.info("Fetching diary for \(date.apiDateString, privacy: .public)")
        return try await APIClient.shared.request(.diaryDay(date: date))
    }

    /// Create a new meal entry.
    func createEntry(_ entry: MealEntryCreate) async throws -> MealEntry {
        logger.info("Creating entry: \(entry.foodDescription ?? "unknown", privacy: .public)")
        return try await APIClient.shared.request(.createEntry(entry))
    }

    /// Update an existing meal entry.
    func updateEntry(id: Int, update: MealEntryUpdate) async throws -> MealEntry {
        logger.info("Updating entry \(id)")
        return try await APIClient.shared.request(.updateEntry(id: id, body: update))
    }

    /// Delete a meal entry.
    func deleteEntry(id: Int) async throws {
        logger.info("Deleting entry \(id)")
        try await APIClient.shared.requestVoid(.deleteEntry(id: id))
    }

    /// Fetch recently logged foods, deduplicated by name.
    func fetchRecentFoods(limit: Int = 10) async throws -> [MealEntry] {
        logger.info("Fetching recent foods (limit: \(limit))")
        return try await APIClient.shared.request(.recentFoods(limit: limit))
    }
}
