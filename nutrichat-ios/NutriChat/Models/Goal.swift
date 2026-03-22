import Foundation

/// A user goal as returned by the goals API.
struct Goal: Codable, Identifiable {
    let id: Int
    let userId: Int
    let goalType: String
    let targetValue: Double
    let unit: String
    var isActive: Bool
    var startDate: String?
    var endDate: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case goalType = "goal_type"
        case targetValue = "target_value"
        case unit
        case isActive = "is_active"
        case startDate = "start_date"
        case endDate = "end_date"
        case createdAt = "created_at"
    }
}
