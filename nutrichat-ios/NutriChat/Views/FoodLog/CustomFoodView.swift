import SwiftUI
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "CustomFoodView")

/// Manual food entry — name, calories, macros, serving size, meal type.
struct CustomFoodView: View {
    @Bindable var viewModel: FoodSearchViewModel
    var onLogged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var fatText = ""
    @State private var carbsText = ""
    @State private var servingText = "100"
    @State private var selectedMealType: MealType = .lunch
    @State private var isLogging = false
    @State private var showValidation = false

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (Double(caloriesText) ?? -1) >= 0
    }

    var body: some View {
        Form {
            Section("Food") {
                HStack(spacing: 0) {
                    TextField("Name", text: $name)
                        .autocorrectionDisabled()
                    requiredMark(isEmpty: name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Nutrition") {
                macroField(label: "Calories", text: $caloriesText, unit: "kcal", required: true)
                macroField(label: "Protein", text: $proteinText, unit: "g")
                macroField(label: "Carbs", text: $carbsText, unit: "g")
                macroField(label: "Fat", text: $fatText, unit: "g")
            }

            Section("Serving") {
                HStack {
                    Text("Size")
                    Spacer()
                    TextField("g", text: $servingText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("g")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Meal") {
                Picker("Meal Type", selection: $selectedMealType) {
                    ForEach(MealType.allCases, id: \.self) { meal in
                        Text(meal.displayName).tag(meal)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    if !canSubmit {
                        withAnimation { showValidation = true }
                        return
                    }
                    Task { await handleLog() }
                } label: {
                    HStack {
                        Spacer()
                        if isLogging {
                            ProgressView()
                        } else {
                            Text("Add to Diary")
                                .font(.headline)
                        }
                        Spacer()
                    }
                }
                .accessibilityLabel("Add custom food to diary")
            }
        }
        .navigationTitle("Custom Food")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedMealType = viewModel.selectedMealType
        }
    }

    // MARK: - Helpers

    private func requiredMark(isEmpty: Bool) -> some View {
        Group {
            if showValidation && isEmpty {
                Text(" *")
                    .foregroundStyle(.red)
                    .fontWeight(.bold)
            }
        }
    }

    private func macroField(label: String, text: Binding<String>, unit: String, required: Bool = false) -> some View {
        HStack {
            HStack(spacing: 0) {
                Text(label)
                if required {
                    requiredMark(isEmpty: text.wrappedValue.isEmpty)
                }
            }
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 35, alignment: .leading)
        }
    }

    private func handleLog() async {
        isLogging = true
        defer { isLogging = false }

        let success = await viewModel.logCustomFood(
            name: name.trimmingCharacters(in: .whitespaces),
            calories: Double(caloriesText) ?? 0,
            proteinG: Double(proteinText) ?? 0,
            fatG: Double(fatText) ?? 0,
            carbsG: Double(carbsText) ?? 0,
            servingG: Double(servingText) ?? 100,
            mealType: selectedMealType
        )
        if success {
            onLogged()
        }
    }
}

#Preview {
    NavigationStack {
        CustomFoodView(viewModel: FoodSearchViewModel(), onLogged: {})
    }
}
