import Foundation

/// A single timestamped measurement (e.g. one HRV reading, or one 30-minute heart-rate bucket).
public struct TimedValue: Sendable, Hashable, Codable {
    public var date: Date
    public var value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// Sleep stages as recorded by HealthKit's `sleepAnalysis` category.
public enum SleepStage: String, Sendable, Hashable, Codable, CaseIterable {
    case inBed
    case awake
    case asleepUnspecified
    case core
    case deep
    case rem

    public var isAsleep: Bool {
        switch self {
        case .asleepUnspecified, .core, .deep, .rem: true
        case .inBed, .awake: false
        }
    }
}

/// One contiguous sleep-analysis sample.
public struct SleepSegment: Sendable, Hashable, Codable {
    public var start: Date
    public var end: Date
    public var stage: SleepStage
    /// Identifies the writing app/device so overlapping sources (iPhone + Watch + third party) are not double counted.
    public var sourceID: String

    public init(start: Date, end: Date, stage: SleepStage, sourceID: String) {
        self.start = start
        self.end = end
        self.stage = stage
        self.sourceID = sourceID
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// A workout, reduced to what the load model needs.
public struct WorkoutRecord: Sendable, Hashable, Codable {
    public enum EffortSource: String, Sendable, Codable {
        /// Rated by the user in the Workout/Fitness app (watchOS 11+).
        case userRated
        /// Apple's estimated effort (watchOS 11+).
        case appleEstimated
        /// Derived here from average heart rate (heart-rate reserve).
        case heartRate
        /// Derived here from energy expenditure per minute.
        case energy
        /// Nothing known; a moderate default was used.
        case assumed
    }

    public var start: Date
    public var end: Date
    public var activityName: String
    public var activeEnergyKcal: Double?
    public var averageHeartRate: Double?
    /// Apple effort score, 1–10, when available.
    public var effortScore: Double?
    public var effortIsEstimated: Bool

    public init(
        start: Date,
        end: Date,
        activityName: String,
        activeEnergyKcal: Double? = nil,
        averageHeartRate: Double? = nil,
        effortScore: Double? = nil,
        effortIsEstimated: Bool = false
    ) {
        self.start = start
        self.end = end
        self.activityName = activityName
        self.activeEnergyKcal = activeEnergyKcal
        self.averageHeartRate = averageHeartRate
        self.effortScore = effortScore
        self.effortIsEstimated = effortIsEstimated
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

public struct UserProfile: Sendable, Hashable, Codable {
    public var age: Int?

    public init(age: Int? = nil) {
        self.age = age
    }
}

/// Everything the engine needs, already pulled out of HealthKit (or generated for demo mode).
///
/// Keeping this a plain value type means the whole scoring pipeline is deterministic and testable
/// without a device, and HealthKit types never leak past the adapter layer.
public struct RawHealthData: Sendable, Hashable, Codable {
    public var sleep: [SleepSegment]
    /// SDNN in milliseconds, one entry per Apple Watch HRV reading.
    public var hrv: [TimedValue]
    /// Average heart rate per fixed bucket (30 min by default); bucket start as the date.
    public var heartRateBuckets: [TimedValue]
    /// Apple's daily resting heart rate estimate (bpm).
    public var restingHeartRate: [TimedValue]
    /// Breaths per minute, measured by the watch during sleep.
    public var respiratoryRate: [TimedValue]
    /// Absolute sleeping wrist temperature in °C (Series 8 / Ultra and later).
    public var wristTemperature: [TimedValue]
    /// Blood oxygen as a percentage (0–100).
    public var oxygenSaturation: [TimedValue]
    public var workouts: [WorkoutRecord]
    /// Active energy per calendar day (kcal); the date is the day's start.
    public var activeEnergyDaily: [TimedValue]
    public var profile: UserProfile

    public init(
        sleep: [SleepSegment] = [],
        hrv: [TimedValue] = [],
        heartRateBuckets: [TimedValue] = [],
        restingHeartRate: [TimedValue] = [],
        respiratoryRate: [TimedValue] = [],
        wristTemperature: [TimedValue] = [],
        oxygenSaturation: [TimedValue] = [],
        workouts: [WorkoutRecord] = [],
        activeEnergyDaily: [TimedValue] = [],
        profile: UserProfile = UserProfile()
    ) {
        self.sleep = sleep
        self.hrv = hrv
        self.heartRateBuckets = heartRateBuckets
        self.restingHeartRate = restingHeartRate
        self.respiratoryRate = respiratoryRate
        self.wristTemperature = wristTemperature
        self.oxygenSaturation = oxygenSaturation
        self.workouts = workouts
        self.activeEnergyDaily = activeEnergyDaily
        self.profile = profile
    }
}

/// Anything that can supply raw health data: HealthKit on device, a demo generator, or a test fixture.
public protocol HealthDataSource: Sendable {
    func requestAuthorization() async throws
    func fetch(from start: Date, to end: Date) async throws -> RawHealthData
}
