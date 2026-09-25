import Foundation
import ReadinessCore

/// One period's value. For `.range` metrics `min`/`max` are filled in; `value` is always the mean or total.
public struct DailyValue: Sendable, Hashable, Codable, Identifiable {
    /// Start of the day (or of the week / month once bucketed).
    public var date: Date
    public var value: Double
    public var min: Double?
    public var max: Double?

    public var id: Date { date }

    public init(date: Date, value: Double, min: Double? = nil, max: Double? = nil) {
        self.date = date
        self.value = value
        self.min = min
        self.max = max
    }
}

public struct ActivityRingDay: Sendable, Hashable, Codable, Identifiable {
    public var date: Date
    public var move: Double
    public var moveGoal: Double
    public var exercise: Double
    public var exerciseGoal: Double
    public var stand: Double
    public var standGoal: Double

    public var id: Date { date }

    public init(date: Date, move: Double, moveGoal: Double, exercise: Double, exerciseGoal: Double, stand: Double, standGoal: Double) {
        self.date = date
        self.move = move
        self.moveGoal = moveGoal
        self.exercise = exercise
        self.exerciseGoal = exerciseGoal
        self.stand = stand
        self.standGoal = standGoal
    }

    public var moveProgress: Double { moveGoal > 0 ? move / moveGoal : 0 }
    public var exerciseProgress: Double { exerciseGoal > 0 ? exercise / exerciseGoal : 0 }
    public var standProgress: Double { standGoal > 0 ? stand / standGoal : 0 }
    public var allClosed: Bool { moveProgress >= 1 && exerciseProgress >= 1 && standProgress >= 1 }
}

public struct WorkoutSummary: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var activityName: String
    public var start: Date
    public var end: Date
    public var activeEnergyKcal: Double?
    public var distanceMeters: Double?
    public var averageHeartRate: Double?
    public var maxHeartRate: Double?

    public init(
        id: UUID, activityName: String, start: Date, end: Date,
        activeEnergyKcal: Double? = nil, distanceMeters: Double? = nil,
        averageHeartRate: Double? = nil, maxHeartRate: Double? = nil
    ) {
        self.id = id
        self.activityName = activityName
        self.start = start
        self.end = end
        self.activeEnergyKcal = activeEnergyKcal
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Min/mean/max over a short bucket (e.g. 5 minutes of heart rate).
public struct RangeBucket: Sendable, Hashable, Codable, Identifiable {
    public var start: Date
    public var min: Double
    public var average: Double
    public var max: Double

    public var id: Date { start }

    public init(start: Date, min: Double, average: Double, max: Double) {
        self.start = start
        self.min = min
        self.average = average
        self.max = max
    }
}

/// Everything needed to draw one day as a timeline.
public struct IntradayDay: Sendable, Hashable {
    public var day: Date
    public var heartRate: [RangeBucket]
    /// Steps per hour; date = start of the hour.
    public var hourlySteps: [TimedValue]
    public var sleep: [SleepSegment]
    public var workouts: [WorkoutSummary]

    public init(day: Date, heartRate: [RangeBucket], hourlySteps: [TimedValue], sleep: [SleepSegment], workouts: [WorkoutSummary]) {
        self.day = day
        self.heartRate = heartRate
        self.hourlySteps = hourlySteps
        self.sleep = sleep
        self.workouts = workouts
    }
}

public struct HealthProfile: Sendable, Hashable {
    public var age: Int?

    public init(age: Int? = nil) {
        self.age = age
    }
}

/// Supplies explorer data. Queries are on demand and per metric, so opening one chart never
/// loads everything.
public protocol HealthMetricsProvider: Sendable {
    func requestAuthorization() async throws
    func daily(_ metric: HealthMetric, in interval: DateInterval) async throws -> [DailyValue]
    func activityRings(in interval: DateInterval) async throws -> [ActivityRingDay]
    func workouts(in interval: DateInterval) async throws -> [WorkoutSummary]
    func heartRateSamples(in interval: DateInterval) async throws -> [TimedValue]
    func intraday(on day: Date) async throws -> IntradayDay
    func profile() async -> HealthProfile
}

/// Chart periods, mirroring the familiar W / M / 6M / Y.
public enum ExplorerRange: String, Sendable, Hashable, CaseIterable, Identifiable {
    case week
    case month
    case sixMonths
    case year

    public var id: String { rawValue }

    public var days: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .sixMonths: 182
        case .year: 365
        }
    }

    public var shortTitle: String {
        switch self {
        case .week: "W"
        case .month: "M"
        case .sixMonths: "6M"
        case .year: "Y"
        }
    }

    /// Longer ranges are bucketed so bars stay readable.
    public var bucket: Calendar.Component {
        switch self {
        case .week, .month: .day
        case .sixMonths: .weekOfYear
        case .year: .month
        }
    }

    public var periodNoun: String {
        switch self {
        case .week: "week"
        case .month: "month"
        case .sixMonths: "6 months"
        case .year: "year"
        }
    }
}
