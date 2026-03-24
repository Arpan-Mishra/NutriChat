import Foundation
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "ProfileViewModel")

/// Manages state for the Profile tab: user info, stats, API keys, goals.
@Observable
final class ProfileViewModel {
    // MARK: - User Profile

    var user: User?

    // MARK: - Weekly Stats

    var weeklyStats: WeeklyStats?
    var isLoadingStats = false

    // MARK: - API Keys (WhatsApp integration)

    var apiKeys: [APIKeyResponse] = []
    var isLoadingKeys = false
    var generatedKey: APIKeyCreateResponse?
    var isGeneratingKey = false

    // MARK: - Goals

    var calorieGoal: Double = 2000
    var proteinGoal: Double = 100
    var carbsGoal: Double = 250
    var fatGoal: Double = 65
    var isSavingGoals = false
    var goalsSaved = false

    // MARK: - General

    var isLoading = false
    var errorMessage: String?

    // MARK: - Services

    private let apiKeyService: APIKeyServiceProtocol

    init(apiKeyService: APIKeyServiceProtocol = APIKeyService.shared) {
        self.apiKeyService = apiKeyService
    }

    // MARK: - Profile

    /// Load user profile from API and populate goals from profile fields.
    func loadProfile() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loadedUser: User = try await APIClient.shared.request(.me)
            user = loadedUser
            syncGoalsFromUser(loadedUser)
            logger.info("Profile loaded: \(loadedUser.displayName ?? "unnamed", privacy: .public)")
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Failed to load profile: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Weekly Stats

    func fetchWeeklyStats() async {
        isLoadingStats = true
        defer { isLoadingStats = false }
        do {
            let startDate = Calendar.current.date(byAdding: .day, value: -6, to: .now) ?? .now
            weeklyStats = try await APIClient.shared.request(.weeklyStats(startDate: startDate))
            logger.info("Weekly stats loaded")
        } catch {
            logger.warning("Failed to load weekly stats: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - API Keys

    func fetchAPIKeys() async {
        isLoadingKeys = true
        defer { isLoadingKeys = false }
        do {
            apiKeys = try await apiKeyService.listKeys()
            logger.info("Loaded \(self.apiKeys.count) API keys")
        } catch {
            logger.warning("Failed to load API keys: \(error.localizedDescription, privacy: .public)")
        }
    }

    func generateAPIKey() async {
        isGeneratingKey = true
        defer { isGeneratingKey = false }
        do {
            let response = try await apiKeyService.createKey(label: "caloriebot")
            generatedKey = response
            await fetchAPIKeys()
            logger.info("API key generated successfully")
        } catch {
            errorMessage = "Failed to generate API key. Please try again."
            logger.error("Failed to generate API key: \(error.localizedDescription, privacy: .public)")
        }
    }

    func revokeAPIKey(id: Int) async {
        do {
            try await apiKeyService.revokeKey(id: id)
            generatedKey = nil
            await fetchAPIKeys()
            logger.info("API key \(id) revoked")
        } catch {
            errorMessage = "Failed to revoke API key."
            logger.error("Failed to revoke key \(id): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The currently active (non-revoked) API key, if any.
    var activeKey: APIKeyResponse? {
        apiKeys.first(where: { $0.isActive })
    }

    /// Whether the user has an active WhatsApp bot connection.
    var isWhatsAppConnected: Bool {
        activeKey != nil
    }

    // MARK: - Goals

    func saveGoals() async {
        isSavingGoals = true
        goalsSaved = false
        defer { isSavingGoals = false }
        do {
            let fields: [String: Any] = [
                "daily_calorie_goal": Int(calorieGoal),
                "protein_goal_g": Int(proteinGoal),
                "carbs_goal_g": Int(carbsGoal),
                "fat_goal_g": Int(fatGoal),
            ]
            let _: User = try await APIClient.shared.request(.updateProfile(fields))
            goalsSaved = true
            logger.info("Goals saved: cal=\(Int(self.calorieGoal)), p=\(Int(self.proteinGoal)), c=\(Int(self.carbsGoal)), f=\(Int(self.fatGoal))")
        } catch {
            errorMessage = "Failed to save goals."
            logger.error("Failed to save goals: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private

    private func syncGoalsFromUser(_ user: User) {
        if let cal = user.dailyCalorieGoal { calorieGoal = cal }
        if let p = user.proteinGoalG { proteinGoal = p }
        if let c = user.carbsGoalG { carbsGoal = c }
        if let f = user.fatGoalG { fatGoal = f }
    }
}

// MARK: - Weekly Stats Response

struct WeeklyStats: Codable {
    let startDate: String
    let endDate: String
    let totalDays: Int
    let daysLogged: Int
    let totalCalories: Double
    let avgCalories: Double
    let avgProteinG: Double
    let avgFatG: Double
    let avgCarbsG: Double
    let totalEntries: Int
    let calorieGoal: Double?

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case endDate = "end_date"
        case totalDays = "total_days"
        case daysLogged = "days_logged"
        case totalCalories = "total_calories"
        case avgCalories = "avg_calories"
        case avgProteinG = "avg_protein_g"
        case avgFatG = "avg_fat_g"
        case avgCarbsG = "avg_carbs_g"
        case totalEntries = "total_entries"
        case calorieGoal = "calorie_goal"
    }
}
