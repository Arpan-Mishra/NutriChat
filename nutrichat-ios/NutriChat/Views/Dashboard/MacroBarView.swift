import SwiftUI

/// Horizontal progress bar for a single macro (protein, carbs, or fat).
struct MacroBarView: View {
    let label: String
    let consumed: Double
    let goal: Double
    let color: Color

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(consumed / goal, 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(goal > 0
                    ? "\(consumed.noDecimal) / \(goal.noDecimal)g"
                    : "\(consumed.noDecimal)g"
                )
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.15))
                        .frame(height: 8)

                    // Filled portion
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * progress, height: 8)
                        .animation(.easeOut(duration: 0.4), value: progress)
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(consumed.noDecimal) of \(goal.noDecimal) grams")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

#Preview {
    VStack(spacing: 20) {
        MacroBarView(label: "Protein", consumed: 85, goal: 150, color: .blue)
        MacroBarView(label: "Carbs", consumed: 200, goal: 250, color: .orange)
        MacroBarView(label: "Fat", consumed: 60, goal: 65, color: .purple)
    }
    .padding()
}
