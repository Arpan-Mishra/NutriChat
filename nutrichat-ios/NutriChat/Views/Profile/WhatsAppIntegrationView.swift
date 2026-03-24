import SwiftUI
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "WhatsAppIntegration")

/// Hero screen — connect/disconnect the WhatsApp bot via API keys.
struct WhatsAppIntegrationView: View {
    @Bindable var viewModel: ProfileViewModel

    @State private var showRevokeConfirmation = false
    @State private var keyToRevoke: Int?
    @State private var hasCopiedKey = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if viewModel.isWhatsAppConnected {
                    connectedState
                } else {
                    notConnectedState
                }
            }
            .padding()
        }
        .navigationTitle("WhatsApp Bot")
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
            Text("The WhatsApp bot will lose access to your account. You can generate a new key to reconnect.")
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

    // MARK: - Not Connected

    private var notConnectedState: some View {
        VStack(spacing: 20) {
            // Illustration
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .padding(.top, 8)

            Text("Connect WhatsApp Bot")
                .font(.title2.bold())

            Text("Log meals by texting our WhatsApp bot — everything syncs here automatically.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Show generated key if we just created one
            if let generated = viewModel.generatedKey {
                generatedKeyCard(key: generated.apiKey)
                instructionsCard
                openWhatsAppButton
            } else {
                // Generate button
                Button {
                    Task { await viewModel.generateAPIKey() }
                } label: {
                    Label("Generate API Key", systemImage: "key.fill")
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
            }
        }
    }

    private func generatedKeyCard(key: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your API Key", systemImage: "key.fill")
                .font(.headline)

            Text("This key is shown only once. Copy it now!")
                .font(.caption)
                .foregroundStyle(.orange)

            // Selectable key text
            HStack {
                Text(key)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button {
                    UIPasteboard.general.string = key
                    hasCopiedKey = true
                    logger.info("API key copied to clipboard")
                } label: {
                    Image(systemName: hasCopiedKey ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(hasCopiedKey ? .green : .tint)
                }
                .accessibilityLabel(hasCopiedKey ? "Copied" : "Copy API key")
            }
        }
        .cardStyle()
    }

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to connect")
                .font(.headline)

            instructionRow(number: 1, text: "Copy your API key above")
            instructionRow(number: 2, text: "Open WhatsApp and message the bot")
            instructionRow(number: 3, text: "Send: link <your_key>")
            instructionRow(number: 4, text: "The bot will confirm the connection")
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

    private var openWhatsAppButton: some View {
        Button {
            handleOpenWhatsApp()
        } label: {
            Label("Open WhatsApp", systemImage: "arrow.up.right.square")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Open WhatsApp to message the bot")
    }

    // MARK: - Connected

    private var connectedState: some View {
        VStack(spacing: 20) {
            // Connected badge
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)

                Text("Connected")
                    .font(.title2.bold())

                Text("Your WhatsApp bot is linked to this account.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)

            // Active key details
            if let key = viewModel.activeKey {
                VStack(alignment: .leading, spacing: 12) {
                    Label("API Key", systemImage: "key.fill")
                        .font(.headline)

                    detailRow(label: "Key", value: "\(key.keyPrefix)...")
                    detailRow(label: "Label", value: key.label)
                    detailRow(label: "Created", value: formatTimestamp(key.createdAt))

                    if let lastUsed = key.lastUsedAt {
                        detailRow(label: "Last used", value: formatTimestamp(lastUsed))
                    } else {
                        detailRow(label: "Last used", value: "Never")
                    }
                }
                .cardStyle()

                // Revoke button
                Button(role: .destructive) {
                    keyToRevoke = key.id
                    showRevokeConfirmation = true
                } label: {
                    Label("Revoke & Relink", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Revoke API key and disconnect WhatsApp bot")
            }
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

    private func handleOpenWhatsApp() {
        let botPhone = API.botPhone
        guard botPhone != "YOUR_BOT_PHONE_NUMBER" else {
            viewModel.errorMessage = "Bot phone number not configured."
            return
        }
        let keyText = viewModel.generatedKey?.apiKey ?? ""
        let encoded = "link \(keyText)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
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
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: timestamp) {
            return date.relativeString
        }
        return timestamp
    }
}
