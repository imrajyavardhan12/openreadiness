import Foundation

/// The main sleep period that ended on a given morning.
public struct SleepSummary: Sendable, Hashable, Codable {
    /// First asleep moment.
    public var start: Date
    /// Last asleep moment.
    public var end: Date
    public var asleep: TimeInterval
    /// Time awake between `start` and `end` (explicit awake samples plus untracked gaps).
    public var awake: TimeInterval
    public var deep: TimeInterval
    public var rem: TimeInterval
    public var core: TimeInterval
    /// Asleep time without stage information (older watches, third-party apps).
    public var unspecified: TimeInterval
    /// Wake-ups of at least a few minutes between falling asleep and final wake.
    public var interruptions: Int
    /// The segments of the chosen source, for drawing a hypnogram.
    public var segments: [SleepSegment]

    public init(
        start: Date, end: Date, asleep: TimeInterval, awake: TimeInterval,
        deep: TimeInterval, rem: TimeInterval, core: TimeInterval, unspecified: TimeInterval,
        interruptions: Int, segments: [SleepSegment]
    ) {
        self.start = start
        self.end = end
        self.asleep = asleep
        self.awake = awake
        self.deep = deep
        self.rem = rem
        self.core = core
        self.unspecified = unspecified
        self.interruptions = interruptions
        self.segments = segments
    }

    public var midpoint: Date { start.addingTimeInterval(end.timeIntervalSince(start) / 2) }
    public var hasStages: Bool { deep + rem + core > 0 }
    /// Asleep ÷ (asleep + awake).
    public var efficiency: Double {
        let total = asleep + awake
        return total > 0 ? asleep / total : 0
    }
}

/// All per-day inputs, computed once from `RawHealthData`. "Day" means the calendar day you woke up on.
///
/// Some metrics are kept in two flavours (overnight vs. all-day HRV, sleeping vs. Apple resting heart
/// rate) because they are not interchangeable: scoring always compares like with like.
public struct DayMetrics: Sendable, Hashable, Codable, Identifiable {
    public var day: Date
    public var sleep: SleepSummary?
    /// Geometric mean of SDNN readings taken during the main sleep (ms).
    public var hrvOvernight: Double?
    /// Geometric mean of SDNN readings from the previous day through this morning (ms). Fallback only.
    public var hrvAllDay: Double?
    /// Lowest 30-minute average heart rate during the main sleep (bpm).
    public var sleepingHeartRate: Double?
    /// Apple's resting heart rate estimate for the previous day (bpm). Fallback only.
    public var appleRestingHeartRate: Double?
    public var respiratoryRate: Double?
    public var wristTemperature: Double?
    public var oxygenSaturation: Double?
    /// Session-RPE training load (minutes × effort) of workouts that started this day.
    public var trainingLoad: Double
    public var workouts: [ScoredWorkout]
    public var activeEnergy: Double?

    public var id: Date { day }

    public init(
        day: Date,
        sleep: SleepSummary? = nil,
        hrvOvernight: Double? = nil,
        hrvAllDay: Double? = nil,
        sleepingHeartRate: Double? = nil,
        appleRestingHeartRate: Double? = nil,
        respiratoryRate: Double? = nil,
        wristTemperature: Double? = nil,
        oxygenSaturation: Double? = nil,
        trainingLoad: Double = 0,
        workouts: [ScoredWorkout] = [],
        activeEnergy: Double? = nil
    ) {
        self.day = day
        self.sleep = sleep
        self.hrvOvernight = hrvOvernight
        self.hrvAllDay = hrvAllDay
        self.sleepingHeartRate = sleepingHeartRate
        self.appleRestingHeartRate = appleRestingHeartRate
        self.respiratoryRate = respiratoryRate
        self.wristTemperature = wristTemperature
        self.oxygenSaturation = oxygenSaturation
        self.trainingLoad = trainingLoad
        self.workouts = workouts
        self.activeEnergy = activeEnergy
    }

    /// Best available HRV for display.
    public var hrv: Double? { hrvOvernight ?? hrvAllDay }
    /// Best available resting heart rate for display.
    public var restingHeartRate: Double? { sleepingHeartRate ?? appleRestingHeartRate }
}

/// A workout with the load the engine assigned to it, so the UI can show exactly where numbers come from.
public struct ScoredWorkout: Sendable, Hashable, Codable, Identifiable {
    public var workout: WorkoutRecord
    public var effort: Double
    public var effortSource: WorkoutRecord.EffortSource
    public var load: Double

    public var id: Date { workout.start }

    public init(workout: WorkoutRecord, effort: Double, effortSource: WorkoutRecord.EffortSource, load: Double) {
        self.workout = workout
        self.effort = effort
        self.effortSource = effortSource
        self.load = load
    }
}
