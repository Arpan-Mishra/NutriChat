import SwiftUI

/// First screen of onboarding — logo, tagline, and "Get Started" button.
struct WelcomeView: View {
    var onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image("NutriChatLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .accessibilityLabel("NutriChat logo")

            VStack(spacing: 12) {
                Text("NutriChat")
                    .font(.largeTitle.bold())

                Text("Track your nutrition, right on WhatsApp")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("Log meals from your iPhone or WhatsApp.\nEverything stays in sync.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }

            Spacer()

            Button(action: onGetStarted) {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .accessibilityLabel("Get started with NutriChat")

            HStack(spacing: 0) {
                Text("By continuing, you agree to our ")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Link("Privacy Policy", destination: URL(string: AppInfo.privacyPolicyURL)!)
                    .font(.caption2)
            }
            .padding(.bottom, 16)
        }
        .padding()
    }
}

#Preview {
    WelcomeView(onGetStarted: {})
}
