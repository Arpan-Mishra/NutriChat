import SwiftUI
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "GoalView")

/// Final onboarding screen — shows computed TDEE and lets user confirm or adjust calorie goal.
struct GoalView: View {
    @Bindable var viewModel: AuthViewModel
    var onGoalConfirmed: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                headerSection

                if viewModel.isFetchingTDEE {
                    ProgressView("Calculating your daily needs...")
                        .padding(.top, 40)
                } else if let tdee = viewModel.tdeeResponse {
                    tdeeCard(tdee)
                    goalInputSection(tdee)
                    confirmButton
                } else if let error = viewModel.goalErrorMessage {
                    errorSection(error)
                }
            }
            .padding(24)
        }
        .navigationTitle("Your Goal")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.fetchTDEE()
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "flame.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Your Recommended Calories")
                .font(.title3.bold())

            Text("Based on your profile and goals")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func tdeeCard(_ tdee: TDEEResponse) -> some View {
        VStack(spacing: 16) {
            // Big number
            Text("\(tdee.recommendedCalories)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)

            Text("kcal / day")
                .font(.title3)
                .foregroundStyle(.secondary)

            Divider()

            // Breakdown
            HStack(spacing: 24) {
                tdeeMetric(label: "BMR", value: tdee.bmr.noDecimal)
                tdeeMetric(label: "TDEE", value: tdee.tdee.noDecimal)
                tdeeMetric(label: "Goal", value: goalLabel(for: tdee.goalType))
            }
        }
        .cardStyle()
    }

    private func tdeeMetric(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.monospaced())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func goalInputSection(_ tdee: TDEEResponse) -> some View {
        VStack(spacing: 12) {
            Text("Adjust if you'd like")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                TextField("Calories", text: $viewModel.customCalorieGoal)
                    .keyboardType(.numberPad)
                    .font(.title2.bold().monospaced())
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Daily calorie goal")

                Text("kcal")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 40)

            Button("Reset to recommended") {
                viewModel.customCalorieGoal = "\(tdee.recommendedCalories)"
            }
            .font(.caption)
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel("Reset to recommended \(tdee.recommendedCalories) calories")
        }
    }

    private var confirmButton: some View {
        VStack(spacing: 8) {
            if let error = viewModel.goalErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task {
                    let success = await viewModel.confirmGoal()
                    if success {
                        onGoalConfirmed()
                    }
                }
            } label: {
                HStack {
                    if viewModel.isConfirmingGoal {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Start Tracking")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel("Confirm calorie goal and start tracking")
        }
    }

    private func errorSection(_ error: String) -> some View {
        VStack(spacing: 16) {
            Text(error)
                .font(.body)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)

            Button("Retry") {
                Task { await viewModel.fetchTDEE() }
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 40)
    }

    // MARK: - Helpers

    private func goalLabel(for goalType: String?) -> String {
        switch goalType {
        case "lose": "-500"
        case "gain": "+300"
        default: "0"
        }
    }
}

#Preview {
    NavigationStack {
        GoalView(viewModel: AuthViewModel(), onGoalConfirmed: {})
    }
}
