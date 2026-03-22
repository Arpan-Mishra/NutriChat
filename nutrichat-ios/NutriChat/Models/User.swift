import Foundation

/// User profile as returned by GET /api/v1/users/me.
struct User: Codable, Identifiable {
    let id: Int
    let phoneNumber: String
    var email: String?
    var displayName: String?
    var dateOfBirth: String?
    var sex: String?
    var heightCm: Double?
    var weightKg: Double?
    var activityLevel: String?
    var goalType: String?
    var dailyCalorieGoal: Double?
    var proteinGoalG: Double?
    var carbsGoalG: Double?
    var fatGoalG: Double?
    var timezone: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case phoneNumber = "phone_number"
        case email
        case displayName = "display_name"
        case dateOfBirth = "date_of_birth"
        case sex
        case heightCm = "height_cm"
        case weightKg = "weight_kg"
        case activityLevel = "activity_level"
        case goalType = "goal_type"
        case dailyCalorieGoal = "daily_calorie_goal"
        case proteinGoalG = "protein_goal_g"
        case carbsGoalG = "carbs_goal_g"
        case fatGoalG = "fat_goal_g"
        case timezone
        case createdAt = "created_at"
    }
}
