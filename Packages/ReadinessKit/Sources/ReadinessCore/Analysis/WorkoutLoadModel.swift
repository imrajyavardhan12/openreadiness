import Foundation

/// Session-RPE training load (Foster et al., 2001): load = duration in minutes × effort (1–10).
///
/// It's a simple, well-validated model that works for any sport. Effort comes from the best
/// available source, in this order:
/// 1. The effort you rated in the Workout/Fitness app (watchOS 11+)
/// 2. Apple's estimated effort (watchOS 11+)
/// 3. Average heart rate as a fraction of heart-rate reserve (Karvonen), which maps roughly
///    linearly onto the CR-10 effort scale
/// 4. Energy expenditure per minute
/// 5. A moderate default of 4
public struct WorkoutLoadModel: Sendable {
    public var restingHeartRate: Double
    public var maxHeartRate: Double

    public init(restingHeartRate: Double, maxHeartRate: Double) {
        self.restingHeartRate = restingHeartRate
        self.maxHeartRate = maxHeartRate
    }

    /// Age-predicted max heart rate (Tanaka, Monahan & Seals, 2001): 208 − 0.7 × age.
    public static func predictedMaxHeartRate(age: Int?) -> Double {
        208 - 0.7 * Double(age ?? 35)
    }

    public func score(_ workout: WorkoutRecord) -> ScoredWorkout {
        let (effort, source) = effort(for: workout)
        let minutes = max(0, workout.duration / 60)
        return ScoredWorkout(workout: workout, effort: effort, effortSource: source, load: minutes * effort)
    }

    func effort(for workout: WorkoutRecord) -> (Double, WorkoutRecord.EffortSource) {
        if let score = workout.effortScore, score > 0 {
            return (Stats.clamp(score, 1, 10), workout.effortIsEstimated ? .appleEstimated : .userRated)
        }
        if let hr = workout.averageHeartRate, maxHeartRate > restingHeartRate {
            let reserve = (hr - restingHeartRate) / (maxHeartRate - restingHeartRate)
            return (Stats.clamp(reserve * 10, 1, 10), .heartRate)
        }
        if let kcal = workout.activeEnergyKcal, workout.duration > 0 {
            // ~12 kcal/min is a very hard effort for most adults; ~3 kcal/min is an easy walk.
            let perMinute = kcal / (workout.duration / 60)
            return (Stats.clamp(perMinute / 1.2, 1, 10), .energy)
        }
        return (4, .assumed)
    }
}
