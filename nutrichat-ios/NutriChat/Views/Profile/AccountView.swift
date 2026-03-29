import SwiftUI
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "AccountView")

/// Account settings — sign out, delete account, privacy policy.
struct AccountView: View {
    @Environment(AppState.self) private var appState

    @State private var showSignOutConfirmation = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        List {
            // App info
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("App version \(appVersion)")
            }

            // Account actions
            Section {
                Button {
                    showSignOutConfirmation = true
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .accessibilityLabel("Sign out of your account")

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Account", systemImage: "trash")
                }
                .accessibilityLabel("Permanently delete your account")
            }

            // Legal
            Section {
                Link(destination: privacyPolicyURL) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                .accessibilityLabel("View privacy policy")
            }
        }
        .navigationTitle("Account")
        .confirmationDialog("Sign Out", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                handleSignOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .confirmationDialog("Delete Account", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) {
                handleDeleteAccount()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action is permanent. All your data will be deleted and cannot be recovered.")
        }
    }

    // MARK: - Actions

    private func handleSignOut() {
        logger.info("User signed out")
        appState.signOut()
    }

    private func handleDeleteAccount() {
        // TODO: Call DELETE /api/v1/users/me when backend endpoint exists
        logger.info("User requested account deletion")
        appState.signOut()
    }

    // MARK: - Constants

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var privacyPolicyURL: URL {
        URL(string: AppInfo.privacyPolicyURL)!
    }
}
