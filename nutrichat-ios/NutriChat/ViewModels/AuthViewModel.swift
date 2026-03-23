import Foundation
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "AuthViewModel")

/// Onboarding navigation path destinations.
enum OnboardingStep: Hashable {
    case phoneOTP
    case profileSetup
    case goalConfirmation
}

/// Manages the entire onboarding flow: phone → OTP → profile → goal.
@Observable
final class AuthViewModel {

    // MARK: - Phone + OTP

    var countryCode = "+91"
    var phoneNumber = ""
    var otpDigits: [String] = Array(repeating: "", count: 6)
    var isRequestingOTP = false
    var isVerifyingOTP = false
    var otpErrorMessage: String?
    var resendCountdown = 0
    /// Debug OTP returned by dev backend — shown in UI only during development.
    var debugOTP: String?

    // MARK: - Profile Setup

    var displayName = ""
    var dateOfBirth = Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
    var sex = "male"
    var heightCm = ""
    var weightKg = ""
    var activityLevel = "moderate"
    var goalType = "maintain"
    var isSubmittingProfile = false
    var profileErrorMessage: String?

    // MARK: - Goal Confirmation

    var tdeeResponse: TDEEResponse?
    var customCalorieGoal = ""
    var isFetchingTDEE = false
    var isConfirmingGoal = false
    var goalErrorMessage: String?

    // MARK: - General

    var isLoading: Bool {
        isRequestingOTP || isVerifyingOTP || isSubmittingProfile || isFetchingTDEE || isConfirmingGoal
    }

    private let authService: AuthServiceProtocol
    private var resendTimer: Timer?

    init(authService: AuthServiceProtocol = AuthService.shared) {
        self.authService = authService
    }

    // MARK: - Computed

    var fullPhoneNumber: String {
        "\(countryCode)\(phoneNumber)"
    }

    var otpCode: String {
        otpDigits.joined()
    }

    var canRequestOTP: Bool {
        phoneNumber.count >= 10 && !isRequestingOTP
    }

    var canVerifyOTP: Bool {
        otpCode.count == 6 && !isVerifyingOTP
    }

    var canSubmitProfile: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
            && !heightCm.isEmpty
            && !weightKg.isEmpty
            && !isSubmittingProfile
    }

    // MARK: - OTP Actions

    /// Request an OTP for the entered phone number.
    func requestOTP() async {
        guard canRequestOTP else { return }
        isRequestingOTP = true
        otpErrorMessage = nil

        do {
            let response = try await authService.requestOTP(phoneNumber: fullPhoneNumber)
            debugOTP = response.otpDebug
            logger.info("OTP requested successfully")
            startResendCountdown()
        } catch {
            otpErrorMessage = (error as? APIError)?.errorDescription ?? "Failed to send OTP"
            logger.error("OTP request failed: \(error.localizedDescription, privacy: .public)")
        }

        isRequestingOTP = false
    }

    /// Verify the 6-digit OTP code.
    func verifyOTP() async -> Bool {
        guard canVerifyOTP else { return false }
        isVerifyingOTP = true
        otpErrorMessage = nil

        do {
            _ = try await authService.verifyOTP(phoneNumber: fullPhoneNumber, code: otpCode)
            logger.info("OTP verified successfully")
            stopResendTimer()
            isVerifyingOTP = false
            return true
        } catch {
            otpErrorMessage = (error as? APIError)?.errorDescription ?? "Invalid OTP. Please try again."
            logger.error("OTP verification failed: \(error.localizedDescription, privacy: .public)")
            isVerifyingOTP = false
            return false
        }
    }

    /// Reset OTP fields for a fresh attempt.
    func resetOTP() {
        otpDigits = Array(repeating: "", count: 6)
        otpErrorMessage = nil
        debugOTP = nil
    }

    // MARK: - Profile Actions

    /// Submit profile fields to PATCH /users/me.
    func submitProfile() async -> Bool {
        guard canSubmitProfile else { return false }
        isSubmittingProfile = true
        profileErrorMessage = nil

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let fields: [String: Any] = [
            "display_name": displayName.trimmingCharacters(in: .whitespaces),
            "date_of_birth": formatter.string(from: dateOfBirth),
            "sex": sex,
            "height_cm": Double(heightCm) ?? 0,
            "weight_kg": Double(weightKg) ?? 0,
            "activity_level": activityLevel,
            "goal_type": goalType,
        ]

        do {
            let _: User = try await APIClient.shared.request(.updateProfile(fields))
            logger.info("Profile submitted successfully")
            isSubmittingProfile = false
            return true
        } catch {
            profileErrorMessage = (error as? APIError)?.errorDescription ?? "Failed to save profile"
            logger.error("Profile submit failed: \(error.localizedDescription, privacy: .public)")
            isSubmittingProfile = false
            return false
        }
    }

    // MARK: - TDEE / Goal Actions

    /// Fetch TDEE from backend after profile is submitted.
    func fetchTDEE() async {
        isFetchingTDEE = true
        goalErrorMessage = nil

        do {
            tdeeResponse = try await APIClient.shared.request(.tdee)
            customCalorieGoal = "\(tdeeResponse?.recommendedCalories ?? 2000)"
            logger.info("TDEE fetched: \(self.tdeeResponse?.tdee.noDecimal ?? "?", privacy: .public) kcal/day")
        } catch {
            goalErrorMessage = (error as? APIError)?.errorDescription ?? "Failed to calculate TDEE"
            logger.error("TDEE fetch failed: \(error.localizedDescription, privacy: .public)")
        }

        isFetchingTDEE = false
    }

    /// Confirm the calorie goal (custom or recommended) and complete onboarding.
    func confirmGoal() async -> Bool {
        isConfirmingGoal = true
        goalErrorMessage = nil

        guard let calories = Int(customCalorieGoal), calories >= 1200, calories <= 10000 else {
            goalErrorMessage = "Please enter a goal between 1,200 and 10,000 kcal"
            isConfirmingGoal = false
            return false
        }

        let fields: [String: Any] = ["daily_calorie_goal": calories]

        do {
            let _: User = try await APIClient.shared.request(.updateProfile(fields))
            logger.info("Calorie goal confirmed: \(calories)")
            isConfirmingGoal = false
            return true
        } catch {
            goalErrorMessage = (error as? APIError)?.errorDescription ?? "Failed to save goal"
            logger.error("Goal confirm failed: \(error.localizedDescription, privacy: .public)")
            isConfirmingGoal = false
            return false
        }
    }

    // MARK: - Resend Timer

    private func startResendCountdown() {
        resendCountdown = 60
        stopResendTimer()
        resendTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            if self.resendCountdown > 0 {
                self.resendCountdown -= 1
            } else {
                timer.invalidate()
            }
        }
    }

    private func stopResendTimer() {
        resendTimer?.invalidate()
        resendTimer = nil
    }

    deinit {
        stopResendTimer()
    }
}

// MARK: - Picker Options

extension AuthViewModel {
    static let sexOptions = ["male", "female", "other"]

    static let activityLevels: [(id: String, label: String, description: String)] = [
        ("sedentary", "Sedentary", "Little or no exercise"),
        ("light", "Lightly Active", "Light exercise 1-3 days/week"),
        ("moderate", "Moderately Active", "Moderate exercise 3-5 days/week"),
        ("active", "Active", "Hard exercise 6-7 days/week"),
        ("very_active", "Very Active", "Physical job or training 2x daily"),
    ]

    static let goalTypes: [(id: String, label: String, description: String)] = [
        ("lose", "Lose Weight", "500 kcal/day deficit"),
        ("maintain", "Maintain Weight", "Match your TDEE"),
        ("gain", "Gain Weight", "300 kcal/day surplus"),
    ]

    static let countryCodes = ["+91", "+1", "+44", "+61", "+971", "+65", "+86"]
}
