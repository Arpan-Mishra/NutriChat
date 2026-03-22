import Foundation
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "AppState")

/// Global app state shared across the entire app via the environment.
@Observable
final class AppState {
    /// Whether the user is authenticated (has valid tokens).
    var isAuthenticated = false

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
    func loadCurrentUser() async {
        do {
            currentUser = try await APIClient.shared.request(.me)
            logger.info("User profile loaded: \(self.currentUser?.displayName ?? "unnamed", privacy: .public)")
        } catch {
            logger.error("Failed to load user profile: \(error.localizedDescription, privacy: .public)")
            if error is APIError {
                let apiError = error as! APIError
                if case .unauthorized = apiError {
                    isAuthenticated = false
                }
            }
        }
    }

    /// Sign out and reset state.
    func signOut() {
        AuthService.shared.logout()
        isAuthenticated = false
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
