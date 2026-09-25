import Foundation

/// Turns raw sleep-analysis samples into one `SleepSummary` per night.
public struct SleepAnalyzer: Sendable {
    public var calendar: Calendar
    /// Gaps between asleep segments shorter than this are treated as continuous sleep.
    public var minimumInterruption: TimeInterval = 3 * 60
    /// A night's window opens at this hour the evening before...
    public var windowStartHour = 18
    /// ...and closes at this hour on the wake day. Sleep starting later is treated as a nap.
    public var windowEndHour = 15

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    /// The window in which a main sleep ending on `day` must start.
    public func nightWindow(for day: Date) -> DateInterval {
        let dayStart = calendar.startOfDay(for: day)
        let start = calendar.date(byAdding: .hour, value: windowStartHour - 24, to: dayStart)!
        let end = calendar.date(byAdding: .hour, value: windowEndHour, to: dayStart)!
        return DateInterval(start: start, end: end)
    }

    /// Summarises the night that ended on `day`, or nil if nothing asleep was recorded.
    ///
    /// Several apps and devices may write overlapping sleep data. Rather than merging them (which
    /// double counts), the single source with the most asleep time is used, preferring sources that
    /// record stages (i.e. Apple Watch).
    public func summarize(_ segments: [SleepSegment], wakeDay day: Date) -> SleepSummary? {
        let window = nightWindow(for: day)
        let inWindow = segments.filter { window.contains($0.start) && $0.end > $0.start }
        guard let source = preferredSource(in: inWindow) else { return nil }

        let chosen = inWindow.filter { $0.sourceID == source }.sorted { $0.start < $1.start }
        let asleepSegments = chosen.filter { $0.stage.isAsleep }
        guard let first = asleepSegments.first,
              let lastEnd = asleepSegments.map(\.end).max()
        else { return nil }

        let merged = Self.merge(asleepSegments.map { DateInterval(start: $0.start, end: $0.end) })
        let asleep = merged.reduce(0) { $0 + $1.duration }
        let span = lastEnd.timeIntervalSince(first.start)

        var byStage: [SleepStage: TimeInterval] = [:]
        for stage in [SleepStage.core, .deep, .rem, .asleepUnspecified] {
            let intervals = asleepSegments.filter { $0.stage == stage }.map { DateInterval(start: $0.start, end: $0.end) }
            byStage[stage] = Self.merge(intervals).reduce(0) { $0 + $1.duration }
        }

        // Interruptions: gaps between merged asleep blocks, after bridging tiny gaps.
        var interruptions = 0
        for (previous, next) in zip(merged, merged.dropFirst())
        where next.start.timeIntervalSince(previous.end) >= minimumInterruption {
            interruptions += 1
        }

        return SleepSummary(
            start: first.start,
            end: lastEnd,
            asleep: asleep,
            awake: max(0, span - asleep),
            deep: byStage[.deep] ?? 0,
            rem: byStage[.rem] ?? 0,
            core: byStage[.core] ?? 0,
            unspecified: byStage[.asleepUnspecified] ?? 0,
            interruptions: interruptions,
            segments: chosen.filter { $0.stage != .inBed }
        )
    }

    /// The source whose sleep data should be used when several apps/devices overlap.
    public func preferredSourceID(in segments: [SleepSegment]) -> String? {
        preferredSource(in: segments)
    }

    func preferredSource(in segments: [SleepSegment]) -> String? {
        var asleepBySource: [String: TimeInterval] = [:]
        var stagedSources: Set<String> = []
        for segment in segments where segment.stage.isAsleep {
            asleepBySource[segment.sourceID, default: 0] += segment.duration
            if segment.stage != .asleepUnspecified { stagedSources.insert(segment.sourceID) }
        }
        return asleepBySource.max { lhs, rhs in
            let lhsStaged = stagedSources.contains(lhs.key)
            let rhsStaged = stagedSources.contains(rhs.key)
            if lhsStaged != rhsStaged { return !lhsStaged }
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key > rhs.key // deterministic tie-break
        }?.key
    }

    /// Merges overlapping or touching intervals.
    static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var result: [DateInterval] = []
        for interval in sorted {
            if let last = result.last, interval.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                result.append(interval)
            }
        }
        return result
    }
}
