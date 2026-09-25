import Foundation
import HealthInsights
import HealthKit
import ReadinessCore

/// Reads explorer data from HealthKit, one metric at a time.
///
/// Daily values come from `HKStatisticsCollectionQuery` (HealthKit aggregates on its side and
/// de-duplicates overlapping iPhone + Watch samples), so a year of steps is 365 numbers rather than
/// hundreds of thousands of samples.
public final class HealthKitMetricsProvider: HealthMetricsProvider, @unchecked Sendable {
    // HKHealthStore is thread-safe; no other mutable state.
    private let store: HKHealthStore
    private let calendar: Calendar

    public init(store: HKHealthStore = HKHealthStore(), calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
    }

    /// HealthKit type, unit and display scale for each metric.
    struct Mapping {
        var identifier: HKQuantityTypeIdentifier
        var unit: HKUnit
        var scale: Double = 1
    }

    static func mapping(for metric: HealthMetric) -> Mapping {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        return switch metric {
        case .heartRate: Mapping(identifier: .heartRate, unit: bpm)
        case .restingHeartRate: Mapping(identifier: .restingHeartRate, unit: bpm)
        case .walkingHeartRate: Mapping(identifier: .walkingHeartRateAverage, unit: bpm)
        case .hrv: Mapping(identifier: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        case .heartRateRecovery: Mapping(identifier: .heartRateRecoveryOneMinute, unit: bpm)
        case .vo2Max: Mapping(identifier: .vo2Max, unit: HKUnit(from: "ml/kg*min"))
        case .steps: Mapping(identifier: .stepCount, unit: .count())
        case .activeEnergy: Mapping(identifier: .activeEnergyBurned, unit: .kilocalorie())
        case .exerciseTime: Mapping(identifier: .appleExerciseTime, unit: .minute())
        case .standTime: Mapping(identifier: .appleStandTime, unit: .minute())
        case .distance: Mapping(identifier: .distanceWalkingRunning, unit: .meterUnit(with: .kilo))
        case .flightsClimbed: Mapping(identifier: .flightsClimbed, unit: .count())
        case .respiratoryRate: Mapping(identifier: .respiratoryRate, unit: bpm)
        case .oxygenSaturation: Mapping(identifier: .oxygenSaturation, unit: .percent(), scale: 100)
        case .wristTemperature: Mapping(identifier: .appleSleepingWristTemperature, unit: .degreeCelsius())
        case .walkingSpeed: Mapping(identifier: .walkingSpeed, unit: .meter().unitDivided(by: .second()), scale: 3.6)
        case .walkingStepLength: Mapping(identifier: .walkingStepLength, unit: .meterUnit(with: .centi))
        case .walkingAsymmetry: Mapping(identifier: .walkingAsymmetryPercentage, unit: .percent(), scale: 100)
        case .environmentalAudio: Mapping(identifier: .environmentalAudioExposure, unit: .decibelAWeightedSoundPressureLevel())
        case .headphoneAudio: Mapping(identifier: .headphoneAudioExposure, unit: .decibelAWeightedSoundPressureLevel())
        case .timeInDaylight: Mapping(identifier: .timeInDaylight, unit: .minute())
        }
    }

    public static var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>(HealthMetric.allCases.map { HKQuantityType(mapping(for: $0).identifier) })
        types.insert(HKObjectType.activitySummaryType())
        types.insert(HKObjectType.workoutType())
        types.insert(HKCategoryType(.sleepAnalysis))
        types.insert(HKCharacteristicType(.dateOfBirth))
        types.insert(HKQuantityType(.distanceCycling))
        types.insert(HKQuantityType(.distanceSwimming))
        return types
    }

    public func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: Self.readTypes.union(HealthKitDataSource.readTypes))
    }

    public func profile() async -> HealthProfile {
        guard let birthday = try? store.dateOfBirthComponents(), let date = calendar.date(from: birthday) else {
            return HealthProfile()
        }
        return HealthProfile(age: calendar.dateComponents([.year], from: date, to: .now).year)
    }

    // MARK: - Daily series

    public func daily(_ metric: HealthMetric, in interval: DateInterval) async throws -> [DailyValue] {
        let mapping = Self.mapping(for: metric)
        let options: HKStatisticsOptions = switch metric.aggregation {
        case .sum: .cumulativeSum
        case .average: .discreteAverage
        case .range: [.discreteAverage, .discreteMin, .discreteMax]
        }
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(
                type: HKQuantityType(mapping.identifier),
                predicate: HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
            ),
            options: options,
            anchorDate: calendar.startOfDay(for: interval.start),
            // Range metrics (heart rate) are read hourly, then combined into a time-weighted daily average.
            intervalComponents: metric.aggregation == .range ? DateComponents(hour: 1) : DateComponents(day: 1)
        )
        let collection = try await descriptor.result(for: store)
        var values: [DailyValue] = []
        collection.enumerateStatistics(from: interval.start, to: interval.end) { statistics, _ in
            let main = metric.aggregation == .sum ? statistics.sumQuantity() : statistics.averageQuantity()
            guard let main else { return }
            values.append(DailyValue(
                date: statistics.startDate,
                value: main.doubleValue(for: mapping.unit) * mapping.scale,
                min: statistics.minimumQuantity().map { $0.doubleValue(for: mapping.unit) * mapping.scale },
                max: statistics.maximumQuantity().map { $0.doubleValue(for: mapping.unit) * mapping.scale }
            ))
        }
        return metric.aggregation == .range ? SeriesAnalytics.dailyFromHourly(values, calendar: calendar) : values
    }

    // MARK: - Activity rings

    public func activityRings(in interval: DateInterval) async throws -> [ActivityRingDay] {
        var start = calendar.dateComponents([.era, .year, .month, .day], from: interval.start)
        var end = calendar.dateComponents([.era, .year, .month, .day], from: interval.end)
        start.calendar = calendar
        end.calendar = calendar
        let descriptor = HKActivitySummaryQueryDescriptor(
            predicate: HKQuery.predicate(forActivitySummariesBetweenStart: start, end: end)
        )
        let bpmMinute = HKUnit.minute()
        return try await descriptor.result(for: store).compactMap { summary in
            guard let date = summary.dateComponents(for: calendar).date else { return nil }
            return ActivityRingDay(
                date: calendar.startOfDay(for: date),
                move: summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                moveGoal: summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()),
                exercise: summary.appleExerciseTime.doubleValue(for: bpmMinute),
                exerciseGoal: summary.exerciseTimeGoal?.doubleValue(for: bpmMinute) ?? 30,
                stand: summary.appleStandHours.doubleValue(for: .count()),
                standGoal: summary.standHoursGoal?.doubleValue(for: .count()) ?? 12
            )
        }
        .sorted { $0.date < $1.date }
    }

    // MARK: - Workouts

    public func workouts(in interval: DateInterval) async throws -> [WorkoutSummary] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: interval.start, end: interval.end))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let bpm = HKUnit.count().unitDivided(by: .minute())
        return try await descriptor.result(for: store).map { workout in
            let heartRate = workout.statistics(for: HKQuantityType(.heartRate))
            let distance = [HKQuantityTypeIdentifier.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
                .lazy
                .compactMap { workout.statistics(for: HKQuantityType($0))?.sumQuantity()?.doubleValue(for: .meter()) }
                .first
            return WorkoutSummary(
                id: workout.uuid,
                activityName: workout.workoutActivityType.displayName,
                start: workout.startDate,
                end: workout.endDate,
                activeEnergyKcal: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                distanceMeters: distance,
                averageHeartRate: heartRate?.averageQuantity()?.doubleValue(for: bpm),
                maxHeartRate: heartRate?.maximumQuantity()?.doubleValue(for: bpm)
            )
        }
    }

    public func heartRateSamples(in interval: DateInterval) async throws -> [TimedValue] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.heartRate), predicate: HKQuery.predicateForSamples(withStart: interval.start, end: interval.end))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let bpm = HKUnit.count().unitDivided(by: .minute())
        return try await descriptor.result(for: store).map {
            TimedValue(date: $0.startDate, value: $0.quantity.doubleValue(for: bpm))
        }
    }

    // MARK: - One day

    public func intraday(on day: Date) async throws -> IntradayDay {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        let interval = DateInterval(start: dayStart, end: dayEnd)

        async let heartRate = heartRateBuckets(in: interval)
        async let steps = hourlySteps(in: interval)
        async let sleep = sleepSegments(in: interval)
        async let workouts = workouts(in: interval)
        return try await IntradayDay(day: dayStart, heartRate: heartRate, hourlySteps: steps, sleep: sleep, workouts: workouts)
    }

    private func heartRateBuckets(in interval: DateInterval) async throws -> [RangeBucket] {
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.heartRate), predicate: HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)),
            options: [.discreteAverage, .discreteMin, .discreteMax],
            anchorDate: interval.start,
            intervalComponents: DateComponents(minute: 5)
        )
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let collection = try await descriptor.result(for: store)
        var buckets: [RangeBucket] = []
        collection.enumerateStatistics(from: interval.start, to: interval.end) { statistics, _ in
            guard let average = statistics.averageQuantity() else { return }
            let mean = average.doubleValue(for: bpm)
            buckets.append(RangeBucket(
                start: statistics.startDate,
                min: statistics.minimumQuantity()?.doubleValue(for: bpm) ?? mean,
                average: mean,
                max: statistics.maximumQuantity()?.doubleValue(for: bpm) ?? mean
            ))
        }
        return buckets
    }

    private func hourlySteps(in interval: DateInterval) async throws -> [TimedValue] {
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.stepCount), predicate: HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)),
            options: .cumulativeSum,
            anchorDate: interval.start,
            intervalComponents: DateComponents(hour: 1)
        )
        let collection = try await descriptor.result(for: store)
        var hours: [TimedValue] = []
        collection.enumerateStatistics(from: interval.start, to: interval.end) { statistics, _ in
            if let sum = statistics.sumQuantity() {
                hours.append(TimedValue(date: statistics.startDate, value: sum.doubleValue(for: .count())))
            }
        }
        return hours
    }

    private func sleepSegments(in interval: DateInterval) async throws -> [SleepSegment] {
        // Include the night that started the evening before.
        let start = calendar.date(byAdding: .hour, value: -8, to: interval.start)!
        let raw = try await HealthKitDataSource(store: store).fetchSleep(from: start, to: interval.end)
        guard let source = SleepAnalyzer(calendar: calendar).preferredSourceID(in: raw) else { return [] }
        return raw.filter { $0.sourceID == source && $0.stage != .inBed && $0.end > interval.start }
    }
}
