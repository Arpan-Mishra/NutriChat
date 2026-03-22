import SwiftUI

// MARK: - Date

extension Date {
    /// ISO 8601 date string (yyyy-MM-dd) suitable for API requests.
    var apiDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: self)
    }

    /// Human-readable relative time ("2 hours ago", "Yesterday").
    var relativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: .now)
    }
}

// MARK: - Double

extension Double {
    /// Rounds to one decimal place for display (e.g. 123.4).
    var oneDecimal: String {
        String(format: "%.1f", self)
    }

    /// Rounds to zero decimal places for display (e.g. 123).
    var noDecimal: String {
        String(format: "%.0f", self)
    }
}

// MARK: - View

extension View {
    /// Applies a card-style background with rounded corners and shadow.
    func cardStyle() -> some View {
        self
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
