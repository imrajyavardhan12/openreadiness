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

    public var today: ReadinessScore?
    public var week: [DayScore]
    public var generatedAt: Date
    /// True when produced from the built-in sample data, so widgets can say so.
    public var isSampleData: Bool

    public static let contextKey = "payload"

    public init(today: ReadinessScore?, week: [DayScore], generatedAt: Date = .now, isSampleData: Bool = false) {
        self.today = today
        self.week = week
        self.generatedAt = generatedAt
        self.isSampleData = isSampleData
    }

    public init(analysis: ReadinessAnalysis, isSampleData: Bool = false) {
        self.init(
            today: analysis.today,
            week: analysis.orderedScores.suffix(7).map { DayScore(day: $0.day, score: $0.score) },
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
