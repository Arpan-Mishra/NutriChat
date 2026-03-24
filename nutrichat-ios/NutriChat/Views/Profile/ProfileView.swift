import SwiftUI
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "ProfileView")

/// Profile tab — user info, quick stats, navigation to settings screens.
struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = ProfileViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                userHeader
                statsSection
                navigationSection
            }
            .padding()
        }
        .navigationTitle("Profile")
        .task {
            await viewModel.loadProfile()
            await viewModel.fetchWeeklyStats()
            await viewModel.fetchAPIKeys()
        }
        .refreshable {
            await viewModel.loadProfile()
            await viewModel.fetchWeeklyStats()
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

    // MARK: - User Header

    private var userHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text(viewModel.user?.displayName ?? "—")
                .font(.title2.bold())

            Text(viewModel.user?.phoneNumber ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let goalType = viewModel.user?.goalType {
                Text(goalLabel(for: goalType))
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(.tint.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Week")
                .font(.headline)

            if viewModel.isLoadingStats {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if let stats = viewModel.weeklyStats {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 12) {
                    statCard(value: "\(stats.daysLogged)", label: "Days Logged")
                    statCard(value: stats.avgCalories.noDecimal, label: "Avg Calories")
                    statCard(value: "\(stats.totalEntries)", label: "Entries")
                }
            } else {
                Text("No data yet — start logging meals!")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .cardStyle()
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Navigation Section

    private var navigationSection: some View {
        VStack(spacing: 2) {
            NavigationLink {
                GoalsView(viewModel: viewModel)
            } label: {
                navRow(icon: "target", title: "Goals", subtitle: calorieGoalSubtitle)
            }

            Divider().padding(.leading, 44)

            NavigationLink {
                WhatsAppIntegrationView(viewModel: viewModel)
            } label: {
                navRow(
                    icon: "bubble.left.and.text.bubble.right",
                    title: "WhatsApp Bot",
                    subtitle: viewModel.isWhatsAppConnected ? "Connected" : "Not connected",
                    badgeColor: viewModel.isWhatsAppConnected ? .green : nil
                )
            }

            Divider().padding(.leading, 44)

            NavigationLink {
                AccountView()
            } label: {
                navRow(icon: "gearshape", title: "Account", subtitle: nil)
            }
        }
        .cardStyle()
    }

    private func navRow(icon: String, title: String, subtitle: String?, badgeColor: Color? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                if let subtitle {
                    HStack(spacing: 4) {
                        if let color = badgeColor {
                            Circle()
                                .fill(color)
                                .frame(width: 8, height: 8)
                        }
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityLabel("\(title), \(subtitle ?? "")")
    }

    // MARK: - Helpers

    private var calorieGoalSubtitle: String {
        if let goal = viewModel.user?.dailyCalorieGoal {
            return "\(goal.noDecimal) kcal/day"
        }
        return "Not set"
    }

    private func goalLabel(for type: String) -> String {
        switch type {
        case "lose": return "Losing weight"
        case "maintain": return "Maintaining weight"
        case "gain": return "Gaining weight"
        default: return type.capitalized
        }
    }
}
