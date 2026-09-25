import Foundation
import ReadinessCore

/// Persists the latest snapshot in the App Group container shared with the widget extensions.
/// iPhone and Apple Watch each have their own container; each side writes its own copy.
enum SnapshotStore {
    static let appGroup = "group.org.openreadiness"
    private static let key = "latestSnapshot"

    /// Falls back to standard defaults when the App Group isn't provisioned (e.g. unsigned builds);
    /// the app still works, widgets then show their empty state.
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static func save(_ snapshot: ReadinessSnapshot) {
        guard let data = try? snapshot.encoded() else { return }
        defaults.set(data, forKey: key)
    }

    static func load() -> ReadinessSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? ReadinessSnapshot.decode(data)
    }
}

extension ReadinessSnapshot {
    /// A realistic snapshot for widget placeholders, galleries and previews.
    static func sample(on date: Date = .now, score: Int = 7) -> ReadinessSnapshot {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        func contributor(_ kind: ContributorKind, _ subscore: Double, _ weight: Double, _ headline: String) -> Contributor {
            var contributor = Contributor(
                kind: kind, subscore: subscore, weight: weight, value: nil, normalRange: nil,
                headline: headline, summaryPhrase: "", components: []
            )
            contributor.effectiveWeight = weight
            return contributor
        }
        let today = ReadinessScore(
            day: day,
            score: score,
            rawScore: Double(score) * 10,
            category: ReadinessCategory(score: score),
            contributors: [
                contributor(.hrv, 76, 0.30, "48 ms · 6% above your usual"),
                contributor(.sleep, 81, 0.25, "7h 32m asleep · sleep score 88"),
                contributor(.trainingLoad, 72, 0.20, "Balanced · 1.05× your usual"),
                contributor(.restingHeartRate, 66, 0.15, "54 bpm · 1 bpm above your usual"),
                contributor(.vitals, 75, 0.10, "All 3 within your normal range"),
            ],
            limitingFactor: nil,
            confidence: 0.95,
            isCalibrating: false,
            baselineNights: 60,
            summary: "Supported by solid sleep, with nothing pulling you down."
        )
        let week = [8, 7, 6, 8, 5, 7, score].enumerated().map { offset, value in
            DayScore(day: calendar.date(byAdding: .day, value: offset - 6, to: day)!, score: value)
        }
        return ReadinessSnapshot(today: today, week: week, isSampleData: true)
    }
}
