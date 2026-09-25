import Foundation
import ReadinessCore

/// What the iPhone sends to the watch. The phone holds months of history, so it produces the
/// best baselines; the watch shows this and only computes locally as a fallback.
struct WatchPayload: Codable, Sendable {
    struct DayScore: Codable, Sendable, Hashable {
        var day: Date
        var score: Int
    }

    var today: ReadinessScore?
    var week: [DayScore]
    var generatedAt: Date

    static let contextKey = "payload"

    init(today: ReadinessScore?, week: [DayScore], generatedAt: Date = .now) {
        self.today = today
        self.week = week
        self.generatedAt = generatedAt
    }

    init(analysis: ReadinessAnalysis) {
        self.init(
            today: analysis.today,
            week: analysis.orderedScores.suffix(7).map { DayScore(day: $0.day, score: $0.score) }
        )
    }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    static func decode(_ data: Data) throws -> WatchPayload {
        try JSONDecoder().decode(WatchPayload.self, from: data)
    }
}
