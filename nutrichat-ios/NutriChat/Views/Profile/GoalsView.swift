import SwiftUI
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "GoalsView")

/// Edit calorie and macro goals.
struct GoalsView: View {
    @Bindable var viewModel: ProfileViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            calorieSection
            macroSection
            saveSection
        }
        .navigationTitle("Goals")
        .alert("Goals Saved", isPresented: $viewModel.goalsSaved) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your daily goals have been updated.")
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Calorie Section

    private var calorieSection: some View {
        Section {
            HStack {
                Text("Daily Calories")
                Spacer()
                Text("\(Int(viewModel.calorieGoal)) kcal")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Daily calorie goal: \(Int(viewModel.calorieGoal)) kilocalories")

            Slider(
                value: $viewModel.calorieGoal,
                in: 1200...4000,
                step: 50
            )
            .accessibilityLabel("Calorie goal slider")
        } header: {
            Text("Calorie Goal")
        } footer: {
            Text("Recommended: 1,500–2,500 kcal for most adults.")
        }
    }

    // MARK: - Macro Section

    private var macroSection: some View {
        Section {
            macroRow(name: "Protein", value: $viewModel.proteinGoal, range: 30...300, unit: "g")
            macroRow(name: "Carbs", value: $viewModel.carbsGoal, range: 50...500, unit: "g")
            macroRow(name: "Fat", value: $viewModel.fatGoal, range: 20...200, unit: "g")

            HStack {
                Text("Total from macros")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(macroCalories) kcal")
                    .font(.footnote.bold())
                    .foregroundStyle(macroCaloriesDelta == 0 ? Color.primary : Color.orange)
            }
        } header: {
            Text("Macro Goals")
        } footer: {
            if macroCaloriesDelta != 0 {
                Text("Macro total differs from calorie goal by \(abs(macroCaloriesDelta)) kcal.")
            }
        }
    }

    private func macroRow(name: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(name)
                Spacer()
                Text("\(Int(value.wrappedValue)) \(unit)")
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) goal: \(Int(value.wrappedValue)) \(unit)")
    }

    // MARK: - Save Section

    private var saveSection: some View {
        Section {
            Button {
                Task { await viewModel.saveGoals() }
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isSavingGoals {
                        ProgressView()
                    } else {
                        Text("Save Goals")
                            .bold()
                    }
                    Spacer()
                }
            }
            .disabled(viewModel.isSavingGoals)
            .accessibilityLabel("Save goals")
        }
    }

    // MARK: - Computed

    /// Calories from macros: protein 4 kcal/g, carbs 4 kcal/g, fat 9 kcal/g.
    private var macroCalories: Int {
        Int(viewModel.proteinGoal * 4 + viewModel.carbsGoal * 4 + viewModel.fatGoal * 9)
    }

    private var macroCaloriesDelta: Int {
        macroCalories - Int(viewModel.calorieGoal)
    }
}
