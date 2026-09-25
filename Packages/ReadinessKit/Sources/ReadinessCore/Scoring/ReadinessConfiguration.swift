import Foundation

/// Every tunable number in the model lives here, so the algorithm is inspectable and easy to experiment with.
/// See `docs/ALGORITHM.md` for the reasoning behind each default.
public struct ReadinessConfiguration: Sendable, Hashable, Codable {
    /// Relative importance of each contributor. Renormalised over whatever has data on a given day.
    public var weights: [ContributorKind: Double]

    /// Days of history (before the scored day) that form the personal baseline.
    public var baselineWindowDays: Int
    /// Nights needed before a baseline is trusted. Apple uses 7 of the past 49 nights.
    public var minimumBaselineNights: Int

    public var sleepGoalHours: Double
    /// Nights considered for sleep debt.
    public var sleepDebtNights: Int
    /// Nights considered for bedtime consistency.
    public var sleepConsistencyNights: Int

    /// Acute and chronic windows for the acute:chronic workload ratio.
    public var acuteLoadDays: Int
    public var chronicLoadDays: Int

    /// A contributor below this subscore is a "limiting factor"...
    public var limitingFactorThreshold: Double
    /// ...and caps the overall score at its own subscore plus this headroom, divided by the number
    /// of limiting factors (several red flags at once — typical of illness — cap harder).
    public var limitingFactorHeadroom: Double
    /// Physiological signals that may act as limiting factors. Training load is excluded: a load
    /// spike is a behavioural caution, not evidence your body is currently struggling.
    public var limitingFactorKinds: Set<ContributorKind>

    public var maxHeartRateOverride: Double?

    public init(
        weights: [ContributorKind: Double] = Self.defaultWeights,
        baselineWindowDays: Int = 60,
        minimumBaselineNights: Int = 7,
        sleepGoalHours: Double = 8,
        sleepDebtNights: Int = 7,
        sleepConsistencyNights: Int = 14,
        acuteLoadDays: Int = 7,
        chronicLoadDays: Int = 28,
        limitingFactorThreshold: Double = 30,
        limitingFactorHeadroom: Double = 35,
        limitingFactorKinds: Set<ContributorKind> = [.hrv, .restingHeartRate, .sleep, .vitals],
        maxHeartRateOverride: Double? = nil
    ) {
        self.weights = weights
        self.baselineWindowDays = baselineWindowDays
        self.minimumBaselineNights = minimumBaselineNights
        self.sleepGoalHours = sleepGoalHours
        self.sleepDebtNights = sleepDebtNights
        self.sleepConsistencyNights = sleepConsistencyNights
        self.acuteLoadDays = acuteLoadDays
        self.chronicLoadDays = chronicLoadDays
        self.limitingFactorThreshold = limitingFactorThreshold
        self.limitingFactorHeadroom = limitingFactorHeadroom
        self.limitingFactorKinds = limitingFactorKinds
        self.maxHeartRateOverride = maxHeartRateOverride
    }

    public static let defaultWeights: [ContributorKind: Double] = [
        .hrv: 0.30,
        .sleep: 0.25,
        .trainingLoad: 0.20,
        .restingHeartRate: 0.15,
        .vitals: 0.10,
    ]

    public static let `default` = ReadinessConfiguration()

    /// The oldest data needed to score `historyDays` days with full baselines and load windows.
    public func lookbackDays(historyDays: Int) -> Int {
        historyDays + max(baselineWindowDays, chronicLoadDays) + 1
    }
}
