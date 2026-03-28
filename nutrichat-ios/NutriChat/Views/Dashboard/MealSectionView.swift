import SwiftUI

/// A collapsible meal section showing entries and an "Add" button.
struct MealSectionView: View {
    let mealType: MealType
    let entries: [MealEntry]
    let totalCalories: Double
    var onAdd: () -> Void
    var onEdit: ((MealEntry) -> Void)?
    var onDelete: ((MealEntry) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack {
                Image(systemName: mealType.icon)
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)

                Text(mealType.displayName)
                    .font(.headline)

                Spacer()

                Text("\(totalCalories.noDecimal) kcal")
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)

                Button {
                    onAdd()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
                .accessibilityLabel("Add food to \(mealType.displayName)")
            }
            .padding(.horizontal)
            .padding(.vertical, 12)

            // Entries list
            if entries.isEmpty {
                Text("No items logged")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 12)
            } else {
                ForEach(entries) { entry in
                    mealEntryRow(entry)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func mealEntryRow(_ entry: MealEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.foodDescription ?? "Food item")
                    .font(.subheadline)
                    .lineLimit(1)

                if let serving = entry.servingSizeG {
                    Text("\(serving.noDecimal)g")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("\(entry.calories.noDecimal)")
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)

            Text("kcal")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit?(entry)
        }
        .contextMenu {
            if let onEdit {
                Button {
                    onEdit(entry)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
            if let onDelete {
                Button(role: .destructive) {
                    onDelete(entry)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.foodDescription ?? "Food item"), \(entry.servingSizeG?.noDecimal ?? "")g, \(entry.calories.noDecimal) calories")
        .accessibilityHint("Tap to edit")
    }
}

#Preview {
    VStack(spacing: 12) {
        MealSectionView(
            mealType: .breakfast,
            entries: [],
            totalCalories: 0,
            onAdd: {}
        )

        MealSectionView(
            mealType: .lunch,
            entries: [
                MealEntry(
                    id: 1, userId: 1, foodItemId: nil,
                    mealType: "lunch", foodDescription: "Chicken Biryani",
                    servingSizeG: 300, calories: 540, proteinG: 28,
                    fatG: 18, carbsG: 65, fiberG: nil, sodiumMg: nil,
                    source: "app", loggedDate: "2026-03-23", loggedAt: "2026-03-23T12:30:00"
                ),
            ],
            totalCalories: 540,
            onAdd: {}
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
