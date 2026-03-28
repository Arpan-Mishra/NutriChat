import Foundation
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "FoodSearchViewModel")

/// Debounce interval for search queries.
private let searchDebounceNanoseconds: UInt64 = 300_000_000 // 300ms

/// Manages food search state: query, results, recent foods, loading.
@Observable
final class FoodSearchViewModel {
    var searchQuery = ""
    var searchResults: [FoodSearchResult] = []
    var isSearching = false
    var errorMessage: String?

    /// Set to true after successfully logging a food entry. Observed by FoodSearchView to auto-dismiss.
    var didLogFood = false

    /// The meal type pre-selected from the dashboard "+" button.
    var selectedMealType: MealType = .lunch

    /// The date being logged to (from dashboard's selected date).
    var logDate: Date = .now

    private let foodService: FoodServiceProtocol
    private let diaryService: DiaryServiceProtocol
    private var searchTask: Task<Void, Never>?

    init(
        foodService: FoodServiceProtocol = FoodService.shared,
        diaryService: DiaryServiceProtocol = DiaryService.shared
    ) {
        self.foodService = foodService
        self.diaryService = diaryService
    }

    // MARK: - Search

    /// Called whenever the search query changes. Debounces and fires search.
    func handleSearchQueryChanged() {
        searchTask?.cancel()

        let query = searchQuery.trimmingCharacters(in: .whitespaces)

        if query.isEmpty {
            searchResults = []
            errorMessage = nil
            return
        }

        guard query.count >= 2 else { return }

        searchTask = Task {
            // Debounce
            try? await Task.sleep(nanoseconds: searchDebounceNanoseconds)
            guard !Task.isCancelled else { return }

            await performSearch(query: query)
        }
    }

    /// Execute the actual search API call.
    private func performSearch(query: String) async {
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            let results = try await foodService.searchFood(query: query, limit: 20)
            guard !Task.isCancelled else { return }
            searchResults = results
            logger.info("Search '\(query, privacy: .public)' returned \(results.count) results")
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            logger.error("Search failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Logging

    /// Log a food entry to the diary.
    func logFood(
        food: FoodSearchResult,
        servingG: Double,
        mealType: MealType
    ) async -> Bool {
        let macros = food.macros(forServingG: servingG)

        let entry = MealEntryCreate(
            mealType: mealType.rawValue,
            foodItemId: food.foodId,
            foodDescription: food.foodName,
            servingSizeG: servingG,
            calories: macros.calories,
            proteinG: macros.protein,
            fatG: macros.fat,
            carbsG: macros.carbs,
            loggedDate: logDate.apiDateString,
            source: "app"
        )

        do {
            _ = try await diaryService.createEntry(entry)
            logger.info("Logged \(food.foodName, privacy: .public) (\(servingG)g) as \(mealType.rawValue, privacy: .public)")
            didLogFood = true
            return true
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Failed to log food: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Log a custom food entry (no food_item_id).
    func logCustomFood(
        name: String,
        calories: Double,
        proteinG: Double,
        fatG: Double,
        carbsG: Double,
        servingG: Double,
        mealType: MealType
    ) async -> Bool {
        let entry = MealEntryCreate(
            mealType: mealType.rawValue,
            foodItemId: nil,
            foodDescription: name,
            servingSizeG: servingG,
            calories: calories,
            proteinG: proteinG,
            fatG: fatG,
            carbsG: carbsG,
            loggedDate: logDate.apiDateString,
            source: "app"
        )

        do {
            _ = try await diaryService.createEntry(entry)
            logger.info("Logged custom food: \(name, privacy: .public)")
            didLogFood = true
            return true
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Failed to log custom food: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
