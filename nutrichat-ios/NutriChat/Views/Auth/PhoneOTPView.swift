import SwiftUI
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "PhoneOTPView")

/// Phone number entry + 6-digit OTP verification.
struct PhoneOTPView: View {
    @Bindable var viewModel: AuthViewModel
    var onVerified: () -> Void

    @State private var showOTPSection = false
    @State private var otpText = ""
    @FocusState private var isOTPFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                headerSection
                phoneSection

                if showOTPSection {
                    otpSection
                }

                if let error = viewModel.otpErrorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                // Debug OTP display (dev only)
                if let debugOTP = viewModel.debugOTP {
                    Text("Debug OTP: \(debugOTP)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.orange)
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(24)
        }
        .navigationTitle("Sign In")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "phone.badge.checkmark")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("Enter your phone number")
                .font(.title3.bold())

            Text("We'll send a 6-digit code to verify your identity")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var phoneSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                // Country code picker
                Menu {
                    ForEach(AuthViewModel.countryCodes, id: \.self) { code in
                        Button(code) {
                            viewModel.countryCode = code
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.countryCode)
                            .font(.body.monospaced())
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityLabel("Country code \(viewModel.countryCode)")

                // Phone number field
                TextField("Phone number", text: $viewModel.phoneNumber)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .font(.body.monospaced())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Phone number")
            }

            // Send OTP button
            Button {
                Task {
                    await viewModel.requestOTP()
                    if viewModel.otpErrorMessage == nil {
                        withAnimation { showOTPSection = true }
                        isOTPFieldFocused = true
                    }
                }
            } label: {
                HStack {
                    if viewModel.isRequestingOTP {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(showOTPSection ? "Resend Code" : "Send Code")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canRequestOTP || (showOTPSection && viewModel.resendCountdown > 0))
            .accessibilityLabel(showOTPSection ? "Resend verification code" : "Send verification code")

            if showOTPSection && viewModel.resendCountdown > 0 {
                Text("Resend in \(viewModel.resendCountdown)s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var otpSection: some View {
        VStack(spacing: 20) {
            Text("Enter verification code")
                .font(.headline)

            // Single hidden TextField captures all input; display boxes are visual only
            ZStack {
                // Hidden input field
                TextField("", text: $otpText)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .focused($isOTPFieldFocused)
                    .onChange(of: otpText) { _, newValue in
                        let filtered = String(newValue.filter(\.isNumber).prefix(6))
                        if filtered != newValue {
                            otpText = filtered
                        }
                        // Sync to viewModel
                        for i in 0..<6 {
                            viewModel.otpDigits[i] = i < filtered.count
                                ? String(filtered[filtered.index(filtered.startIndex, offsetBy: i)])
                                : ""
                        }
                    }

                // Visual digit boxes
                HStack(spacing: 10) {
                    ForEach(0..<6, id: \.self) { index in
                        let hasDigit = index < otpText.count
                        let digit = hasDigit
                            ? String(otpText[otpText.index(otpText.startIndex, offsetBy: index)])
                            : ""

                        Text(digit)
                            .font(.title2.bold().monospaced())
                            .frame(width: 48, height: 56)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(
                                        index == otpText.count && isOTPFieldFocused
                                            ? Color.accentColor
                                            : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isOTPFieldFocused = true
                }
            }
            .accessibilityLabel("6-digit verification code")

            // Verify button
            Button {
                Task {
                    let success = await viewModel.verifyOTP()
                    if success {
                        onVerified()
                    }
                }
            } label: {
                HStack {
                    if viewModel.isVerifyingOTP {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Verify")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canVerifyOTP)
            .accessibilityLabel("Verify code")
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

#Preview {
    NavigationStack {
        PhoneOTPView(viewModel: AuthViewModel(), onVerified: {})
    }
}
