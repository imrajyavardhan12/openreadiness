import Foundation

/// Metrics that can be charted over time.
public enum MetricKind: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case readiness
    case hrv
    case restingHeartRate
    case sleepDuration
    case sleepScore
    case trainingLoad
    case respiratoryRate
    case wristTemperature
    case oxygenSaturation
    case activeEnergy

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .readiness: "Readiness"
        case .hrv: "HRV"
        case .restingHeartRate: "Resting Heart Rate"
        case .sleepDuration: "Time Asleep"
        case .sleepScore: "Sleep Score"
        case .trainingLoad: "Training Load"
        case .respiratoryRate: "Respiratory Rate"
        case .wristTemperature: "Wrist Temperature"
        case .oxygenSaturation: "Blood Oxygen"
        case .activeEnergy: "Active Energy"
        }
    }

    public var unit: String {
        switch self {
        case .readiness: ""
        case .hrv: "ms"
        case .restingHeartRate: "bpm"
        case .sleepDuration: "h"
        case .sleepScore: ""
        case .trainingLoad: "load"
        case .respiratoryRate: "br/min"
        case .wristTemperature: "°C"
        case .oxygenSaturation: "%"
        case .activeEnergy: "kcal"
        }
    }

    public var fractionDigits: Int {
        switch self {
        case .sleepDuration, .respiratoryRate: 1
        case .wristTemperature: 2
        default: 0
        }
    }

    public var systemImage: String {
        switch self {
        case .readiness: "gauge.with.dots.needle.67percent"
        case .hrv: "waveform.path.ecg"
        case .restingHeartRate: "heart"
        case .sleepDuration: "bed.double"
        case .sleepScore: "moon.stars"
        case .trainingLoad: "figure.run"
        case .respiratoryRate: "lungs"
        case .wristTemperature: "thermometer.medium"
        case .oxygenSaturation: "drop"
        case .activeEnergy: "flame"
        }
    }

    /// Whether this metric gets a personal normal band.
    public var hasNormalRange: Bool {
        switch self {
        case .hrv, .restingHeartRate, .respiratoryRate, .wristTemperature, .oxygenSaturation, .sleepDuration: true
        case .readiness, .sleepScore, .trainingLoad, .activeEnergy: false
        }
    }

    /// Sums (bars) vs. levels (lines).
    public var isCumulative: Bool {
        self == .trainingLoad || self == .activeEnergy
    }
}

public struct TrendPoint: Sendable, Hashable, Identifiable {
    public var day: Date
    public var value: Double?
    public var normalRange: NormalRange?

    public var id: Date { day }
}

public struct LoadPoint: Sendable, Hashable, Identifiable {
    public var day: Date
    public var load: Double
    /// Rolling 7-day average daily load.
    public var acute: Double
    /// Average daily load over the 3 weeks before the acute window.
    public var chronic: Double?

    public var id: Date { day }
    public var ratio: Double? { chronic.flatMap { $0 > 0 ? acute / $0 : nil } }
}

/// The engine's output: per-day inputs, per-day scores and chart series.
public struct ReadinessAnalysis: Sendable {
    /// Days in the requested history window, oldest first.
    public let days: [DayMetrics]
    /// Includes the extra lookback used for baselines.
    let allDays: [DayMetrics]
    public let scores: [Date: ReadinessScore]
    public let configuration: ReadinessConfiguration
    let calendar: Calendar

    public init(
        days: [DayMetrics], allDays: [DayMetrics], scores: [Date: ReadinessScore],
        configuration: ReadinessConfiguration, calendar: Calendar
    ) {
        self.days = days
        self.allDays = allDays
        self.scores = scores
        self.configuration = configuration
        self.calendar = calendar
    }

    public static let empty = ReadinessAnalysis(
        days: [], allDays: [], scores: [:], configuration: .default, calendar: .current
    )

    /// The most recent day's score, if today could be scored.
    public var today: ReadinessScore? { days.last.flatMap { scores[$0.day] } }

    public var todayMetrics: DayMetrics? { days.last }

    /// Scores oldest first.
    public var orderedScores: [ReadinessScore] {
        days.compactMap { scores[$0.day] }
    }

    public func metrics(for day: Date) -> DayMetrics? {
        let start = calendar.startOfDay(for: day)
        return allDays.first { $0.day == start }
    }

    /// The last `count` days of a metric, with its personal normal range where it has one.
    public func trend(_ metric: MetricKind, lastDays count: Int) -> [TrendPoint] {
        let lower = max(allDays.count - count, 0)
        let range = lower..<allDays.count
        let sleepScorer = SleepScorer(
            goalHours: configuration.sleepGoalHours,
            consistencyNights: configuration.sleepConsistencyNights,
            calendar: calendar
        )

        let keyPath: KeyPath<DayMetrics, Double?>? = switch metric {
        case .hrv: preferredFlavour(\.hrvOvernight, \.hrvAllDay, in: range)
        case .restingHeartRate: preferredFlavour(\.sleepingHeartRate, \.appleRestingHeartRate, in: range)
        case .sleepDuration: \.sleepHours
        case .respiratoryRate: \.respiratoryRate
        case .wristTemperature: \.wristTemperature
        case .oxygenSaturation: \.oxygenSaturation
        case .activeEnergy: \.activeEnergy
        case .trainingLoad: \.trainingLoadValue
        case .readiness, .sleepScore: nil
        }

        return range.map { index in
            let day = allDays[index]
            let value: Double? = switch metric {
            case .readiness: scores[day.day].map { Double($0.score) }
            case .sleepScore: sleepScorer.score(days: allDays, index: index)?.total
            default: keyPath.flatMap { day[keyPath: $0] }
            }

            var normal: NormalRange?
            if metric.hasNormalRange, let keyPath {
                let ctx = ScoringContext(days: allDays, index: index, configuration: configuration, calendar: calendar)
                normal = switch metric {
                case .hrv: ctx.baseline(keyPath, minimumSpread: HRVScorer.minimumLogSpread, transform: log)
                    .map { NormalRange(logBaseline: $0) }
                case .restingHeartRate: ctx.baseline(keyPath, minimumSpread: RestingHeartRateScorer.minimumSpread)
                    .map { NormalRange($0) }
                case .wristTemperature: ctx.baseline(keyPath, minimumSpread: 0.15).map { NormalRange($0) }
                default: ctx.baseline(keyPath, minimumSpread: 0.25).map { NormalRange($0) }
                }
            }
            return TrendPoint(day: day.day, value: value, normalRange: normal)
        }
    }

    /// Daily load with acute and chronic rolling averages, for the training-load chart.
    public func loadTrend(lastDays count: Int) -> [LoadPoint] {
        let acuteDays = configuration.acuteLoadDays
        let chronicDays = configuration.chronicLoadDays
        let lower = max(allDays.count - count, 0)
        return (lower..<allDays.count).map { index in
            let acuteSlice = allDays[max(0, index - acuteDays + 1)...index]
            let chronicStart = max(0, index - chronicDays + 1)
            let chronicEnd = index - acuteDays + 1
            let chronic: Double? = chronicEnd - chronicStart >= 7
                ? Stats.mean(allDays[chronicStart..<chronicEnd].map(\.trainingLoad))
                : nil
            return LoadPoint(
                day: allDays[index].day,
                load: allDays[index].trainingLoad,
                acute: Stats.mean(acuteSlice.map(\.trainingLoad)) ?? 0,
                chronic: chronic
            )
        }
    }

    /// Overnight readings are preferred when they cover at least half of the days shown.
    private func preferredFlavour(
        _ primary: KeyPath<DayMetrics, Double?>,
        _ fallback: KeyPath<DayMetrics, Double?>,
        in range: Range<Int>
    ) -> KeyPath<DayMetrics, Double?> {
        let covered = allDays[range].filter { $0[keyPath: primary] != nil }.count
        return covered * 2 >= range.count ? primary : fallback
    }
}

extension DayMetrics {
    var sleepHours: Double? { sleep.map { $0.asleep / 3600 } }
    var trainingLoadValue: Double? { trainingLoad }
}
