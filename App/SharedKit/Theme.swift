import ReadinessCore
import SwiftUI

// System colours adapt to dark mode and Increase Contrast automatically. Every colour
// cue in the app is paired with text or an icon, so nothing relies on colour alone.

extension ReadinessCategory {
    var color: Color {
        switch self {
        case .recover: .red
        case .paceYourself: .orange
        case .ready: .green
        case .goForIt: .cyan
        }
    }

    var systemImage: String {
        switch self {
        case .recover: "bed.double.fill"
        case .paceYourself: "tortoise.fill"
        case .ready: "checkmark.circle.fill"
        case .goForIt: "bolt.fill"
        }
    }
}

extension ContributorStatus {
    var color: Color {
        switch self {
        case .poor: .red
        case .caution: .orange
        case .neutral: .blue
        case .good: .green
        }
    }
}

extension SleepStage {
    var color: Color {
        switch self {
        case .awake: .orange
        case .rem: .cyan
        case .core: .blue
        case .deep: .indigo
        case .asleepUnspecified: .teal
        case .inBed: .gray
        }
    }

    var label: String {
        switch self {
        case .awake: "Awake"
        case .rem: "REM"
        case .core: "Core"
        case .deep: "Deep"
        case .asleepUnspecified: "Asleep"
        case .inBed: "In Bed"
        }
    }
}

extension Date {
    /// "Today", "Yesterday" or "Mon 22 Sep".
    var relativeDayName: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return String(localized: "Today") }
        if calendar.isDateInYesterday(self) { return String(localized: "Yesterday") }
        return formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}
