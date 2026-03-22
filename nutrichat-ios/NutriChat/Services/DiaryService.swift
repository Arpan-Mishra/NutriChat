import Foundation
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "DiaryService")

/// Protocol for mocking in tests.
protocol DiaryServiceProtocol {
    func fetchDay(date: Date) async throws -> DiaryDay
    func createEntry(_ entry: MealEntryCreate) async throws -> MealEntry
    func updateEntry(id: Int, update: MealEntryUpdate) async throws -> MealEntry
    func deleteEntry(id: Int) async throws
}

/// Full diary day response — entries grouped by meal type with totals.
struct DiaryDay: Codable {
    let date: String
    let entries: [MealEntry]
    let totals: DiaryTotals
    var goalProgress: GoalProgress?

    enum CodingKeys: String, CodingKey {
        case date, entries, totals
        case goalProgress = "goal_progress"
    }
}

/// Daily macro totals.
struct DiaryTotals: Codable {
    let calories: Double
    let proteinG: Double
    let fatG: Double
    let carbsG: Double

    enum CodingKeys: String, CodingKey {
        case calories
        case proteinG = "protein_g"
        case fatG = "fat_g"
        case carbsG = "carbs_g"
    }
}

/// Progress toward daily goals.
struct GoalProgress: Codable {
    let calorieGoal: Double?
    let caloriePercent: Double?
    let proteinGoal: Double?
    let proteinPercent: Double?
    let fatGoal: Double?
    let fatPercent: Double?
    let carbsGoal: Double?
    let carbsPercent: Double?

    enum CodingKeys: String, CodingKey {
        case calorieGoal = "calorie_goal"
        case caloriePercent = "calorie_percent"
        case proteinGoal = "protein_goal"
        case proteinPercent = "protein_percent"
        case fatGoal = "fat_goal"
        case fatPercent = "fat_percent"
        case carbsGoal = "carbs_goal"
        case carbsPercent = "carbs_percent"
    }
}

/// Request body for creating a meal entry.
struct MealEntryCreate: Codable {
    let mealType: String
    var foodItemId: Int?
    var foodDescription: String?
    var servingSizeG: Double?
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
}
