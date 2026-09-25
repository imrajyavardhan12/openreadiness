import Foundation

/// A nightly 0–100 sleep score.
///
/// Apple doesn't expose its own sleep score through HealthKit, so this mirrors the structure Apple
/// published for it — duration (50), bedtime consistency (30) and interruptions (20) — using only
/// data older watches record. Stage breakdowns are shown in the UI but deliberately not scored:
/// wrist-based staging is the least accurate part of sleep tracking.
public struct SleepScore: Sendable, Hashable, Codable {
    public var total: Double
    public var duration: Double
    public var consistency: Double
    public var interruptions: Double
    /// Minutes the sleep midpoint differed from your recent typical midpoint, if known.
    public var midpointDeviationMinutes: Double?

    public static let maxDuration = 50.0
    public static let maxConsistency = 30.0
    public static let maxInterruptions = 20.0
}

public struct SleepScorer: Sendable {
    public var goalHours: Double
    public var consistencyNights: Int
    public var calendar: Calendar

    public init(goalHours: Double, consistencyNights: Int, calendar: Calendar) {
        self.goalHours = goalHours
        self.consistencyNights = consistencyNights
        self.calendar = calendar
    }

    /// Scores the night in `days[index]`, using earlier nights for consistency.
    public func score(days: [DayMetrics], index: Int) -> SleepScore? {
        guard let sleep = days[index].sleep else { return nil }

        // Duration: nothing below 3 h, full marks at the goal.
        let hours = sleep.asleep / 3600
        let duration = Stats.interpolate(hours, from: 3, goalHours, to: 0, SleepScore.maxDuration)

        // Consistency: distance of tonight's midpoint from the median of recent midpoints.
        let midpoint = midpointMinutes(sleep, wakeDay: days[index].day)
        let previous = days[max(0, index - consistencyNights)..<index].compactMap { day in
            day.sleep.map { midpointMinutes($0, wakeDay: day.day) }
        }
        var consistency = SleepScore.maxConsistency * 0.67 // neutral until there's history
        var deviation: Double?
        if previous.count >= 3, let typical = Stats.median(previous) {
            let minutes = abs(midpoint - typical)
            deviation = minutes
            consistency = Stats.interpolate(minutes, from: 30, 180, to: SleepScore.maxConsistency, 0)
        }

        // Interruptions: awake time and number of wake-ups after falling asleep.
        let awakeMinutes = sleep.awake / 60
        let byTime = Stats.interpolate(awakeMinutes, from: 10, 60, to: SleepScore.maxInterruptions, 0)
        let byCount = Double(max(0, sleep.interruptions - 2)) * 2
        let interruptions = max(0, byTime - byCount)

        return SleepScore(
            total: duration + consistency + interruptions,
            duration: duration,
            consistency: consistency,
            interruptions: interruptions,
            midpointDeviationMinutes: deviation
        )
    }

    /// Minutes from the wake day's midnight (negative = before midnight).
    private func midpointMinutes(_ sleep: SleepSummary, wakeDay: Date) -> Double {
        sleep.midpoint.timeIntervalSince(calendar.startOfDay(for: wakeDay)) / 60
    }
}
