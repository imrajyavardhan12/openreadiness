import HealthInsights
import ReadinessCore
import SwiftUI

extension HealthMetric {
    /// "8,214 steps", "52 ms", "7.4 km".
    func formatted(_ value: Double, includeUnit: Bool = true) -> String {
        let number = Format.number(value, digits: fractionDigits)
        guard includeUnit else { return number }
        return unit == "%" ? "\(number)%" : "\(number) \(unit)"
    }

    var tint: Color { category.tint }

    /// Whether a change of `delta` is good, bad or neither for this metric.
    func tone(forChange delta: Double) -> Color {
        guard let higherIsBetter, abs(delta) > 0 else { return .secondary }
        return (delta > 0) == higherIsBetter ? .green : .orange
    }
}

extension MetricCategory {
    var tint: Color {
        switch self {
        case .heart: .red
        case .activity: .orange
        case .respiratory: .teal
        case .mobility: .indigo
        case .environment: .yellow
        }
    }
}

extension ReferenceBand.Tone {
    var color: Color {
        switch self {
        case .good: .green
        case .neutral: .gray
        case .caution: .orange
        }
    }
}

extension ExplorerRange {
    /// Human description of the visible dates, e.g. "12–18 Sep 2026".
    func dateSpan(endingAt end: Date = .now) -> String {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: end))!
        return (start..<end).formatted(.interval.day().month(.abbreviated).year())
    }
}
