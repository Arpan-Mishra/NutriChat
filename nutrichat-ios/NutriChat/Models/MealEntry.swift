import Foundation

/// A single meal entry as returned by the diary API.
struct MealEntry: Codable, Identifiable {
    let id: Int
    let userId: Int
    var foodItemId: Int?
    let mealType: String
    var foodDescription: String?
    var servingSizeG: Double?
    let calories: Double
    let proteinG: Double
    let fatG: Double
    let carbsG: Double
    var fiberG: Double?
    var sodiumMg: Double?
    let source: String
    let loggedDate: String
    let loggedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case foodItemId = "food_item_id"
        case mealType = "meal_type"
        case foodDescription = "food_description"
        case servingSizeG = "serving_size_g"
        case calories
        case proteinG = "protein_g"
        case fatG = "fat_g"
        case carbsG = "carbs_g"
        case fiberG = "fiber_g"
        case sodiumMg = "sodium_mg"
        case source
        case loggedDate = "logged_date"
        case loggedAt = "logged_at"
    }
}

/// Meal type options matching the backend enum.
enum MealType: String, CaseIterable, Codable {
    case breakfast
    case lunch
    case dinner
    case snack

    var displayName: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon"
        case .snack: "cup.and.saucer"
        }
    }
}
