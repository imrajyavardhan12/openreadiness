import Foundation

/// The day being scored plus everything before it. Scorers only look backwards, so a historical
/// score is exactly what you would have seen that morning.
struct ScoringContext {
    let days: [DayMetrics]
    let index: Int
    let configuration: ReadinessConfiguration
    let calendar: Calendar

    var today: DayMetrics { days[index] }

    /// Up to `count` days immediately before the scored day.
    func previous(_ count: Int) -> ArraySlice<DayMetrics> {
        days[max(0, index - count)..<index]
    }

    /// The last `count` days including the scored day.
    func recent(_ count: Int) -> ArraySlice<DayMetrics> {
        days[max(0, index - count + 1)...index]
    }

    func baseline(
        _ metric: KeyPath<DayMetrics, Double?>,
        minimumSpread: Double,
        transform: (Double) -> Double = { $0 }
    ) -> Baseline? {
        let values = previous(configuration.baselineWindowDays).compactMap { $0[keyPath: metric] }.map(transform)
        return Baseline.robust(values, minimumCount: configuration.minimumBaselineNights, minimumSpread: minimumSpread)
    }
}

// MARK: - HRV

enum HRVScorer {
    /// Day-to-day ln(SDNN) noise is roughly 0.15–0.25; never treat less than 0.08 as meaningful.
    static let minimumLogSpread = 0.08

    static func score(_ ctx: ScoringContext) -> Contributor? {
        // Most to least preferred. Each flavour is only ever compared with its own baseline.
        let flavours: [(KeyPath<DayMetrics, Double?>, String)] = [
            (\.rmssdOvernight, "overnight RMSSD"),
            (\.hrvOvernight, "overnight SDNN"),
            (\.hrvAllDay, "SDNN, last 24 h"),
        ]
        for (metric, label) in flavours {
            guard let value = ctx.today[keyPath: metric], value > 0,
                  let baseline = ctx.baseline(metric, minimumSpread: minimumLogSpread, transform: log)
            else { continue }

            let zToday = baseline.zScore(log(value))
            let week = ctx.recent(7).compactMap { $0[keyPath: metric] }
            let weekMean = week.count >= 3 ? Stats.geometricMean(week) : nil
            let zWeek = weekMean.map { baseline.zScore(log($0)) }
            let z = zWeek.map { 0.7 * zToday + 0.3 * $0 } ?? zToday

            let range = NormalRange(logBaseline: baseline)
            var components = [
                ScoreComponent(label: "Last night (\(label))", value: "\(Format.number(value)) ms"),
                ScoreComponent(
                    label: "Your normal",
                    value: "\(Format.number(range.median)) ms",
                    note: "\(Format.number(range.low))–\(Format.number(range.high)) ms over \(baseline.count) days"
                ),
            ]
            if let weekMean {
                components.append(ScoreComponent(label: "7-day average", value: "\(Format.number(weekMean)) ms"))
            }
            components.append(ScoreComponent(
                label: "Deviation",
                value: "z \(Format.signed(z, digits: 1))",
                note: zWeek == nil ? "Last night only" : "70% last night, 30% 7-day trend"
            ))

            return Contributor(
                kind: .hrv,
                subscore: Stats.subscore(fromZ: z),
                weight: ctx.configuration.weights[.hrv] ?? 0,
                value: value,
                normalRange: range,
                headline: "\(Format.number(value)) ms · \(Format.relative(value, to: range.median)) your usual",
                summaryPhrase: phrase(z: z, better: "HRV above your usual", worse: "HRV below your usual"),
                components: components
            )
        }
        return nil
    }
}

// MARK: - Resting heart rate

enum RestingHeartRateScorer {
    static let minimumSpread = 1.5

    static func score(_ ctx: ScoringContext) -> Contributor? {
        let flavours: [(KeyPath<DayMetrics, Double?>, String)] = [
            (\.sleepingHeartRate, "lowest 30-min average during sleep"),
            (\.appleRestingHeartRate, "Apple resting heart rate"),
        ]
        for (metric, label) in flavours {
            guard let value = ctx.today[keyPath: metric],
                  let baseline = ctx.baseline(metric, minimumSpread: minimumSpread)
            else { continue }

            // Lower than usual is good, so invert.
            let z = -baseline.zScore(value)
            let delta = value - baseline.median
            let deltaText = abs(delta) < 1
                ? "right at your usual"
                : "\(Format.number(abs(delta))) bpm \(delta > 0 ? "above" : "below") your usual"

            return Contributor(
                kind: .restingHeartRate,
                subscore: Stats.subscore(fromZ: z),
                weight: ctx.configuration.weights[.restingHeartRate] ?? 0,
                value: value,
                normalRange: NormalRange(baseline),
                headline: "\(Format.number(value)) bpm · \(deltaText)",
                summaryPhrase: phrase(z: z, better: "a low resting heart rate", worse: "an elevated resting heart rate"),
                components: [
                    ScoreComponent(label: "Last night", value: "\(Format.number(value)) bpm", note: label.capitalizedFirst),
                    ScoreComponent(
                        label: "Your normal",
                        value: "\(Format.number(baseline.median)) bpm",
                        note: "±\(Format.number(baseline.spread, digits: 1)) bpm over \(baseline.count) days"
                    ),
                    ScoreComponent(label: "Deviation", value: "z \(Format.signed(z, digits: 1))", note: "Positive = lower than usual"),
                ]
            )
        }
        return nil
    }
}

// MARK: - Sleep

enum SleepContributorScorer {
    static func score(_ ctx: ScoringContext) -> Contributor? {
        let scorer = SleepScorer(
            goalHours: ctx.configuration.sleepGoalHours,
            consistencyNights: ctx.configuration.sleepConsistencyNights,
            calendar: ctx.calendar
        )
        guard let sleep = ctx.today.sleep, let night = scorer.score(days: ctx.days, index: ctx.index) else { return nil }

        // Sleep debt: average shortfall versus the goal over recent tracked nights.
        let goal = ctx.configuration.sleepGoalHours * 3600
        let recent = ctx.recent(ctx.configuration.sleepDebtNights).compactMap(\.sleep)
        let shortfall = Stats.mean(recent.map { max(0, goal - $0.asleep) }) ?? 0
        let debtScore = Stats.interpolate(shortfall / 3600, from: 0, 2.5, to: 100, 20)

        let composite = 0.75 * night.total + 0.25 * debtScore
        // A typical good night (composite ≈ 85) should sit near the "your normal" level of the
        // other contributors (≈ 70–75), not above it; otherwise ordinary days inflate the total.
        let subscore = Stats.clamp(75 + (composite - 85) * 1.33, 0, 100)
        var components = [
            ScoreComponent(label: "Sleep score", value: Format.number(night.total), note: "Out of 100 · a typical good night is ~85"),
            ScoreComponent(
                label: "Duration",
                value: "\(Format.number(night.duration))/\(Format.number(SleepScore.maxDuration))",
                note: "\(Format.duration(sleep.asleep)) asleep, goal \(Format.number(ctx.configuration.sleepGoalHours, digits: 1))h"
            ),
            ScoreComponent(
                label: "Bedtime consistency",
                value: "\(Format.number(night.consistency))/\(Format.number(SleepScore.maxConsistency))",
                note: night.midpointDeviationMinutes.map { "Midpoint \(Format.number($0)) min from your usual" }
                    ?? "Needs 3 more nights of history"
            ),
            ScoreComponent(
                label: "Interruptions",
                value: "\(Format.number(night.interruptions))/\(Format.number(SleepScore.maxInterruptions))",
                note: "\(sleep.interruptions) wake-ups, \(Format.duration(sleep.awake)) awake"
            ),
        ]
        components.append(ScoreComponent(
            label: "Sleep debt",
            value: Format.number(debtScore),
            note: "Avg \(Format.duration(shortfall)) short over \(recent.count) nights"
        ))

        let isGood = subscore >= 70
        return Contributor(
            kind: .sleep,
            subscore: subscore,
            weight: ctx.configuration.weights[.sleep] ?? 0,
            value: sleep.asleep / 3600,
            normalRange: nil,
            headline: "\(Format.duration(sleep.asleep)) asleep · sleep score \(Format.number(night.total))",
            summaryPhrase: isGood ? "solid sleep" : (sleep.asleep < goal - 3600 ? "short sleep" : "restless sleep"),
            components: components
        )
    }
}

// MARK: - Training load

enum TrainingLoadScorer {
    /// Below this daily average (sRPE units, ≈ 5 easy minutes) the history is effectively "no training".
    static let minimumMeaningfulLoad = 20.0

    static func score(_ ctx: ScoringContext) -> Contributor? {
        let config = ctx.configuration
        let window = ctx.recent(config.chronicLoadDays)
        // Need at least two weeks of history for a ratio to mean anything.
        guard window.count >= 14 else { return nil }

        // Without any logged workouts, fall back to daily active energy as the load signal.
        let usesWorkouts = window.contains { !$0.workouts.isEmpty }
        let load: (DayMetrics) -> Double? = usesWorkouts ? { $0.trainingLoad } : { $0.activeEnergy }
        let unit = usesWorkouts ? "load" : "kcal"
        let floor = usesWorkouts ? minimumMeaningfulLoad : 150

        let acuteDays = Array(ctx.recent(config.acuteLoadDays))
        let chronicDays = Array(window.dropLast(acuteDays.count))
        guard let acute = Stats.mean(acuteDays.compactMap(load)),
              let chronic = Stats.mean(chronicDays.compactMap(load))
        else { return nil }

        let ratio: Double = if chronic < floor {
            acute < floor ? 1 : acute / floor
        } else {
            acute / chronic
        }
        let yesterday = ctx.index > 0 ? (load(ctx.days[ctx.index - 1]) ?? 0) : 0
        let strain = yesterday / max(chronic, floor)

        let ratioScore = ratioSubscore(ratio)
        let strainScore = strainSubscore(strain)
        let subscore = 0.7 * ratioScore + 0.3 * strainScore
        let label = ratioLabel(ratio)

        return Contributor(
            kind: .trainingLoad,
            subscore: subscore,
            weight: config.weights[.trainingLoad] ?? 0,
            value: ratio,
            normalRange: NormalRange(low: 0.8, median: 1.05, high: 1.3),
            headline: "\(label) · last 7 days \(Format.number(ratio, digits: 2))× your usual",
            summaryPhrase: subscore >= 70 ? "a manageable training load" : "a heavy recent training load",
            components: [
                ScoreComponent(label: "7-day average", value: "\(Format.number(acute)) \(unit)/day"),
                ScoreComponent(label: "Previous 3 weeks", value: "\(Format.number(chronic)) \(unit)/day"),
                ScoreComponent(
                    label: "Acute:chronic ratio",
                    value: Format.number(ratio, digits: 2),
                    note: "\(label). 0.8–1.3 is the usual sweet spot"
                ),
                ScoreComponent(
                    label: "Yesterday",
                    value: "\(Format.number(yesterday)) \(unit)",
                    note: "\(Format.number(strain, digits: 1))× a typical day"
                ),
                ScoreComponent(
                    label: "Source",
                    value: usesWorkouts ? "Workouts" : "Active energy",
                    note: usesWorkouts ? "Minutes × effort (session RPE)" : "No workouts logged in 4 weeks"
                ),
            ]
        )
    }

    /// Being fresher than usual supports readiness; spikes well above your chronic load do not.
    static func ratioSubscore(_ ratio: Double) -> Double {
        switch ratio {
        case ..<0.8: 80
        case ..<1.3: Stats.interpolate(ratio, from: 0.8, 1.3, to: 78, 68)
        case ..<1.5: Stats.interpolate(ratio, from: 1.3, 1.5, to: 68, 45)
        case ..<2.0: Stats.interpolate(ratio, from: 1.5, 2.0, to: 45, 25)
        default: 20
        }
    }

    static func strainSubscore(_ strain: Double) -> Double {
        switch strain {
        case ..<1: 78
        case ..<2: Stats.interpolate(strain, from: 1, 2, to: 78, 55)
        case ..<3.5: Stats.interpolate(strain, from: 2, 3.5, to: 55, 25)
        default: 20
        }
    }

    static func ratioLabel(_ ratio: Double) -> String {
        switch ratio {
        case ..<0.8: "Fresh"
        case ..<1.3: "Balanced"
        case ..<1.5: "High"
        default: "Very high"
        }
    }
}

// MARK: - Vitals

enum VitalsScorer {
    static func score(_ ctx: ScoringContext) -> Contributor? {
        var readings: [(name: String, subscore: Double, component: ScoreComponent)] = []

        if let value = ctx.today.respiratoryRate,
           let baseline = ctx.baseline(\.respiratoryRate, minimumSpread: 0.5) {
            let z = baseline.zScore(value)
            // Elevated breathing is the more meaningful direction; low counts half.
            let effective = z > 0 ? z : abs(z) * 0.5
            let sub = effective <= 1 ? 75 : Stats.interpolate(effective, from: 1, 3, to: 75, 20)
            readings.append(("Respiratory rate", sub, ScoreComponent(
                label: "Respiratory rate",
                value: "\(Format.number(value, digits: 1)) br/min",
                note: "Usual \(Format.number(baseline.median, digits: 1)) (\(Format.signed(value - baseline.median, digits: 1)))"
            )))
        }

        if let value = ctx.today.wristTemperature,
           let baseline = ctx.baseline(\.wristTemperature, minimumSpread: 0.15) {
            let delta = value - baseline.median
            let effective = delta > 0 ? delta : abs(delta) * 0.5
            let sub = effective <= 0.3 ? 75 : Stats.interpolate(effective, from: 0.3, 1.0, to: 75, 25)
            readings.append(("Wrist temperature", sub, ScoreComponent(
                label: "Wrist temperature",
                value: "\(Format.signed(delta, digits: 2)) °C",
                note: "Relative to your usual"
            )))
        }

        if let value = ctx.today.oxygenSaturation,
           let baseline = ctx.baseline(\.oxygenSaturation, minimumSpread: 0.5) {
            let drop = baseline.median - value
            let sub = drop <= 1 ? 75 : Stats.interpolate(drop, from: 1, 5, to: 75, 20)
            readings.append(("Blood oxygen", sub, ScoreComponent(
                label: "Blood oxygen",
                value: "\(Format.number(value))%",
                note: "Usual \(Format.number(baseline.median))%"
            )))
        }

        guard let worst = readings.min(by: { $0.subscore < $1.subscore }) else { return nil }

        // One vital off can be noise; several off together is a much stronger illness signal.
        let outOfRange = readings.filter { $0.subscore < 60 }
        let subscore = max(0, worst.subscore - (outOfRange.count >= 2 ? 10 : 0))

        let headline = outOfRange.isEmpty
            ? "All \(readings.count) within your normal range"
            : outOfRange.map(\.name).joined(separator: " & ") + " outside your normal"

        return Contributor(
            kind: .vitals,
            subscore: subscore,
            weight: ctx.configuration.weights[.vitals] ?? 0,
            value: Double(outOfRange.count),
            normalRange: nil,
            headline: headline,
            summaryPhrase: outOfRange.isEmpty ? "normal overnight vitals" : "vitals outside your normal range",
            components: readings.map(\.component)
        )
    }
}

// MARK: - Helpers

private func phrase(z: Double, better: String, worse: String) -> String {
    z >= 0 ? better : worse
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
