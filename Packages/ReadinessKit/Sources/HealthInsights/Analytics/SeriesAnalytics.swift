import Foundation
import ReadinessCore

public struct PeriodComparison: Sendable, Hashable {
    public var current: Double
    public var previous: Double
    public var currentCount: Int
    public var previousCount: Int

    public var delta: Double { current - previous }
    public var percentChange: Double? { previous != 0 ? (current / previous - 1) * 100 : nil }
}

public struct WeekdayStat: Sendable, Hashable, Identifiable {
    /// 1 = Sunday … 7 = Saturday (Calendar convention).
    public var weekday: Int
    public var mean: Double
    public var count: Int
    public var id: Int { weekday }
}

public struct HistogramBin: Sendable, Hashable, Identifiable {
    public var lower: Double
    public var upper: Double
    public var count: Int
    public var id: Double { lower }
    public var midpoint: Double { (lower + upper) / 2 }
}

public struct Streak: Sendable, Hashable {
    public var start: Date
    public var end: Date
    public var length: Int
}

public struct Records: Sendable, Hashable {
    public var highest: DailyValue
    public var lowest: DailyValue
    public var mean: Double
    public var count: Int
}

public struct BandPoint: Sendable, Hashable, Identifiable {
    public var date: Date
    public var low: Double
    public var median: Double
    public var high: Double
    public var id: Date { date }
}

/// Descriptive analytics over a daily series. All functions are pure and calendar-explicit.
public enum SeriesAnalytics {
    /// Groups daily values into weeks or months. Sums become *average daily totals* for the
    /// period (so a partial week is comparable to a full one); ranges keep the true min and max.
    public static func bucketed(
        _ values: [DailyValue],
        by component: Calendar.Component,
        aggregation: Aggregation,
        calendar: Calendar
    ) -> [DailyValue] {
        guard component != .day else { return values }
        let groups = Dictionary(grouping: values) { calendar.dateInterval(of: component, for: $0.date)?.start ?? $0.date }
        return groups.map { start, items in
            DailyValue(
                date: start,
                value: Stats.mean(items.map(\.value)) ?? 0,
                min: aggregation == .range ? items.compactMap(\.min).min() : nil,
                max: aggregation == .range ? items.compactMap(\.max).max() : nil
            )
        }
        .sorted { $0.date < $1.date }
    }

    /// Daily values from hourly buckets: the day's value is the mean of its hourly means (a
    /// time-weighted average), with the true minimum and maximum.
    ///
    /// Heart rate is sampled every few seconds during workouts but only every few minutes otherwise,
    /// so a plain mean of samples is dominated by workouts. Averaging hours first fixes that.
    public static func dailyFromHourly(_ hourly: [DailyValue], calendar: Calendar) -> [DailyValue] {
        Dictionary(grouping: hourly) { calendar.startOfDay(for: $0.date) }
            .map { day, hours in
                DailyValue(
                    date: day,
                    value: Stats.mean(hours.map(\.value)) ?? 0,
                    min: hours.compactMap(\.min).min(),
                    max: hours.compactMap(\.max).max()
                )
            }
            .sorted { $0.date < $1.date }
    }

    /// Trailing mean over `window` calendar days, emitted only where at least half the window has data.
    public static func rollingMean(_ values: [DailyValue], window: Int, calendar: Calendar) -> [TimedValue] {
        let byDay = Dictionary(values.map { (calendar.startOfDay(for: $0.date), $0.value) }, uniquingKeysWith: { a, _ in a })
        return values.compactMap { item in
            let day = calendar.startOfDay(for: item.date)
            let windowValues = (0..<window).compactMap { offset in
                calendar.date(byAdding: .day, value: -offset, to: day).flatMap { byDay[$0] }
            }
            guard windowValues.count * 2 >= window, let mean = Stats.mean(windowValues) else { return nil }
            return TimedValue(date: item.date, value: mean)
        }
    }

    /// Mean over the most recent `days` versus the `days` before that, ending at `end`.
    public static func comparePeriods(_ values: [DailyValue], days: Int, endingAt end: Date, calendar: Calendar) -> PeriodComparison? {
        let endDay = calendar.startOfDay(for: end)
        guard let currentStart = calendar.date(byAdding: .day, value: -(days - 1), to: endDay),
              let previousStart = calendar.date(byAdding: .day, value: -days, to: currentStart)
        else { return nil }
        let current = values.filter { $0.date >= currentStart && $0.date <= endDay }.map(\.value)
        let previous = values.filter { $0.date >= previousStart && $0.date < currentStart }.map(\.value)
        guard let currentMean = Stats.mean(current), let previousMean = Stats.mean(previous) else { return nil }
        return PeriodComparison(current: currentMean, previous: previousMean, currentCount: current.count, previousCount: previous.count)
    }

    /// Mean by day of the week, ordered from the calendar's first weekday.
    public static func weekdayProfile(_ values: [DailyValue], calendar: Calendar) -> [WeekdayStat] {
        let groups = Dictionary(grouping: values) { calendar.component(.weekday, from: $0.date) }
        return (0..<7).compactMap { offset in
            let weekday = (calendar.firstWeekday - 1 + offset) % 7 + 1
            guard let items = groups[weekday], let mean = Stats.mean(items.map(\.value)) else { return nil }
            return WeekdayStat(weekday: weekday, mean: mean, count: items.count)
        }
    }

    /// Equal-width histogram with a "nice" bin width (1, 2, 2.5 or 5 × 10ⁿ).
    public static func histogram(_ values: [Double], targetBins: Int = 12) -> [HistogramBin] {
        guard let low = values.min(), let high = values.max() else { return [] }
        guard high > low else { return [HistogramBin(lower: low, upper: low + 1, count: values.count)] }
        let width = niceStep((high - low) / Double(max(targetBins, 1)))
        let start = (low / width).rounded(.down) * width
        let binCount = Int(((high - start) / width).rounded(.down)) + 1
        var counts = Array(repeating: 0, count: binCount)
        for value in values {
            counts[min(binCount - 1, Int((value - start) / width))] += 1
        }
        return counts.enumerated().map { index, count in
            HistogramBin(lower: start + Double(index) * width, upper: start + Double(index + 1) * width, count: count)
        }
    }

    static func niceStep(_ raw: Double) -> Double {
        guard raw > 0 else { return 1 }
        let magnitude = pow(10, (log10(raw)).rounded(.down))
        let fraction = raw / magnitude
        let nice: Double = switch fraction {
        case ..<1.5: 1
        case ..<2.25: 2
        case ..<3.5: 2.5
        case ..<7.5: 5
        default: 10
        }
        return nice * magnitude
    }

    public static func records(_ values: [DailyValue]) -> Records? {
        guard let highest = values.max(by: { $0.value < $1.value }),
              let lowest = values.min(by: { $0.value < $1.value }),
              let mean = Stats.mean(values.map(\.value))
        else { return nil }
        return Records(highest: highest, lowest: lowest, mean: mean, count: values.count)
    }

    /// Longest and current (ending today or yesterday) runs of consecutive days meeting `condition`.
    public static func streaks(
        _ values: [DailyValue],
        today: Date,
        calendar: Calendar,
        where condition: (Double) -> Bool
    ) -> (longest: Streak?, current: Streak?) {
        let hits = Set(values.filter { condition($0.value) }.map { calendar.startOfDay(for: $0.date) })
        var longest: Streak?
        var run: Streak?
        for day in hits.sorted() {
            if let current = run, let next = calendar.date(byAdding: .day, value: 1, to: current.end), next == day {
                run = Streak(start: current.start, end: day, length: current.length + 1)
            } else {
                run = Streak(start: day, end: day, length: 1)
            }
            if let run, run.length > (longest?.length ?? 0) { longest = run }
        }
        let todayStart = calendar.startOfDay(for: today)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let current = run.flatMap { $0.end == todayStart || $0.end == yesterday ? $0 : nil }
        return (longest, current)
    }

    /// Least-squares change across the series, in value units (first → last day).
    public static func trendChange(_ values: [DailyValue]) -> Double? {
        guard values.count >= 5, let first = values.first?.date else { return nil }
        let xs = values.map { $0.date.timeIntervalSince(first) / 86_400 }
        let ys = values.map(\.value)
        guard let xMean = Stats.mean(xs), let yMean = Stats.mean(ys) else { return nil }
        let denominator = xs.reduce(0) { $0 + ($1 - xMean) * ($1 - xMean) }
        guard denominator > 0 else { return nil }
        let slope = zip(xs, ys).reduce(0) { $0 + ($1.0 - xMean) * ($1.1 - yMean) } / denominator
        return slope * (xs.last! - xs.first!)
    }

    /// Your personal normal range for each day: median ± robust spread of the preceding `window` days.
    public static func normalBand(
        _ values: [DailyValue],
        window: Int = 60,
        minimumCount: Int = 7,
        calendar: Calendar
    ) -> [BandPoint] {
        let sorted = values.sorted { $0.date < $1.date }
        var result: [BandPoint] = []
        var lower = 0
        for (index, item) in sorted.enumerated() {
            guard let windowStart = calendar.date(byAdding: .day, value: -window, to: item.date) else { continue }
            while lower < index, sorted[lower].date < windowStart { lower += 1 }
            let history = sorted[lower..<index].map(\.value)
            let floor = max(abs(Stats.median(history) ?? 0) * 0.02, 1e-6)
            guard let baseline = Baseline.robust(history, minimumCount: minimumCount, minimumSpread: floor) else { continue }
            result.append(BandPoint(date: item.date, low: baseline.median - baseline.spread, median: baseline.median, high: baseline.median + baseline.spread))
        }
        return result
    }
}
