import SwiftUI
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "App")

@main
struct NutriChatApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .task {
                    appState.checkAuthStatus()
                    if appState.isAuthenticated {
                        await appState.loadCurrentUser()
                    }
                }
        }
    }
}

/// Root view that switches between onboarding and the main tab view.
struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isAuthenticated {
                MainTabView()
            } else {
                WelcomePlaceholderView()
            }
        }
        .animation(.easeInOut, value: appState.isAuthenticated)
    }
}

/// Temporary placeholder for the main tab view — replaced in Sprint 9.
struct MainTabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        TabView(selection: $state.activeTab) {
            Tab("Today", systemImage: "chart.pie", value: .today) {
                Text("Dashboard — Sprint 9")
            }
            Tab("Log", systemImage: "plus.circle", value: .logFood) {
                Text("Food Search — Sprint 10")
            }
            Tab("Profile", systemImage: "person", value: .profile) {
                Text("Profile — Sprint 12")
            }
        }
    }
}

/// Temporary placeholder for the welcome/onboarding flow — replaced in Sprint 8.
struct WelcomePlaceholderView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.accent)

            Text("NutriChat")
                .font(.largeTitle.bold())

            Text("Track calories. Chat to log.")
                .font(.title3)
                .foregroundStyle(.secondary)

            Button("Debug: Simulate Login") {
                // Temporary — remove when real auth is built in Sprint 8
                appState.isAuthenticated = true
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 40)
        }
        .padding()
    }
}
