import SwiftUI

/// First screen of onboarding — logo, tagline, and "Get Started" button.
struct WelcomeView: View {
    var onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 100))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 12) {
                Text("NutriChat")
                    .font(.largeTitle.bold())

                Text("Track calories. Chat to log.")
                    .font(.title3)
                    .foregroundStyle(.secondary)

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

            Text("By continuing, you agree to our Privacy Policy")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
        .padding()
    }
}

#Preview {
    WelcomeView(onGetStarted: {})
}
