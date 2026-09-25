import Foundation

/// The small, self-contained summary that everything outside the main app displays: the watch app,
/// home-screen and lock-screen widgets, and watch-face complications.
///
/// It is computed where months of history are available (the iPhone) and copied outwards, so no
/// widget or complication ever has to query HealthKit itself.
public struct ReadinessSnapshot: Codable, Sendable, Hashable {
    public struct DayScore: Codable, Sendable, Hashable {
        public var day: Date
        public var score: Int

        public init(day: Date, score: Int) {
            self.day = day
            self.score = score
        }
    }

    /// One day of a compact trend series, with the personal normal range when known.
    public struct Point: Codable, Sendable, Hashable, Identifiable {
        public var day: Date
        public var value: Double?
        public var low: Double?
        public var high: Double?

        public var id: Date { day }

        public init(day: Date, value: Double?, low: Double? = nil, high: Double? = nil) {
            self.day = day
            self.value = value
            self.low = low
            self.high = high
        }
    }

    /// Recent context for the watch's chart pages; widgets ignore it.
    public struct Trends: Codable, Sendable, Hashable {
        public var hrv: [Point]
        public var restingHeartRate: [Point]
        public var lastNight: SleepSummary?

        public init(hrv: [Point], restingHeartRate: [Point], lastNight: SleepSummary?) {
            self.hrv = hrv
            self.restingHeartRate = restingHeartRate
            self.lastNight = lastNight
        }
    }

    public var today: ReadinessScore?
    public var week: [DayScore]
    /// Optional so snapshots from older app versions still decode.
    public var trends: Trends?
    public var generatedAt: Date
    /// True when produced from the built-in sample data, so widgets can say so.
    public var isSampleData: Bool

    public static let contextKey = "payload"

    public init(
        today: ReadinessScore?, week: [DayScore], trends: Trends? = nil,
        generatedAt: Date = .now, isSampleData: Bool = false
    ) {
        self.today = today
        self.week = week
        self.trends = trends
        self.generatedAt = generatedAt
        self.isSampleData = isSampleData
    }

    public init(analysis: ReadinessAnalysis, isSampleData: Bool = false) {
        self.init(
            today: analysis.today,
            week: analysis.orderedScores.suffix(7).map { DayScore(day: $0.day, score: $0.score) },
            trends: Trends(analysis: analysis),
            isSampleData: isSampleData
        )
    }

    /// Today's score, or nil once the day it describes is over (a stale number is worse than none).
    public func score(on date: Date, calendar: Calendar = .current) -> ReadinessScore? {
        guard let today, calendar.isDate(today.day, inSameDayAs: date) else { return nil }
        return today
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }

    public static func decode(_ data: Data) throws -> ReadinessSnapshot {
        try JSONDecoder().decode(ReadinessSnapshot.self, from: data)
    }
}

extension ReadinessSnapshot.Trends {
    /// The last 14 days of HRV and resting heart rate (same flavour and normal range the score
    /// uses) and last night's sleep. A few KB — small enough for WatchConnectivity's context.
    public init(analysis: ReadinessAnalysis, days: Int = 14) {
        func points(_ metric: MetricKind) -> [ReadinessSnapshot.Point] {
            analysis.trend(metric, lastDays: days).map {
                ReadinessSnapshot.Point(day: $0.day, value: $0.value, low: $0.normalRange?.low, high: $0.normalRange?.high)
            }
        }
        var lastNight = analysis.todayMetrics?.sleep
        if let segments = lastNight?.segments {
            lastNight?.segments = segments.filter { $0.stage != .inBed }
        }
        self.init(hrv: points(.hrv), restingHeartRate: points(.restingHeartRate), lastNight: lastNight)
    }
}
