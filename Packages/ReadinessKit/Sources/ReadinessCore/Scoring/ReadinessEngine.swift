import Foundation

/// Computes readiness scores and chart-ready trends from raw health data.
///
/// Pure and deterministic: the same `RawHealthData`, configuration, calendar and `now`
/// always give the same result.
public struct ReadinessEngine: Sendable {
    public var configuration: ReadinessConfiguration
    public var calendar: Calendar

    public init(configuration: ReadinessConfiguration = .default, calendar: Calendar = .current) {
        self.configuration = configuration
        self.calendar = calendar
    }

    /// Analyses the last `historyDays` days (today included), using older data for baselines.
    public func analyze(_ raw: RawHealthData, now: Date, historyDays: Int = 90) -> ReadinessAnalysis {
        let lastDay = calendar.startOfDay(for: now)
        let firstDay = calendar.date(byAdding: .day, value: -configuration.lookbackDays(historyDays: historyDays), to: lastDay)!
        let builder = DayMetricsBuilder(calendar: calendar, maxHeartRateOverride: configuration.maxHeartRateOverride)
        let days = builder.build(from: raw, firstDay: firstDay, lastDay: lastDay)

        let firstScored = max(0, days.count - historyDays)
        var scores: [Date: ReadinessScore] = [:]
        for index in firstScored..<days.count {
            let context = ScoringContext(days: days, index: index, configuration: configuration, calendar: calendar)
            if let score = score(context) {
                scores[days[index].day] = score
            }
        }
        return ReadinessAnalysis(
            days: Array(days[firstScored...]),
            allDays: days,
            scores: scores,
            configuration: configuration,
            calendar: calendar
        )
    }

    func score(_ ctx: ScoringContext) -> ReadinessScore? {
        let measured = [
            HRVScorer.score(ctx),
            RestingHeartRateScorer.score(ctx),
            SleepContributorScorer.score(ctx),
            TrainingLoadScorer.score(ctx),
            VitalsScorer.score(ctx),
        ].compactMap { $0 }
        guard let combined = Self.combine(measured, configuration: configuration) else { return nil }
        var contributors = combined.contributors
        let raw = combined.raw
        let limitingFactor = combined.limitingFactor
        let presentWeight = measured.reduce(0) { $0 + $1.weight }
        let totalWeight = configuration.weights.values.reduce(0, +)

        let score = Int((raw / 10).rounded()).clamped(to: 0...10)
        let category = ReadinessCategory(score: score)

        // Baseline maturity: days in the window with the recovery signals scoring relies on (HRV or
        // resting heart rate). Counting only tracked sleep would leave people who don't wear the
        // watch to bed "calibrating" forever, even with months of solid HRV history.
        let baselineNights = ctx.previous(configuration.baselineWindowDays).filter {
            $0.rmssdOvernight != nil || $0.hrvOvernight != nil || $0.hrvAllDay != nil
                || $0.sleepingHeartRate != nil || $0.appleRestingHeartRate != nil
        }.count
        let maturity = min(1, 0.5 + 0.5 * Double(baselineNights) / 28)
        let confidence = (presentWeight / totalWeight) * maturity

        contributors.sort { $0.effectiveWeight > $1.effectiveWeight }
        return ReadinessScore(
            day: ctx.today.day,
            score: score,
            rawScore: raw,
            category: category,
            contributors: contributors,
            limitingFactor: limitingFactor,
            confidence: confidence,
            isCalibrating: baselineNights < configuration.minimumBaselineNights,
            baselineNights: baselineNights,
            summary: Self.summary(contributors: contributors, limitingFactor: limitingFactor)
        )
    }

    /// Weighted mean over the contributors that have data, then the limiting-factor cap.
    /// Returns nil when too little of the model has data to be meaningful.
    static func combine(
        _ measured: [Contributor],
        configuration: ReadinessConfiguration
    ) -> (contributors: [Contributor], raw: Double, limitingFactor: ContributorKind?)? {
        // Don't produce a number from, say, training load alone.
        let presentWeight = measured.reduce(0) { $0 + $1.weight }
        let totalWeight = configuration.weights.values.reduce(0, +)
        guard totalWeight > 0, presentWeight > 0, presentWeight / totalWeight >= 0.4 else { return nil }

        var contributors = measured
        for i in contributors.indices {
            contributors[i].effectiveWeight = contributors[i].weight / presentWeight
        }
        var raw = contributors.reduce(0) { $0 + $1.subscore * $1.effectiveWeight }

        // A very weak physiological signal (a fever, a terrible night) shouldn't be averaged away,
        // and several at once should cap harder still.
        var limitingFactor: ContributorKind?
        let weak = contributors
            .filter { configuration.limitingFactorKinds.contains($0.kind) && $0.subscore < configuration.limitingFactorThreshold }
            .sorted { $0.subscore < $1.subscore }
        if let weakest = weak.first {
            let cap = weakest.subscore + configuration.limitingFactorHeadroom / Double(weak.count)
            if raw > cap {
                raw = cap
                limitingFactor = weakest.kind
            }
        }
        return (contributors, raw, limitingFactor)
    }

    static func summary(contributors: [Contributor], limitingFactor: ContributorKind?) -> String {
        if let limitingFactor, let weakest = contributors.first(where: { $0.kind == limitingFactor }) {
            return "Held back by \(weakest.summaryPhrase). \(limitingFactor.shortTitle) is well outside your normal, so the score is capped until it recovers."
        }
        let helping = contributors.filter { $0.impact > 0.15 }.max { $0.impact < $1.impact }
        let hurting = contributors.filter { $0.impact < -0.15 }.min { $0.impact < $1.impact }
        switch (helping, hurting) {
        case let (up?, down?):
            return "Lifted by \(up.summaryPhrase), held back by \(down.summaryPhrase)."
        case let (up?, nil):
            return "Supported by \(up.summaryPhrase), with nothing pulling you down."
        case let (nil, down?):
            return "Mostly in line with your normal, but held back by \(down.summaryPhrase)."
        case (nil, nil):
            return "Everything is close to your personal baseline."
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
