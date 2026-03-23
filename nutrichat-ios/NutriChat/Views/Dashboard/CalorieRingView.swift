import SwiftUI

/// Circular progress ring showing calories consumed vs goal.
struct CalorieRingView: View {
    let consumed: Double
    let goal: Double
    let remaining: Double

    private let lineWidth: CGFloat = 18

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(consumed / goal, 1.0)
    }

    private var isOverGoal: Bool {
        consumed > goal && goal > 0
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: lineWidth)

            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    isOverGoal ? Color.red : Color.accentColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)

            // Center text
            VStack(spacing: 4) {
                Text(consumed.noDecimal)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(isOverGoal ? .red : .primary)

                Text("of \(goal.noDecimal) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: remaining >= 0 ? "arrow.down" : "exclamationmark.triangle")
                        .font(.caption2)
                    Text(remaining >= 0
                        ? "\(remaining.noDecimal) left"
                        : "\(abs(remaining).noDecimal) over"
                    )
                    .font(.caption.bold())
                }
                .foregroundColor(remaining >= 0 ? Color.secondary : Color.red)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(consumed.noDecimal) of \(goal.noDecimal) calories consumed. \(remaining >= 0 ? "\(remaining.noDecimal) remaining" : "\(abs(remaining).noDecimal) over goal")")
    }
}

#Preview {
    VStack(spacing: 40) {
        CalorieRingView(consumed: 1450, goal: 2000, remaining: 550)
            .frame(width: 200, height: 200)

        CalorieRingView(consumed: 2300, goal: 2000, remaining: -300)
            .frame(width: 200, height: 200)
    }
    .padding()
}
