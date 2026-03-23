import Foundation
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "AppState")

/// Global app state shared across the entire app via the environment.
@Observable
final class AppState {
    /// Whether the user is authenticated (has valid tokens).
    var isAuthenticated = false

    /// Whether the user needs to complete profile setup after first login.
    var needsProfileSetup = false

    /// The currently active tab in the main tab view.
    var activeTab: AppTab = .today

    /// The current user profile (loaded after authentication).
    var currentUser: User?

    /// Global error message shown as an alert.
    var errorMessage: String?

    /// Check authentication status on app launch.
    func checkAuthStatus() {
        isAuthenticated = AuthService.shared.isAuthenticated
        logger.info("Auth status: \(self.isAuthenticated ? "authenticated" : "not authenticated")")
    }

    /// Load the current user profile from the API.
    /// Returns true if profile is complete, false if onboarding is needed.
    @discardableResult
    func loadCurrentUser() async -> Bool {
        do {
            let user: User = try await APIClient.shared.request(.me)
            currentUser = user
            logger.info("User profile loaded: \(user.displayName ?? "unnamed", privacy: .public)")

            let profileComplete = user.isProfileComplete
            needsProfileSetup = !profileComplete
            return profileComplete
        } catch {
            logger.error("Failed to load user profile: \(error.localizedDescription, privacy: .public)")
            if let apiError = error as? APIError, case .unauthorized = apiError {
                isAuthenticated = false
            }
            return false
        }
    }

    /// Called after successful OTP verification.
    func handleLoginSuccess() async {
        isAuthenticated = true
        let profileComplete = await loadCurrentUser()
        needsProfileSetup = !profileComplete
        logger.info("Login success, profile complete: \(profileComplete)")
    }

    /// Called after profile setup + goal confirmation.
    func handleOnboardingComplete() {
        needsProfileSetup = false
        logger.info("Onboarding complete")
    }

    /// Sign out and reset state.
    func signOut() {
        AuthService.shared.logout()
        isAuthenticated = false
        needsProfileSetup = false
        currentUser = nil
        activeTab = .today
        logger.info("User signed out, state reset")
    }
}

/// Main app tabs.
enum AppTab: Hashable {
    case today
    case logFood
    case profile
}
