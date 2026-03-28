import SwiftUI
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "FoodDetailView")

/// Food detail screen — nutrition facts, quantity input, meal type picker, "Add to Diary".
struct FoodDetailView: View {
    let food: FoodSearchResult
    @Bindable var viewModel: FoodSearchViewModel
    var onLogged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var servingText: String = ""
    @State private var selectedMealType: MealType = .lunch
    @State private var isLogging = false

    /// Parsed serving size in grams.
    private var servingG: Double {
        Double(servingText) ?? food.servingSizeG
    }

    /// Live-computed macros based on current serving.
    private var macros: (calories: Double, protein: Double, fat: Double, carbs: Double) {
        food.macros(forServingG: servingG)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                nutritionCard
                servingSection
                mealTypeSection
                addButton
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Food Detail")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            servingText = food.servingSizeG.noDecimal
            selectedMealType = viewModel.selectedMealType
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 6) {
            Text(food.foodName)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            if let brand = food.brand, !brand.isEmpty {
                Text(brand)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Source: \(food.source)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Nutrition Card

    private var nutritionCard: some View {
        VStack(spacing: 16) {
            // Big calorie number
            VStack(spacing: 4) {
                Text(macros.calories.noDecimal)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                Text("kcal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Macro breakdown
            HStack(spacing: 0) {
                macroColumn(label: "Protein", value: macros.protein, color: .blue)
                Divider().frame(height: 40)
                macroColumn(label: "Carbs", value: macros.carbs, color: .orange)
                Divider().frame(height: 40)
                macroColumn(label: "Fat", value: macros.fat, color: .purple)
            }

            // Per 100g reference
            HStack(spacing: 16) {
                Text("Per 100g:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(food.caloriesPer100g.noDecimal) kcal")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text("P: \(food.proteinPer100g.oneDecimal)g")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text("C: \(food.carbsPer100g.oneDecimal)g")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text("F: \(food.fatPer100g.oneDecimal)g")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private func macroColumn(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value.oneDecimal)
                .font(.headline.monospaced())
                .foregroundStyle(color)
            Text("\(label) (g)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Serving Size

    private var servingSection: some View {
        VStack(spacing: 12) {
            Text("Serving Size")
                .font(.headline)

            HStack(spacing: 12) {
                // Quick presets
                ForEach([50, 100, 150, 200], id: \.self) { grams in
                    Button("\(grams)g") {
                        servingText = "\(grams)"
                    }
                    .buttonStyle(.bordered)
                    .tint(servingG == Double(grams) ? .accentColor : .secondary)
                    .font(.caption)
                }
            }

            HStack {
                TextField("Grams", text: $servingText)
                    .keyboardType(.decimalPad)
                    .font(.title3.bold().monospaced())
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Serving size in grams")

                Text("g")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 60)

            if servingText.isEmpty || (Double(servingText) ?? -1) <= 0 {
                Text("Enter a valid serving size")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if food.servingDescription != "100g" {
                Text("1 serving = \(food.servingDescription)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Meal Type

    private var mealTypeSection: some View {
        VStack(spacing: 8) {
            Text("Meal")
                .font(.headline)

            HStack(spacing: 12) {
                ForEach(MealType.allCases, id: \.self) { meal in
                    Button {
                        selectedMealType = meal
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: meal.icon)
                                .font(.title3)
                            Text(meal.displayName)
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selectedMealType == meal
                                ? Color.accentColor.opacity(0.15)
                                : Color(.systemGray6)
                        )
                        .foregroundStyle(
                            selectedMealType == meal ? Color.accentColor : .secondary
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .accessibilityLabel(meal.displayName)
                    .accessibilityAddTraits(selectedMealType == meal ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Add Button

    private var addButton: some View {
        VStack(spacing: 8) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await handleLog() }
            } label: {
                HStack {
                    if isLogging {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Add to Diary")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLogging || servingG <= 0)
            .accessibilityLabel("Add \(food.foodName) to \(selectedMealType.displayName)")
        }
    }

    private func handleLog() async {
        isLogging = true
        defer { isLogging = false }

        let success = await viewModel.logFood(
            food: food,
            servingG: servingG,
            mealType: selectedMealType
        )
        if success {
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        FoodDetailView(
            food: FoodSearchResult(
                foodId: 1,
                foodName: "Chicken Biryani",
                brand: "Homemade",
                source: "local",
                caloriesPer100g: 180,
                proteinPer100g: 12.5,
                fatPer100g: 6.0,
                carbsPer100g: 22.0,
                servingSizeG: 250,
                servingDescription: "1 plate (250g)"
            ),
            viewModel: FoodSearchViewModel(),
            onLogged: {}
        )
    }
}
