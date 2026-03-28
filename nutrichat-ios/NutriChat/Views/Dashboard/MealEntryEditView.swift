import SwiftUI
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "MealEntryEditView")

/// Edit or delete a logged meal entry — serving size, meal type, macros.
struct MealEntryEditView: View {
    let entry: MealEntry
    var onUpdated: () -> Void
    var onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var servingSizeText: String = ""
    @State private var selectedMealType: MealType = .lunch
    @State private var caloriesText: String = ""
    @State private var proteinText: String = ""
    @State private var fatText: String = ""
    @State private var carbsText: String = ""
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false

    private let diaryService: DiaryServiceProtocol

    /// Whether the entry is linked to a food item (macros auto-recompute on backend).
    private var isLinkedToFood: Bool { entry.foodItemId != nil }

    /// Whether any field has been modified from the original entry.
    private var hasChanges: Bool {
        let newServing = Double(servingSizeText) ?? 0
        let originalServing = entry.servingSizeG ?? 0
        let mealChanged = selectedMealType.rawValue != entry.mealType

        if isLinkedToFood {
            return newServing != originalServing || mealChanged
        }

        // Custom food: check macros too
        let calChanged = Double(caloriesText) ?? 0 != entry.calories
        let proChanged = Double(proteinText) ?? 0 != entry.proteinG
        let fatChanged = Double(fatText) ?? 0 != entry.fatG
        let carbChanged = Double(carbsText) ?? 0 != entry.carbsG
        return newServing != originalServing || mealChanged || calChanged || proChanged || fatChanged || carbChanged
    }

    /// Computed macros for linked foods (scales linearly with serving size).
    private var estimatedCalories: Double {
        guard isLinkedToFood, let originalServing = entry.servingSizeG, originalServing > 0 else {
            return Double(caloriesText) ?? entry.calories
        }
        let newServing = Double(servingSizeText) ?? originalServing
        return entry.calories * (newServing / originalServing)
    }

    private var estimatedProtein: Double {
        guard isLinkedToFood, let originalServing = entry.servingSizeG, originalServing > 0 else {
            return Double(proteinText) ?? entry.proteinG
        }
        let newServing = Double(servingSizeText) ?? originalServing
        return entry.proteinG * (newServing / originalServing)
    }

    private var estimatedFat: Double {
        guard isLinkedToFood, let originalServing = entry.servingSizeG, originalServing > 0 else {
            return Double(fatText) ?? entry.fatG
        }
        let newServing = Double(servingSizeText) ?? originalServing
        return entry.fatG * (newServing / originalServing)
    }

    private var estimatedCarbs: Double {
        guard isLinkedToFood, let originalServing = entry.servingSizeG, originalServing > 0 else {
            return Double(carbsText) ?? entry.carbsG
        }
        let newServing = Double(servingSizeText) ?? originalServing
        return entry.carbsG * (newServing / originalServing)
    }

    init(
        entry: MealEntry,
        onUpdated: @escaping () -> Void,
        onDeleted: @escaping () -> Void,
        diaryService: DiaryServiceProtocol = DiaryService.shared
    ) {
        self.entry = entry
        self.onUpdated = onUpdated
        self.onDeleted = onDeleted
        self.diaryService = diaryService
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    nutritionCard
                    servingSection
                    mealTypeSection

                    // Custom food macro editing
                    if !isLinkedToFood {
                        macroEditSection
                    }

                    actionButtons
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { populateFields() }
            .confirmationDialog(
                "Delete Entry",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    Task { await handleDelete() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently remove this entry from your diary.")
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 6) {
            Text(entry.foodDescription ?? "Food item")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Text("Source: \(entry.source)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if isLinkedToFood {
                    Text("Linked to food database")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    // MARK: - Nutrition Card

    private var nutritionCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(estimatedCalories.noDecimal)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                Text("kcal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 0) {
                macroColumn(label: "Protein", value: estimatedProtein, color: .blue)
                Divider().frame(height: 40)
                macroColumn(label: "Carbs", value: estimatedCarbs, color: .orange)
                Divider().frame(height: 40)
                macroColumn(label: "Fat", value: estimatedFat, color: .purple)
            }

            if isLinkedToFood {
                Text("Macros auto-update when you change the serving size")
                    .font(.caption2)
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
                ForEach([50, 100, 150, 200], id: \.self) { grams in
                    Button("\(grams)g") {
                        servingSizeText = "\(grams)"
                    }
                    .buttonStyle(.bordered)
                    .tint(Double(servingSizeText) == Double(grams) ? Color.accentColor : Color.secondary)
                    .font(.caption)
                }
            }

            HStack {
                TextField("Grams", text: $servingSizeText)
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

            if (Double(servingSizeText) ?? 0) <= 0 {
                Text("Enter a valid serving size")
                    .font(.caption)
                    .foregroundStyle(.red)
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

    // MARK: - Custom Macro Editing

    private var macroEditSection: some View {
        VStack(spacing: 12) {
            Text("Nutrition")
                .font(.headline)

            HStack(spacing: 12) {
                macroField(label: "Calories", text: $caloriesText, unit: "kcal")
                macroField(label: "Protein", text: $proteinText, unit: "g")
            }
            HStack(spacing: 12) {
                macroField(label: "Fat", text: $fatText, unit: "g")
                macroField(label: "Carbs", text: $carbsText, unit: "g")
            }
        }
    }

    private func macroField(label: String, text: Binding<String>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(label) (\(unit))")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(label, text: text)
                .keyboardType(.decimalPad)
                .font(.body.monospaced())
                .padding(10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel(label)
        }
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await handleSave() }
            } label: {
                HStack {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Save Changes")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving || isDeleting || !hasChanges || (Double(servingSizeText) ?? 0) <= 0)
            .accessibilityLabel("Save changes to entry")

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    if isDeleting {
                        ProgressView()
                    }
                    Text("Delete Entry")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(isSaving || isDeleting)
            .accessibilityLabel("Delete this entry")
        }
    }

    // MARK: - Logic

    private func populateFields() {
        servingSizeText = entry.servingSizeG?.noDecimal ?? "100"
        selectedMealType = MealType(rawValue: entry.mealType) ?? .lunch
        caloriesText = entry.calories.noDecimal
        proteinText = entry.proteinG.oneDecimal
        fatText = entry.fatG.oneDecimal
        carbsText = entry.carbsG.oneDecimal
    }

    private func handleSave() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        var update = MealEntryUpdate()

        let newServing = Double(servingSizeText) ?? entry.servingSizeG ?? 100
        if newServing != entry.servingSizeG {
            update.servingSizeG = newServing
        }

        if selectedMealType.rawValue != entry.mealType {
            update.mealType = selectedMealType.rawValue
        }

        // For custom foods, send macro overrides
        if !isLinkedToFood {
            let newCal = Double(caloriesText) ?? entry.calories
            let newPro = Double(proteinText) ?? entry.proteinG
            let newFat = Double(fatText) ?? entry.fatG
            let newCarb = Double(carbsText) ?? entry.carbsG
            if newCal != entry.calories { update.calories = newCal }
            if newPro != entry.proteinG { update.proteinG = newPro }
            if newFat != entry.fatG { update.fatG = newFat }
            if newCarb != entry.carbsG { update.carbsG = newCarb }
        }

        do {
            _ = try await diaryService.updateEntry(id: entry.id, update: update)
            logger.info("Updated entry \(entry.id)")
            onUpdated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Failed to update entry: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleDelete() async {
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }

        do {
            try await diaryService.deleteEntry(id: entry.id)
            logger.info("Deleted entry \(entry.id)")
            onDeleted()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Failed to delete entry: \(error.localizedDescription, privacy: .public)")
        }
    }
}

#Preview {
    MealEntryEditView(
        entry: MealEntry(
            id: 1, userId: 1, foodItemId: 42,
            mealType: "lunch", foodDescription: "Chicken Biryani",
            servingSizeG: 300, calories: 540, proteinG: 28,
            fatG: 18, carbsG: 65, fiberG: nil, sodiumMg: nil,
            source: "app", loggedDate: "2026-03-28", loggedAt: "2026-03-28T12:30:00"
        ),
        onUpdated: {},
        onDeleted: {}
    )
}
