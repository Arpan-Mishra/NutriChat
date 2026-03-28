import SwiftUI
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "WhatsAppIntegration")

/// Hero screen — connect/disconnect NutriBot (WhatsApp) via API keys.
///
/// Three states:
/// 1. **Not connected** — no active key. Show "Generate API Key" button.
/// 2. **Linking in progress** — key generated but `last_used_at` is nil (NutriBot hasn't used it yet).
///    Show key, copy button, instructions, and "Open WhatsApp" button.
/// 3. **Connected** — key exists and `last_used_at` is set (NutriBot has used the key).
///    Show green badge, key details, and revoke button.
struct WhatsAppIntegrationView: View {
    @Bindable var viewModel: ProfileViewModel

    @State private var showRevokeConfirmation = false
    @State private var keyToRevoke: Int?
    @State private var hasCopiedKey = false

    /// Current connection state derived from API key status.
    private var connectionState: ConnectionState {
        if let generated = viewModel.generatedKey {
            // Just generated — always show linking state with the raw key
            return .linking(rawKey: generated.apiKey)
        }
        if let key = viewModel.activeKey {
            if key.lastUsedAt != nil {
                return .connected(key)
            } else {
                // Key exists but bot hasn't used it yet
                return .linking(rawKey: nil)
            }
        }
        return .notConnected
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                switch connectionState {
                case .notConnected:
                    notConnectedState
                case .linking(let rawKey):
                    linkingState(rawKey: rawKey)
                case .connected(let key):
                    connectedState(key: key)
                }
            }
            .padding()
        }
        .navigationTitle("NutriBot")
        .task {
            await viewModel.fetchAPIKeys()
        }
        .alert("Revoke API Key?", isPresented: $showRevokeConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Revoke", role: .destructive) {
                if let id = keyToRevoke {
                    Task { await viewModel.revokeAPIKey(id: id) }
                }
            }
        } message: {
            Text("NutriBot will lose access to your account. You can generate a new key to reconnect.")
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

    // MARK: - State 1: Not Connected

    private var notConnectedState: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .padding(.top, 8)

            Text("Connect NutriBot")
                .font(.title2.bold())

            Text("Log meals by texting NutriBot on WhatsApp — everything syncs here automatically.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await viewModel.generateAPIKey()
                    // Auto-open WhatsApp after key is generated
                    if viewModel.generatedKey != nil {
                        openWhatsApp(with: viewModel.generatedKey?.apiKey)
                    }
                }
            } label: {
                Label("Connect WhatsApp", systemImage: "key.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isGeneratingKey)
            .overlay {
                if viewModel.isGeneratingKey {
                    ProgressView()
                }
            }
            .accessibilityLabel("Generate API key and open WhatsApp")
        }
    }

    // MARK: - State 2: Linking In Progress

    private func linkingState(rawKey: String?) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
                .padding(.top, 8)

            Text("Linking in Progress")
                .font(.title2.bold())

            Text("Send the message below to NutriBot on WhatsApp to complete the connection.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Show the raw key if we have it (just generated)
            if let key = rawKey {
                apiKeyCard(key: key)
            }

            instructionsCard

            // Open WhatsApp button
            Button {
                openWhatsApp(with: rawKey)
            } label: {
                Label("Open WhatsApp", systemImage: "arrow.up.right.square")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .accessibilityLabel("Open WhatsApp to send the link command")

            // Refresh status
            Button {
                Task { await viewModel.fetchAPIKeys() }
            } label: {
                Label("Check Connection Status", systemImage: "arrow.clockwise")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Refresh connection status")

            // Revoke option
            if let key = viewModel.activeKey {
                Button(role: .destructive) {
                    keyToRevoke = key.id
                    showRevokeConfirmation = true
                } label: {
                    Text("Cancel & Start Over")
                        .font(.caption)
                }
                .padding(.top, 4)
            }
        }
    }

    private func apiKeyCard(key: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your API Key", systemImage: "key.fill")
                .font(.headline)

            Text("Tap to copy. This key is shown only once.")
                .font(.caption)
                .foregroundStyle(.orange)

            // Tappable key — copies on tap
            Button {
                UIPasteboard.general.string = key
                hasCopiedKey = true
                logger.info("API key copied to clipboard")
            } label: {
                HStack {
                    Text(key)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Spacer()

                    Image(systemName: hasCopiedKey ? "checkmark.circle.fill" : "doc.on.doc")
                        .foregroundStyle(hasCopiedKey ? Color.green : Color.accentColor)
                        .font(.title3)
                }
                .padding(12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .accessibilityLabel(hasCopiedKey ? "API key copied" : "Tap to copy API key")

            if hasCopiedKey {
                Text("Copied to clipboard!")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .cardStyle()
    }

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to connect")
                .font(.headline)

            instructionRow(number: 1, text: "Tap \"Open WhatsApp\" below")
            instructionRow(number: 2, text: "Send the pre-filled message to NutriBot")
            instructionRow(number: 3, text: "NutriBot will confirm the connection")
            instructionRow(number: 4, text: "Come back here and tap \"Check Connection Status\"")
        }
        .cardStyle()
    }

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.tint)
                .clipShape(Circle())

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(text)")
    }

    // MARK: - State 3: Connected

    private func connectedState(key: APIKeyResponse) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)

                Text("Connected")
                    .font(.title2.bold())

                Text("NutriBot is linked and active.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 12) {
                Label("API Key", systemImage: "key.fill")
                    .font(.headline)

                detailRow(label: "Key", value: "\(key.keyPrefix)...")
                detailRow(label: "Label", value: key.label)
                detailRow(label: "Created", value: formatTimestamp(key.createdAt))

                if let lastUsed = key.lastUsedAt {
                    detailRow(label: "Last used", value: formatTimestamp(lastUsed))
                }
            }
            .cardStyle()

            Button(role: .destructive) {
                keyToRevoke = key.id
                showRevokeConfirmation = true
            } label: {
                Label("Revoke & Relink", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Revoke API key and disconnect NutriBot")
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Helpers

    private func openWhatsApp(with key: String?) {
        let botPhone = API.botPhone
        guard botPhone != "YOUR_BOT_PHONE_NUMBER" else {
            viewModel.errorMessage = "NutriBot phone number not configured."
            return
        }
        let keyText = key ?? viewModel.activeKey?.keyPrefix ?? ""
        let message = "link \(keyText)"
        let encoded = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "whatsapp://send?phone=\(botPhone)&text=\(encoded)") {
            UIApplication.shared.open(url)
            logger.info("Opening WhatsApp deep link")
        }
    }

    private func formatTimestamp(_ timestamp: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: timestamp) {
            return date.relativeString
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: timestamp) {
            return date.relativeString
        }
        return timestamp
    }
}

// MARK: - Connection State

private enum ConnectionState {
    case notConnected
    case linking(rawKey: String?)
    case connected(APIKeyResponse)
}
