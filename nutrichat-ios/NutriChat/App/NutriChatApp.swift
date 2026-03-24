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

/// Root view that switches between onboarding, profile setup, and the main tab view.
struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isAuthenticated && !appState.needsProfileSetup {
                MainTabView()
            } else if appState.isAuthenticated && appState.needsProfileSetup {
                OnboardingProfileFlow()
            } else {
                OnboardingAuthFlow()
            }
        }
        .animation(.easeInOut, value: appState.isAuthenticated)
        .animation(.easeInOut, value: appState.needsProfileSetup)
    }
}

// MARK: - Onboarding Auth Flow (Welcome → Phone/OTP)

/// Handles Welcome → Phone/OTP → triggers profile setup or main app.
struct OnboardingAuthFlow: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = AuthViewModel()
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView {
                path.append(OnboardingStep.phoneOTP)
            }
            .navigationDestination(for: OnboardingStep.self) { step in
                switch step {
                case .phoneOTP:
                    PhoneOTPView(viewModel: viewModel) {
                        handleOTPVerified()
                    }
                case .profileSetup, .goalConfirmation:
                    EmptyView()
                }
            }
        }
    }

    private func handleOTPVerified() {
        Task {
            await appState.handleLoginSuccess()
        }
    }
}

// MARK: - Onboarding Profile Flow (ProfileSetup → Goal)

/// Handles ProfileSetup → GoalConfirmation for newly registered or incomplete-profile users.
struct OnboardingProfileFlow: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = AuthViewModel()
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ProfileSetupView(viewModel: viewModel) {
                path.append(OnboardingStep.goalConfirmation)
            }
            .navigationDestination(for: OnboardingStep.self) { step in
                switch step {
                case .goalConfirmation:
                    GoalView(viewModel: viewModel) {
                        handleGoalConfirmed()
                    }
                case .phoneOTP, .profileSetup:
                    EmptyView()
                }
            }
        }
    }

    private func handleGoalConfirmed() {
        Task {
            await appState.loadCurrentUser()
            appState.handleOnboardingComplete()
        }
    }
}

// MARK: - Main Tab View

/// Main tab view — Summary (dashboard), Log (food search), Profile.
struct MainTabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        TabView(selection: $state.activeTab) {
            Tab("Summary", systemImage: "chart.pie", value: .today) {
                DashboardView()
            }
            Tab("Log", systemImage: "plus.circle", value: .logFood) {
                LogTabView()
            }
            Tab("Profile", systemImage: "person", value: .profile) {
                NavigationStack {
                    ProfileView()
                }
            }
        }
    }
}

// MARK: - Log Tab View

/// Log tab — wraps FoodSearchView in its own NavigationStack.
struct LogTabView: View {
    @State private var viewModel = FoodSearchViewModel()

    var body: some View {
        NavigationStack {
            FoodSearchView(viewModel: viewModel)
        }
    }
}
