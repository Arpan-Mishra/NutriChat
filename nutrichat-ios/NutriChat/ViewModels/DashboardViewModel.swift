import Foundation
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "DashboardViewModel")

/// Manages dashboard state: selected date, diary data, loading/error states.
@Observable
final class DashboardViewModel {
    var diary: DiaryDay?
    var isLoading = false
    var errorMessage: String?
    var selectedDate: Date = .now

    private let diaryService: DiaryServiceProtocol

    init(diaryService: DiaryServiceProtocol = DiaryService.shared) {
        self.diaryService = diaryService
    }

    // MARK: - Computed

    /// Whether the selected date is today.
    var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    /// Display string for the selected date header.
    var dateDisplayString: String {
        if isToday { return "Today" }
        if Calendar.current.isDateInYesterday(selectedDate) { return "Yesterday" }
        if Calendar.current.isDateInTomorrow(selectedDate) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: selectedDate)
    }

    /// Calories consumed.
    var caloriesConsumed: Double { diary?.totalCalories ?? 0 }

    /// Daily calorie goal.
    var calorieGoal: Double { diary?.calorieGoal ?? 2000 }

    /// Calories remaining (negative if over goal).
    var caloriesRemaining: Double { calorieGoal - caloriesConsumed }

    /// Protein consumed in grams.
    var proteinConsumed: Double { diary?.totalProteinG ?? 0 }

    /// Protein goal in grams.
    var proteinGoal: Double { diary?.proteinGoal ?? 0 }

    /// Fat consumed in grams.
    var fatConsumed: Double { diary?.totalFatG ?? 0 }

    /// Fat goal in grams.
    var fatGoal: Double { diary?.fatGoal ?? 0 }

    /// Carbs consumed in grams.
    var carbsConsumed: Double { diary?.totalCarbsG ?? 0 }

    /// Carbs goal in grams.
    var carbsGoal: Double { diary?.carbsGoal ?? 0 }

    /// Entries for a specific meal type.
    func entries(for mealType: MealType) -> [MealEntry] {
        diary?.entries(for: mealType) ?? []
    }

    /// Calorie subtotal for a meal type.
    func mealCalories(for mealType: MealType) -> Double {
        entries(for: mealType).reduce(0) { $0 + $1.calories }
    }

    // MARK: - Actions

    /// Fetch diary for the currently selected date.
    func fetchDiary() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            diary = try await diaryService.fetchDay(date: selectedDate)
            logger.info("Diary loaded for \(self.selectedDate.apiDateString, privacy: .public): \(self.diary?.allEntries.count ?? 0) entries")
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Failed to load diary: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Navigate to the previous day.
    func goToPreviousDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
    }

    /// Navigate to the next day.
    func goToNextDay() {
        guard !isToday else { return }
        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
    }

    /// Jump back to today.
    func goToToday() {
        selectedDate = .now
    }

    /// Delete a diary entry and re-fetch totals.
    func deleteEntry(_ entry: MealEntry) async {
        do {
            try await diaryService.deleteEntry(id: entry.id)
            logger.info("Deleted entry \(entry.id)")
            await fetchDiary()
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Failed to delete entry: \(error.localizedDescription, privacy: .public)")
        }
    }
}
