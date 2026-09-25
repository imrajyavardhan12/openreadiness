import Foundation
import ReadinessCore

public struct SleepScheduleNight: Sendable, Hashable, Identifiable {
    /// The wake day.
    public var day: Date
    /// Minutes relative to midnight of the wake day; negative means the evening before.
    public var sleepStart: Double
    public var wake: Double
    public var asleepHours: Double
    public var isWeekendNight: Bool

    public var id: Date { day }
    public var midpoint: Double { (sleepStart + wake) / 2 }
}

/// How regular your sleep timing is. Irregular timing is associated with poorer health outcomes
/// independent of duration (e.g. Windred et al., SLEEP 2024), which Apple Health barely surfaces.
public struct SleepScheduleAnalysis: Sendable, Hashable {
    public var nights: [SleepScheduleNight]
    public var medianStart: Double
    public var medianWake: Double
    /// Robust spread of sleep onset, in minutes.
    public var startVariability: Double
    public var wakeVariability: Double
    /// Weekend midpoint minus weekday midpoint, in minutes ("social jetlag").
    public var socialJetlag: Double?

    public var regularityLabel: String {
        switch max(startVariability, wakeVariability) {
        case ..<30: "Very regular"
        case ..<60: "Fairly regular"
        case ..<90: "Irregular"
        default: "Very irregular"
        }
    }

    public static func analyze(_ days: [DayMetrics], calendar: Calendar) -> SleepScheduleAnalysis? {
        let nights = days.compactMap { day -> SleepScheduleNight? in
            guard let sleep = day.sleep else { return nil }
            let midnight = calendar.startOfDay(for: day.day)
            // The night of Friday→Saturday and Saturday→Sunday: wake day is Saturday or Sunday.
            let wakeWeekday = calendar.component(.weekday, from: day.day)
            return SleepScheduleNight(
                day: day.day,
                sleepStart: sleep.start.timeIntervalSince(midnight) / 60,
                wake: sleep.end.timeIntervalSince(midnight) / 60,
                asleepHours: sleep.asleep / 3600,
                isWeekendNight: wakeWeekday == 7 || wakeWeekday == 1
            )
        }
        guard nights.count >= 3,
              let medianStart = Stats.median(nights.map(\.sleepStart)),
              let medianWake = Stats.median(nights.map(\.wake)),
              let startMAD = Stats.mad(nights.map(\.sleepStart)),
              let wakeMAD = Stats.mad(nights.map(\.wake))
        else { return nil }

        let weekend = nights.filter(\.isWeekendNight).map(\.midpoint)
        let weekday = nights.filter { !$0.isWeekendNight }.map(\.midpoint)
        let jetlag: Double? = if let we = Stats.mean(weekend), let wd = Stats.mean(weekday), weekend.count >= 2, weekday.count >= 3 {
            we - wd
        } else {
            nil
        }

        return SleepScheduleAnalysis(
            nights: nights,
            medianStart: medianStart,
            medianWake: medianWake,
            startVariability: startMAD * 1.4826,
            wakeVariability: wakeMAD * 1.4826,
            socialJetlag: jetlag
        )
    }
}

/// Five heart-rate zones based on heart-rate reserve (Karvonen), the method Apple uses by default.
public struct HeartRateZones: Sendable, Hashable {
    public var resting: Double
    public var maximum: Double

    public init(resting: Double, maximum: Double) {
        self.resting = resting
        self.maximum = maximum
    }

    public static let reserveFractions: [Double] = [0.5, 0.6, 0.7, 0.8, 0.9]
    public static let names = ["Easy", "Moderate", "Aerobic", "Threshold", "Maximum"]

    /// Lower bpm bound of zones 1–5.
    public var lowerBounds: [Double] {
        Self.reserveFractions.map { resting + $0 * (maximum - resting) }
    }

    /// Zone index 0–4 for a heart rate (anything below zone 1 counts as zone 1).
    public func zone(for bpm: Double) -> Int {
        max(0, (lowerBounds.lastIndex { bpm >= $0 }) ?? 0)
    }

    /// Seconds in each zone. Each sample counts until the next one, capped so gaps (e.g. a paused
    /// workout) aren't attributed to a zone.
    public func timeInZones(_ samples: [TimedValue], until end: Date, maximumGap: TimeInterval = 60) -> [TimeInterval] {
        var totals = Array(repeating: 0.0, count: 5)
        let sorted = samples.sorted { $0.date < $1.date }
        for (index, sample) in sorted.enumerated() {
            let next = index + 1 < sorted.count ? sorted[index + 1].date : end
            let span = min(max(0, next.timeIntervalSince(sample.date)), maximumGap)
            totals[zone(for: sample.value)] += span
        }
        return totals
    }
}
