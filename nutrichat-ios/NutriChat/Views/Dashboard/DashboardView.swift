import SwiftUI
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "DashboardView")

/// Main dashboard — calorie ring, macro bars, meal sections, day navigation.
struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()
    @State private var foodSearchVM = FoodSearchViewModel()
    @State private var showFoodSearch = false
    @State private var entryToEdit: MealEntry?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    dateNavigator
                    calorieSection
                    macroSection
                    mealsSection
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await viewModel.fetchDiary()
            }
            .task(id: viewModel.selectedDate.apiDateString) {
                await viewModel.fetchDiary()
            }
            .overlay {
                if viewModel.isLoading && viewModel.diary == nil {
                    ProgressView("Loading...")
                }
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button("Retry") {
                    Task { await viewModel.fetchDiary() }
                }
                Button("Dismiss", role: .cancel) {}
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 50)
                    .onEnded { value in
                        if value.translation.width < -50 {
                            viewModel.goToNextDay()
                        } else if value.translation.width > 50 {
                            viewModel.goToPreviousDay()
                        }
                    }
            )
            .navigationDestination(isPresented: $showFoodSearch) {
                FoodSearchView(viewModel: foodSearchVM)
            }
            .onChange(of: showFoodSearch) { _, isShowing in
                if !isShowing {
                    Task { await viewModel.fetchDiary() }
                }
            }
            .sheet(item: $entryToEdit) { entry in
                MealEntryEditView(
                    entry: entry,
                    onUpdated: {
                        Task { await viewModel.fetchDiary() }
                    },
                    onDeleted: {
                        Task { await viewModel.fetchDiary() }
                    }
                )
            }
        }
    }

    // MARK: - Date Navigator

    private var dateNavigator: some View {
        HStack {
            Button {
                viewModel.goToPreviousDay()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
            }
            .accessibilityLabel("Previous day")

            Spacer()

            VStack(spacing: 2) {
                Text(viewModel.dateDisplayString)
                    .font(.headline)

                if !viewModel.isToday {
                    Button("Go to Today") {
                        viewModel.goToToday()
                    }
                    .font(.caption)
                    .accessibilityLabel("Go to today")
                }
            }

            Spacer()

            Button {
                viewModel.goToNextDay()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
            }
            .disabled(viewModel.isToday)
            .accessibilityLabel("Next day")
        }
        .padding(.vertical, 8)
    }

    // MARK: - Calorie Ring

    private var calorieSection: some View {
        CalorieRingView(
            consumed: viewModel.caloriesConsumed,
            goal: viewModel.calorieGoal,
            remaining: viewModel.caloriesRemaining
        )
        .frame(width: 200, height: 200)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Macros

    private var macroSection: some View {
        VStack(spacing: 14) {
            MacroBarView(
                label: "Protein",
                consumed: viewModel.proteinConsumed,
                goal: viewModel.proteinGoal,
                color: .blue
            )
            MacroBarView(
                label: "Carbs",
                consumed: viewModel.carbsConsumed,
                goal: viewModel.carbsGoal,
                color: .orange
            )
            MacroBarView(
                label: "Fat",
                consumed: viewModel.fatConsumed,
                goal: viewModel.fatGoal,
                color: .purple
            )
        }
        .cardStyle()
    }

    // MARK: - Meal Sections

    private var mealsSection: some View {
        VStack(spacing: 12) {
            ForEach(MealType.allCases, id: \.self) { mealType in
                MealSectionView(
                    mealType: mealType,
                    entries: viewModel.entries(for: mealType),
                    totalCalories: viewModel.mealCalories(for: mealType),
                    onAdd: {
                        handleAddFood(mealType: mealType)
                    },
                    onEdit: { entry in
                        entryToEdit = entry
                    },
                    onDelete: { entry in
                        Task { await viewModel.deleteEntry(entry) }
                    }
                )
            }
        }
    }

    // MARK: - Actions

    private func handleAddFood(mealType: MealType) {
        foodSearchVM.selectedMealType = mealType
        foodSearchVM.logDate = viewModel.selectedDate
        foodSearchVM.searchQuery = ""
        foodSearchVM.searchResults = []
        foodSearchVM.errorMessage = nil
        showFoodSearch = true
        logger.info("Add food tapped for \(mealType.rawValue, privacy: .public)")
    }
}

#Preview {
    DashboardView()
}
