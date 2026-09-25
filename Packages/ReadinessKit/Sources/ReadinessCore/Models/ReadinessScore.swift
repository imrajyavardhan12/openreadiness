import Foundation

/// The four recommendation bands. Ranges intentionally match Apple's published Readiness bands
/// so the numbers mean the same thing to people who know both.
public enum ReadinessCategory: Int, Sendable, Codable, CaseIterable, Comparable {
    case recover
    case paceYourself
    case ready
    case goForIt

    public init(score: Int) {
        switch score {
        case ...1: self = .recover
        case 2...4: self = .paceYourself
        case 5...7: self = .ready
        default: self = .goForIt
        }
    }

    public var title: String {
        switch self {
        case .recover: "Recover"
        case .paceYourself: "Pace Yourself"
        case .ready: "Ready"
        case .goForIt: "Go For It"
        }
    }

    public var scoreRange: ClosedRange<Int> {
        switch self {
        case .recover: 0...1
        case .paceYourself: 2...4
        case .ready: 5...7
        case .goForIt: 8...10
        }
    }

    public var guidance: String {
        switch self {
        case .recover:
            "Your body is showing clear signs of strain. Prioritise rest, sleep, hydration and easy movement."
        case .paceYourself:
            "Some signals are below your usual. Keep intensity moderate and favour technique or recovery work."
        case .ready:
            "You're close to your baseline. A normal training day is well supported."
        case .goForIt:
            "Your recovery markers are strong. A good day for a harder session or a personal best."
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum ContributorKind: String, Sendable, Codable, CaseIterable, Identifiable {
    case hrv
    case restingHeartRate
    case sleep
    case trainingLoad
    case vitals

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .hrv: "Heart Rate Variability"
        case .restingHeartRate: "Resting Heart Rate"
        case .sleep: "Sleep"
        case .trainingLoad: "Training Load"
        case .vitals: "Overnight Vitals"
        }
    }

    public var shortTitle: String {
        switch self {
        case .hrv: "HRV"
        case .restingHeartRate: "Resting HR"
        case .sleep: "Sleep"
        case .trainingLoad: "Load"
        case .vitals: "Vitals"
        }
    }

    /// SF Symbol name.
    public var systemImage: String {
        switch self {
        case .hrv: "waveform.path.ecg"
        case .restingHeartRate: "heart"
        case .sleep: "bed.double"
        case .trainingLoad: "figure.run"
        case .vitals: "lungs"
        }
    }

    public var explanation: String {
        switch self {
        case .hrv:
            "Heart rate variability reflects how much your nervous system is in 'rest and recover' mode. Higher than your own normal is generally a good sign; a sustained drop often follows hard training, poor sleep, alcohol, stress or illness. OpenReadiness computes RMSSD from your watch's beat-to-beat data (the measure used in research and by Oura and Whoop), falling back to Apple's SDNN, and compares it on a log scale against your last 60 days."
        case .restingHeartRate:
            "Your lowest sustained heart rate during sleep. When your body is fighting fatigue, heat, alcohol or illness it usually sits a few beats higher than normal."
        case .sleep:
            "Last night's sleep score (duration, bedtime consistency and interruptions) combined with any sleep debt from the past week."
        case .trainingLoad:
            "Compares the last 7 days of training to the 3 weeks before. A sudden jump well above what you're used to raises injury and fatigue risk; a steady or lighter week leaves you fresher."
        case .vitals:
            "Respiratory rate, wrist temperature and blood oxygen while you slept, compared with your own baseline. Several out of range at once can be an early sign of illness."
        }
    }
}

public enum ContributorStatus: Int, Sendable, Codable, Comparable {
    case poor
    case caution
    case neutral
    case good

    public init(subscore: Double) {
        switch subscore {
        case ..<35: self = .poor
        case ..<55: self = .caution
        case ..<75: self = .neutral
        default: self = .good
        }
    }

    public var label: String {
        switch self {
        case .poor: "Low"
        case .caution: "Below usual"
        case .neutral: "Normal"
        case .good: "Optimal"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A personal normal range derived from recent history.
public struct Baseline: Sendable, Hashable, Codable {
    public var median: Double
    /// Robust standard deviation (1.4826 × MAD), floored so a very stable metric doesn't overreact.
    public var spread: Double
    /// Number of days that contributed.
    public var count: Int

    public init(median: Double, spread: Double, count: Int) {
        self.median = median
        self.spread = spread
        self.count = count
    }

    public func zScore(_ value: Double) -> Double {
        spread > 0 ? (value - median) / spread : 0
    }
}

/// A personal normal range in display units (for HRV this is computed on a log scale, so it is asymmetric).
public struct NormalRange: Sendable, Hashable, Codable {
    public var low: Double
    public var median: Double
    public var high: Double

    public init(low: Double, median: Double, high: Double) {
        self.low = low
        self.median = median
        self.high = high
    }

    public init(_ baseline: Baseline) {
        self.init(low: baseline.median - baseline.spread, median: baseline.median, high: baseline.median + baseline.spread)
    }

    /// For a baseline computed on natural-log values.
    public init(logBaseline baseline: Baseline) {
        self.init(
            low: exp(baseline.median - baseline.spread),
            median: exp(baseline.median),
            high: exp(baseline.median + baseline.spread)
        )
    }

    public func contains(_ value: Double) -> Bool { (low...high).contains(value) }
}

/// A line in the "show the math" breakdown of a contributor.
public struct ScoreComponent: Sendable, Hashable, Codable, Identifiable {
    public var label: String
    public var value: String
    public var note: String?

    public var id: String { label }

    public init(label: String, value: String, note: String? = nil) {
        self.label = label
        self.value = value
        self.note = note
    }
}

public struct Contributor: Sendable, Hashable, Codable, Identifiable {
    public var kind: ContributorKind
    /// 0–100. ~70 means "right on your baseline".
    public var subscore: Double
    /// Weight from configuration.
    public var weight: Double
    /// Weight actually used after renormalising over the contributors that had data.
    public var effectiveWeight: Double
    public var status: ContributorStatus
    /// Primary value in display units (ms, bpm, hours, ratio…), if any.
    public var value: Double?
    public var normalRange: NormalRange?
    /// One line, e.g. "52 ms · 12% above your usual".
    public var headline: String
    /// Short clause used to build the day's summary, e.g. "HRV well above your usual".
    public var summaryPhrase: String
    public var components: [ScoreComponent]

    public var id: ContributorKind { kind }

    public init(
        kind: ContributorKind, subscore: Double, weight: Double, effectiveWeight: Double = 0,
        value: Double?, normalRange: NormalRange?, headline: String, summaryPhrase: String,
        components: [ScoreComponent]
    ) {
        self.kind = kind
        self.subscore = subscore
        self.weight = weight
        self.effectiveWeight = effectiveWeight
        self.status = ContributorStatus(subscore: subscore)
        self.value = value
        self.normalRange = normalRange
        self.headline = headline
        self.summaryPhrase = summaryPhrase
        self.components = components
    }

    /// Points (out of 10) this contributor moved the final score relative to a neutral 7.
    public var impact: Double { (subscore - 70) / 10 * effectiveWeight }
}

public struct ReadinessScore: Sendable, Hashable, Codable, Identifiable {
    public var day: Date
    /// 0–10.
    public var score: Int
    /// 0–100 before rounding, after any limiting-factor cap.
    public var rawScore: Double
    public var category: ReadinessCategory
    public var contributors: [Contributor]
    /// Set when one very weak contributor capped the overall score.
    public var limitingFactor: ContributorKind?
    /// 0–1: how much of the model had data and a mature baseline behind it.
    public var confidence: Double
    /// True while fewer than the minimum number of nights exist for a personal baseline.
    public var isCalibrating: Bool
    public var baselineNights: Int
    public var summary: String

    public var id: Date { day }

    public init(
        day: Date, score: Int, rawScore: Double, category: ReadinessCategory, contributors: [Contributor],
        limitingFactor: ContributorKind?, confidence: Double, isCalibrating: Bool, baselineNights: Int, summary: String
    ) {
        self.day = day
        self.score = score
        self.rawScore = rawScore
        self.category = category
        self.contributors = contributors
        self.limitingFactor = limitingFactor
        self.confidence = confidence
        self.isCalibrating = isCalibrating
        self.baselineNights = baselineNights
        self.summary = summary
    }

    public func contributor(_ kind: ContributorKind) -> Contributor? {
        contributors.first { $0.kind == kind }
    }
}
