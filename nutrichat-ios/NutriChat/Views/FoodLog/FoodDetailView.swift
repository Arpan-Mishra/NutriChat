import SwiftUI
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "FoodDetailView")

/// Food detail screen — nutrition facts, serving/unit picker, meal type picker, "Add to Diary".
struct FoodDetailView: View {
    let food: FoodSearchResult
    @Bindable var viewModel: FoodSearchViewModel
    var onLogged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var quantityText: String = "1"
    @State private var selectedServing: ServingOption = .customGrams
    @State private var customGramsText: String = ""
    @State private var selectedMealType: MealType = .lunch
    @State private var isLogging = false

    /// All available serving options for this food.
    private var servingOptions: [ServingOption] {
        var options: [ServingOption] = []

        // Add servings from API
        if let servings = food.servings {
            for serving in servings {
                options.append(.foodServing(serving))
            }
        }

        // Always add "Custom (g)" as last option
        options.append(.customGrams)
        return options
    }

    /// The effective serving size in grams based on selection and quantity.
    private var servingG: Double {
        let qty = Double(quantityText) ?? 1
        switch selectedServing {
        case .foodServing(let serving):
            return serving.servingSizeG * qty
        case .customGrams:
            return Double(customGramsText) ?? food.servingSizeG
        }
    }

    /// The unit string to send to the backend (nil for custom grams).
    private var servingUnit: String? {
        switch selectedServing {
        case .foodServing:
            return "serving"
        case .customGrams:
            return "g"
        }
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
            selectedMealType = viewModel.selectedMealType
            customGramsText = food.servingSizeG.noDecimal
            // Select the default serving if available
            if let servings = food.servings, let defaultServing = servings.first(where: { $0.isDefault }) {
                selectedServing = .foodServing(defaultServing)
            } else if let servings = food.servings, let first = servings.first {
                selectedServing = .foodServing(first)
            } else {
                selectedServing = .customGrams
            }
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

            // Serving picker — only show if there are actual servings from the API
            if let servings = food.servings, !servings.isEmpty {
                servingPicker
            }

            // Quantity or gram input
            switch selectedServing {
            case .foodServing(let serving):
                // Show quantity multiplier for named servings
                HStack {
                    Text("Quantity:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("1", text: $quantityText)
                        .keyboardType(.decimalPad)
                        .font(.title3.bold().monospaced())
                        .multilineTextAlignment(.center)
                        .frame(width: 60)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("Quantity")

                    Text("× \(serving.servingDescription)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.horizontal, 16)

                // Show gram equivalent
                Text("= \(servingG.noDecimal)g")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

            case .customGrams:
                // Direct gram input with quick presets
                HStack(spacing: 12) {
                    ForEach([50, 100, 150, 200], id: \.self) { grams in
                        Button("\(grams)g") {
                            customGramsText = "\(grams)"
                        }
                        .buttonStyle(.bordered)
                        .tint(servingG == Double(grams) ? Color.accentColor : Color.secondary)
                        .font(.caption)
                    }
                }

                HStack {
                    TextField("Grams", text: $customGramsText)
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
            }

            if servingG <= 0 {
                Text("Enter a valid serving size")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var servingPicker: some View {
        Picker("Serving", selection: $selectedServing) {
            ForEach(servingOptions) { option in
                Text(option.displayName)
                    .tag(option)
            }
        }
        .pickerStyle(.menu)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("Select serving size")
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

        let qty = Double(quantityText) ?? 1
        let success = await viewModel.logFood(
            food: food,
            servingG: servingG,
            mealType: selectedMealType,
            servingUnit: servingUnit,
            servingQuantity: selectedServing.isCustomGrams ? nil : qty
        )
        if success {
            dismiss()
        }
    }
}

// MARK: - Serving Option

/// Represents either a named serving (from API) or custom gram input.
enum ServingOption: Identifiable, Hashable {
    case foodServing(FoodServing)
    case customGrams

    var id: String {
        switch self {
        case .foodServing(let s): "serving_\(s.id)"
        case .customGrams: "custom_grams"
        }
    }

    var displayName: String {
        switch self {
        case .foodServing(let s): "\(s.servingDescription) (\(s.servingSizeG.noDecimal)g)"
        case .customGrams: "Custom (g)"
        }
    }

    var isCustomGrams: Bool {
        if case .customGrams = self { return true }
        return false
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
                servingDescription: "1 plate (250g)",
                servings: [
                    FoodServing(id: 1, servingDescription: "1 plate", servingSizeG: 250, isDefault: true),
                    FoodServing(id: 2, servingDescription: "1 cup", servingSizeG: 200, isDefault: false),
                ]
            ),
            viewModel: FoodSearchViewModel(),
            onLogged: {}
        )
    }
}
