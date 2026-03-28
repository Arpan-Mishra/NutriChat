import Foundation
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "FoodSearchViewModel")

/// Debounce intervals for search.
private let suggestDebounceNs: UInt64 = 300_000_000   // 300ms — backend now fans out to all sources
private let fullSearchDebounceNs: UInt64 = 800_000_000 // 800ms for explicit full search (more results)

/// Maximum number of cached search results to keep in memory.
private let maxCacheEntries = 50

/// Manages food search state: typeahead suggestions, full search, recent foods, logging.
@Observable
final class FoodSearchViewModel {
    var searchQuery = ""
    var searchResults: [FoodSearchResult] = []
    var recentFoods: [MealEntry] = []
    var isSearching = false
    var isSearchingFull = false
    var errorMessage: String?

    /// Set to true after successfully logging a food entry. Observed by FoodSearchView to auto-dismiss.
    var didLogFood = false

    /// The meal type pre-selected from the dashboard "+" button.
    var selectedMealType: MealType = .lunch

    /// The date being logged to (from dashboard's selected date).
    var logDate: Date = .now

    private let foodService: FoodServiceProtocol
    private let diaryService: DiaryServiceProtocol
    private var suggestTask: Task<Void, Never>?
    private var fullSearchTask: Task<Void, Never>?

    /// In-memory cache for search results (query → results).
    private var searchCache: [String: [FoodSearchResult]] = [:]
    private var cacheOrder: [String] = []

    init(
        foodService: FoodServiceProtocol = FoodService.shared,
        diaryService: DiaryServiceProtocol = DiaryService.shared
    ) {
        self.foodService = foodService
        self.diaryService = diaryService
    }

    // MARK: - Search

    /// Called whenever the search query changes. Fires suggest (which now hits all sources on backend).
    func handleSearchQueryChanged() {
        suggestTask?.cancel()
        fullSearchTask?.cancel()

        let query = searchQuery.trimmingCharacters(in: .whitespaces)

        if query.isEmpty {
            searchResults = []
            errorMessage = nil
            isSearching = false
            isSearchingFull = false
            return
        }

        // Check exact cache hit
        if let cached = searchCache[query.lowercased()] {
            searchResults = cached
            return
        }

        // Prefix-based filtering: if "chick" is cached, filter for "chicken" instantly
        let prefixFiltered = filterFromCachedPrefix(query: query)
        if let filtered = prefixFiltered, !filtered.isEmpty {
            searchResults = filtered
            // Still fire a background suggest to get better results
        }

        guard query.count >= 1 else { return }

        // Suggest: backend now fans out to all sources (1.5s timeout on backend)
        suggestTask = Task {
            try? await Task.sleep(nanoseconds: suggestDebounceNs)
            guard !Task.isCancelled else { return }
            await performSuggest(query: query)
        }
    }

    /// Explicit search trigger (user presses Search/Enter).
    func handleSearchSubmitted() {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else { return }

        suggestTask?.cancel()
        fullSearchTask?.cancel()

        fullSearchTask = Task {
            await performFullSearch(query: query)
        }
    }

    /// Suggest — backend fans out to all sources with 1.5s timeout.
    private func performSuggest(query: String) async {
        isSearching = true
        errorMessage = nil

        do {
            let results = try await foodService.suggestFood(query: query, limit: 10)
            guard !Task.isCancelled else { return }
            searchResults = results
            cacheResults(query: query, results: results)
            logger.debug("Suggest '\(query, privacy: .public)' returned \(results.count) results")
        } catch is CancellationError {
            // Ignore
        } catch {
            guard !Task.isCancelled else { return }
            // Don't show errors for suggest — user can press Search for full search
            logger.debug("Suggest failed: \(error.localizedDescription, privacy: .public)")
        }

        if !Task.isCancelled {
            isSearching = false
        }
    }

    /// Full search — backend fans out with 3s timeout, returns up to 20 results.
    private func performFullSearch(query: String) async {
        isSearchingFull = true
        isSearching = true
        errorMessage = nil
        defer {
            isSearchingFull = false
            isSearching = false
        }

        do {
            let results = try await foodService.searchFood(query: query, limit: 20)
            guard !Task.isCancelled else { return }
            searchResults = results
            cacheResults(query: query, results: results)
            logger.info("Full search '\(query, privacy: .public)' returned \(results.count) results")
        } catch is CancellationError {
            // Ignore
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            logger.error("Full search failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Filter cached results from a shorter prefix of the current query.
    private func filterFromCachedPrefix(query: String) -> [FoodSearchResult]? {
        let q = query.lowercased()
        // Walk backwards from (len-1) to 1 to find longest cached prefix
        for prefixLen in stride(from: q.count - 1, through: 1, by: -1) {
            let prefix = String(q.prefix(prefixLen))
            if let cached = searchCache[prefix] {
                let filtered = cached.filter { result in
                    result.foodName.lowercased().contains(q)
                }
                if !filtered.isEmpty {
                    return filtered
                }
            }
        }
        return nil
    }

    /// Cache search results with LRU eviction.
    private func cacheResults(query: String, results: [FoodSearchResult]) {
        let key = query.lowercased()
        if searchCache[key] == nil {
            cacheOrder.append(key)
        }
        searchCache[key] = results

        // Evict oldest entries beyond limit
        while cacheOrder.count > maxCacheEntries {
            let oldest = cacheOrder.removeFirst()
            searchCache.removeValue(forKey: oldest)
        }
    }

    // MARK: - Recent Foods

    /// Fetch recently logged foods for the empty state.
    func fetchRecentFoods() async {
        do {
            recentFoods = try await diaryService.fetchRecentFoods(limit: 10)
            logger.debug("Loaded \(self.recentFoods.count) recent foods")
        } catch {
            logger.debug("Failed to load recent foods: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Logging

    /// Log a food entry to the diary.
    func logFood(
        food: FoodSearchResult,
        servingG: Double,
        mealType: MealType,
        servingUnit: String? = nil,
        servingQuantity: Double? = nil
    ) async -> Bool {
        let macros = food.macros(forServingG: servingG)

        let entry = MealEntryCreate(
            mealType: mealType.rawValue,
            foodItemId: food.foodId,
            foodDescription: food.foodName,
            servingSizeG: servingG,
            servingUnit: servingUnit,
            servingQuantity: servingQuantity,
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
