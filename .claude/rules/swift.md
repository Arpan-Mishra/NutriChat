# NutriChat iOS — Swift Rules
# .claude/rules/swift.md
#
# Load this file when working in nutrichat-ios/

SwiftUI iOS app. iOS 17.0 minimum. Xcode 16+. Swift 6 (strict concurrency enabled).

---

## Non-Negotiable Claude Code Rules

These seven rules apply in every session, without exception.

---

### Rule 1 — Never touch `.pbxproj`

Claude Code must **never read, write, or suggest edits** to any `.pbxproj` file.

- Claude Code's job is to create and edit `.swift` files only
- Adding a new file to the Xcode project is **always done manually by the developer**:
  File → Add Files to "NutriChat", or drag into the Project Navigator
- One corrupted `.pbxproj` costs hours to recover — this rule is absolute, no exceptions

---

### Rule 2 — Document platform gotchas immediately

The moment a SwiftUI or iOS API behaves unexpectedly, append a row to the
**Platform Gotchas** table at the bottom of this file — before continuing work.

Required columns: date discovered, iOS version, category, one-line description.

This table exists because a single entry like "NO `.background()` before `.glassEffect()`"
can prevent the same mistake from being made 50+ times across sessions.

---

### Rule 3 — Feature-flag all experimental code

Every new or unstable feature must be behind a flag in `Utilities/FeatureFlags.swift`.
No experimental code ships enabled by default.

```swift
// Utilities/FeatureFlags.swift
enum FeatureFlags {
    static let aiQuickLog        = false
    static let newBarcodeScanner = false
    static let voiceLogging      = false
    static let healthKitSync     = false
}

// Usage at the call site
if FeatureFlags.newBarcodeScanner {
    BarcodeScannerV2View()
} else {
    BarcodeScannerView()
}
```

Rolling back at 11 pm = flip one `false`. No git revert, no rebuild required.

---

### Rule 4 — Logger for every complex flow

Any async sequence, camera session, API call chain, auth flow, or multi-step
navigation must have `Logger` calls throughout. Never use `print()`.

```swift
import OSLog

// One logger per file, named after its category
private let logger = Logger(subsystem: "app.nutrichat", category: "BarcodeScanner")

// Use the right level
logger.debug("Camera session starting")
logger.info("Barcode detected: \(code, privacy: .public)")
logger.warning("Food lookup returned 0 results for barcode: \(code, privacy: .public)")
logger.error("AVFoundation setup failed: \(error.localizedDescription, privacy: .public)")
```

`print()` is stripped in release builds and invisible in Console.app.
`Logger` persists across app launches, is filterable by subsystem/category,
and is visible in both Xcode console and Console.app on device.

---

### Rule 5 — Test after every change

After every meaningful code change, before moving to the next task:

1. `Cmd+Shift+K` — clean build folder
2. Build and run on simulator (`Cmd+R`)
3. Exercise the specific changed flow manually
4. Check the Xcode console and debug area for errors or unexpected output

Do not stack multiple changes and test them together.
Issues that compound are much harder to bisect than issues caught immediately.

---

### Rule 6 — One component per task

Scope every Claude Code task to a single file or a single coherent feature slice.

✅ `"Update FoodDetailView to recalculate macros live as the quantity stepper changes"`
❌ `"Refactor all food views to use the new design system"`

Smaller scope → better output → trivial rollback if something goes wrong.

---

### Rule 7 — Session notes at the end of every meaningful session

Before closing any session that makes meaningful changes, create a brief markdown file:

```
docs/session-notes/YYYY-MM-DD-<topic>.md
```

Use this template:

```markdown
## What changed
- `FileName.swift`: one-line description of what was added or modified

## What broke and how it was fixed
- Symptom → root cause → fix applied

## Rollback
- `git revert <sha>`  OR  restore `FileName.swift` from commit <sha>
```

---

## Quick-Start

```bash
# Open project
open nutrichat-ios/NutriChat.xcodeproj

# Build and run on simulator
# Xcode → select "iPhone 16 Pro" → Cmd+R

# Run tests from terminal
xcodebuild test \
  -scheme NutriChat \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

---

## Project Structure

```
NutriChat/
├── App/
│   ├── NutriChatApp.swift           # @main, app-level environment setup
│   └── AppState.swift               # Global @Observable (auth status, active tab)
│
├── Models/                          # Data shapes only — no logic
│   ├── User.swift
│   ├── MealEntry.swift
│   ├── FoodItem.swift
│   └── Goal.swift
│
├── Views/
│   ├── Auth/
│   │   ├── WelcomeView.swift
│   │   ├── PhoneOTPView.swift
│   │   ├── ProfileSetupView.swift
│   │   └── GoalView.swift
│   ├── Dashboard/
│   │   ├── DashboardView.swift
│   │   ├── CalorieRingView.swift    # Custom Shape — no third-party library
│   │   ├── MacroBarView.swift
│   │   └── MealSectionView.swift
│   ├── FoodLog/
│   │   ├── FoodSearchView.swift
│   │   ├── FoodDetailView.swift
│   │   ├── BarcodeScannerView.swift
│   │   └── CustomFoodView.swift
│   └── Profile/
│       ├── ProfileView.swift
│       ├── GoalsView.swift
│       ├── WhatsAppIntegrationView.swift  # ← hero screen
│       └── AccountView.swift
│
├── ViewModels/                      # @Observable — own all async state
│   ├── AuthViewModel.swift
│   ├── DashboardViewModel.swift
│   ├── FoodSearchViewModel.swift
│   └── ProfileViewModel.swift
│
├── Services/                        # Stateless — pure async functions only
│   ├── APIClient.swift              # URLSession wrapper, JWT injection, decoding
│   ├── KeychainService.swift        # Token storage — Keychain only, never UserDefaults
│   ├── AuthService.swift
│   ├── FoodService.swift
│   ├── DiaryService.swift
│   └── APIKeyService.swift
│
├── Utilities/
│   ├── Constants.swift              # API.BASE_URL, API.BOT_PHONE, deep-link scheme
│   ├── FeatureFlags.swift           # All toggles default to false
│   └── Extensions.swift            # Date, Color, View helpers
│
└── NutriChatTests/
    ├── ViewModelTests/
    └── ServiceTests/
```

---

## Architecture: MVVM + @Observable

### Layer contract

| Layer | Owns | Must NOT |
|-------|------|----------|
| View | Declarative layout, user event forwarding | Contain business logic; call APIs directly |
| ViewModel | UI state, async coordination | Import UIKit; hold View references |
| Service | Stateless API / system calls | Hold mutable state; reference ViewModels |
| Model | Data shapes | Contain logic beyond simple computed properties |

### ViewModel pattern — @Observable (iOS 17+)

```swift
// CORRECT — @Observable macro, NOT ObservableObject + @Published
@Observable
final class DashboardViewModel {
    var diary: DiaryDay?
    var isLoading = false
    var errorMessage: String?

    private let diaryService: DiaryServiceProtocol

    init(diaryService: DiaryServiceProtocol = DiaryService.shared) {
        self.diaryService = diaryService
    }

    func fetchToday() async {
        isLoading = true
        defer { isLoading = false }
        do {
            diary = try await diaryService.fetchDay(date: .now)
        } catch {
            errorMessage = error.localizedDescription
            logger.error("fetchToday failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// View: @State owns the ViewModel instance
struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()

    var body: some View {
        content
            .task { await viewModel.fetchToday() }
    }
}
```

### Service pattern — protocol first

```swift
// Protocol enables mocking in unit tests
protocol DiaryServiceProtocol {
    func fetchDay(date: Date) async throws -> DiaryDay
}

final class DiaryService: DiaryServiceProtocol {
    static let shared = DiaryService()
    private init() {}

    func fetchDay(date: Date) async throws -> DiaryDay {
        try await APIClient.shared.request(Endpoint.diaryDay(date: date))
    }
}
```

---

## Code Style

### Naming

| Thing | Convention | Example |
|-------|-----------|---------|
| Types (class, struct, enum, protocol) | `PascalCase` | `DashboardViewModel` |
| Properties, functions, local variables | `camelCase` | `isLoading`, `fetchToday()` |
| Event / action handlers | `handle` prefix | `handleAddButtonTapped()` |
| Boolean properties | `is` / `has` / `can` | `isConnected`, `hasError`, `canSubmit` |
| Async data-fetch functions | `fetch` prefix | `fetchTodayDiary()` |
| File/type-scope constants | `camelCase` (Swift convention) | `static let baseURL` |
| Global constants (`Constants.swift`) | namespaced enum | `API.BASE_URL` |

### Formatting

- Indentation: 4 spaces (Xcode default — do not override)
- Max line length: 120 characters
- Trailing closure syntax where it improves readability
- `///` doc comments on all `public` and `internal` types and functions
- `//` inline comments explain *why*, never *what*
- **Never import `Combine`** — use `async/await` and `@Observable` exclusively

---

## Networking

All HTTP goes through `APIClient.shared.request(_:)`.
No View or ViewModel ever instantiates or calls `URLSession` directly.

```swift
// Generic request — JWT injected automatically from Keychain
func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T

// On 401: attempts silent token refresh once, then throws AuthError.unauthorized
// On network failure: throws APIError.networkUnavailable
```

```swift
enum APIError: LocalizedError {
    case unauthorized           // 401 — call AuthService.logout(), show login screen
    case notFound               // 404
    case serverError(Int)       // 5xx — log at .error and show generic message
    case decodingError(Error)   // JSON shape mismatch — log and investigate
    case networkUnavailable     // show offline banner
}
```

**No silent failures.** Every `catch` block must either surface an error to the user
or log at `.error` level with enough context to reproduce the issue.

---

## Security

| Concern | Rule |
|---------|------|
| JWT access + refresh tokens | Keychain via `KeychainService` — **never** `UserDefaults` |
| API Keys (WhatsApp linking) | Displayed once in UI, never persisted in app storage |
| Camera | `NSCameraUsageDescription` in `Info.plist` — barcode scanning only |
| Deep links | `nutrichat://` URL scheme — validate host before acting on it |

---

## SwiftData

Used **only** for offline caching of diary data. The backend is always source of truth.
Never put business logic inside `@Model` classes.

```swift
@Model final class CachedMealEntry {
    var id: Int
    var foodName: String
    var calories: Double
    var loggedDate: Date
}
```

`@Query` only works inside a `View` — do not use in ViewModels or Services.

---

## WhatsApp Integration Screen

`WhatsAppIntegrationView` is the hero feature. Two distinct UI states:

**Not connected**
1. `POST /api/v1/apikeys` → show raw key once in a selectable `Text` (not editable)
2. Show QR code from backend base64 response
3. Numbered instruction card: Copy key → Open WhatsApp → Send `link <key>`
4. Deep-link button:
   ```swift
   let url = URL(string: "whatsapp://send?phone=\(API.BOT_PHONE)&text=link%20")!
   UIApplication.shared.open(url)
   ```

**Connected**
- Green badge + "Connected" label
- `last_used_at` displayed as relative time ("2 hours ago")
- "Revoke & Relink" → `DELETE /api/v1/apikeys/{id}` → returns to Not Connected state

---

## Barcode Scanner

`BarcodeScannerView` — `AVFoundation` + `Vision` only. No third-party library.
Wrap `AVCaptureViewController` in a `UIViewControllerRepresentable`.
Supported formats: EAN-13, UPC-A, QR.

- `AVCaptureSession.startRunning()` must run on a **background thread**, never on `MainActor`
- On successful scan → `FoodService.shared.fetchByBarcode(code)` → push `FoodDetailView`
- On 404 → action sheet: "Search manually" | "Create custom food"

---

## Custom Calorie Ring

Pure SwiftUI — no Swift Charts, no third-party library.

```swift
struct CalorieRingView: View {
    let consumed: Double
    let goal: Double

    private var progress: Double { min(consumed / max(goal, 1), 1.0) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 16)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut, value: progress)
        }
    }
}
```

---

## Testing

Every Service must expose a protocol so it can be mocked in unit tests.

```swift
final class DashboardViewModelTests: XCTestCase {
    func test_fetchToday_populatesDiary() async throws {
        let mock = MockDiaryService()
        mock.stubbedDay = DiaryDay.fixture()
        let vm = DashboardViewModel(diaryService: mock)

        await vm.fetchToday()

        XCTAssertNotNil(vm.diary)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
    }
}
```

Use `#Preview` with injected mock ViewModels — never placeholder strings or
hardcoded data — so previews reflect realistic content and edge cases.

---

## Accessibility

Every interactive element requires an `.accessibilityLabel`.
Check with Accessibility Inspector before each sprint deliverable.
This is an App Store review requirement.

```swift
Button("Add") { handleAddTapped() }
    .accessibilityLabel("Add food to \(mealType.displayName)")
```

---

## Dark Mode

All colours via Asset Catalog named colours or semantic system colours
(`Color.primary`, `Color.secondary`, `Color.background`).
Never hardcode hex values inline.
Test dark mode with `Cmd+Shift+A` in the simulator before every sprint sign-off.

---

## Git

```bash
# Always run before and after work
git status && git diff --stat

# Standard commit
git add -A
git commit -m "feat(ios): <description>"
git push origin main

# Auto-commit when diff >= 10%
git add -A && git commit -m "chore(ios): auto-commit — diff threshold" && git push origin main
```

Scope for all iOS commits: `(ios)`.

---

## Platform Gotchas

_Append a new row the moment you discover a quirk. Date and iOS version are required.
Never leave a session without updating this table if something unexpected happened._

| Date | iOS | Category | Gotcha |
|------|-----|----------|--------|
| — | 17+ | SwiftUI | `.task` re-fires on every re-render — use `.task(id: value)` to scope re-runs to a specific value change |
| — | 17+ | @Observable | Class must be `final` — non-final + strict concurrency = compiler error |
| — | 17+ | SwiftData | `@Query` only valid inside a `View` — cannot be used in ViewModel or Service |
| — | 17+ | AVFoundation | `AVCaptureSession.startRunning()` must run on a background thread, never on `MainActor` |
| — | 17+ | SwiftUI | `.background()` modifier must come **after** `.glassEffect()`, not before |