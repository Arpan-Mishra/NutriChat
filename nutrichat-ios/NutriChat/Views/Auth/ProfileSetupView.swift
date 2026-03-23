import SwiftUI
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "ProfileSetupView")

/// Profile setup form: name, DOB, sex, height, weight, activity level, goal type.
struct ProfileSetupView: View {
    @Bindable var viewModel: AuthViewModel
    var onProfileSubmitted: () -> Void

    /// Toggled on first submit attempt — shows red asterisks on empty required fields.
    @State private var showValidation = false

    var body: some View {
        Form {
            personalSection
            bodySection
            activitySection
            goalSection
            submitSection
        }
        .navigationTitle("Your Profile")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Helpers

    /// Red asterisk shown next to empty mandatory fields after first submit attempt.
    private func requiredMark(isEmpty: Bool) -> some View {
        Group {
            if showValidation && isEmpty {
                Text(" *")
                    .foregroundStyle(.red)
                    .fontWeight(.bold)
            }
        }
    }

    // MARK: - Sections

    private var personalSection: some View {
        Section {
            HStack(spacing: 0) {
                TextField("Display Name", text: $viewModel.displayName)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Display name, required")
                requiredMark(isEmpty: viewModel.displayName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            DatePicker(
                "Date of Birth",
                selection: $viewModel.dateOfBirth,
                in: ...Date.now,
                displayedComponents: .date
            )
            .accessibilityLabel("Date of birth")

            Picker("Sex", selection: $viewModel.sex) {
                ForEach(AuthViewModel.sexOptions, id: \.self) { option in
                    Text(option.capitalized).tag(option)
                }
            }
            .accessibilityLabel("Biological sex")
        } header: {
            Text("Personal Info")
        }
    }

    private var bodySection: some View {
        Section {
            HStack {
                HStack(spacing: 0) {
                    Text("Height")
                    requiredMark(isEmpty: viewModel.heightCm.isEmpty)
                }
                Spacer()
                TextField("cm", text: $viewModel.heightCm)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .accessibilityLabel("Height in centimeters, required")
                Text("cm")
                    .foregroundStyle(.secondary)
            }

            HStack {
                HStack(spacing: 0) {
                    Text("Weight")
                    requiredMark(isEmpty: viewModel.weightKg.isEmpty)
                }
                Spacer()
                TextField("kg", text: $viewModel.weightKg)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .accessibilityLabel("Weight in kilograms, required")
                Text("kg")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Body Measurements")
        }
    }

    private var activitySection: some View {
        Section {
            ForEach(AuthViewModel.activityLevels, id: \.id) { level in
                Button {
                    viewModel.activityLevel = level.id
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(level.label)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(level.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if viewModel.activityLevel == level.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .accessibilityLabel("\(level.label): \(level.description)")
                .accessibilityAddTraits(viewModel.activityLevel == level.id ? .isSelected : [])
            }
        } header: {
            Text("Activity Level")
        }
    }

    private var goalSection: some View {
        Section {
            ForEach(AuthViewModel.goalTypes, id: \.id) { goal in
                Button {
                    viewModel.goalType = goal.id
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.label)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(goal.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if viewModel.goalType == goal.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .accessibilityLabel("\(goal.label): \(goal.description)")
                .accessibilityAddTraits(viewModel.goalType == goal.id ? .isSelected : [])
            }
        } header: {
            Text("Goal")
        }
    }

    private var submitSection: some View {
        Section {
            if let error = viewModel.profileErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                if !viewModel.canSubmitProfile {
                    withAnimation { showValidation = true }
                    return
                }
                Task {
                    let success = await viewModel.submitProfile()
                    if success {
                        onProfileSubmitted()
                    }
                }
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isSubmittingProfile {
                        ProgressView()
                    }
                    Text("Continue")
                        .font(.headline)
                    Spacer()
                }
            }
            .accessibilityLabel("Continue to set your calorie goal")
        }
    }
}

#Preview {
    NavigationStack {
        ProfileSetupView(viewModel: AuthViewModel(), onProfileSubmitted: {})
    }
}
