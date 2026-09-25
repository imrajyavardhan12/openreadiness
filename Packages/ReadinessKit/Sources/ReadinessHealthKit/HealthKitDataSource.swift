import Foundation
import HealthKit
import ReadinessCore

/// Reads everything the readiness model needs from HealthKit. Read-only: this app never writes health data.
///
/// All queries run concurrently. HealthKit silently returns empty results for types the user
/// declined, so a denied permission simply shows up as a missing contributor rather than an error.
public final class HealthKitDataSource: HealthDataSource, @unchecked Sendable {
    // HKHealthStore is documented as thread-safe; this class holds no other mutable state.
    private let store: HKHealthStore

    public init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    public static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    public static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.respiratoryRate),
            HKQuantityType(.oxygenSaturation),
            HKQuantityType(.appleSleepingWristTemperature),
            HKQuantityType(.activeEnergyBurned),
            HKObjectType.workoutType(),
            HKCharacteristicType(.dateOfBirth),
            HKSeriesType.heartbeat(),
        ]
        if #available(iOS 18.0, watchOS 11.0, macOS 15.0, *) {
            types.insert(HKQuantityType(.workoutEffortScore))
            types.insert(HKQuantityType(.estimatedWorkoutEffortScore))
        }
        return types
    }

    /// On iPhone, requests everything the app reads (readiness + explorer) in one sheet. The watch
    /// app only computes readiness, so it asks for no more than that.
    public func requestAuthorization() async throws {
        #if os(watchOS)
        let types = Self.readTypes
        #else
        let types = Self.readTypes.union(HealthKitMetricsProvider.readTypes)
        #endif
        try await store.requestAuthorization(toShare: [], read: types)
    }

    func fetchSleep(from start: Date, to end: Date) async throws -> [SleepSegment] {
        try await sleepSegments(DateInterval(start: start, end: end))
    }

    public func fetch(from start: Date, to end: Date) async throws -> RawHealthData {
        // Predicates aren't Sendable, so each query builds its own from this interval.
        let range = DateInterval(start: start, end: end)

        async let sleep = sleepSegments(range)
        async let hrv = quantities(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), range)
        async let rmssd = rmssdReadings(range)
        async let heartRate = heartRateBuckets(from: start, to: end)
        async let resting = quantities(.restingHeartRate, unit: .beatsPerMinute, range)
        async let respiratory = quantities(.respiratoryRate, unit: .perMinute, range)
        async let temperature = quantities(.appleSleepingWristTemperature, unit: .degreeCelsius(), range)
        async let oxygen = quantities(.oxygenSaturation, unit: .percent(), range)
        async let workouts = workoutRecords(range)
        async let energy = dailyActiveEnergy(from: start, to: end)

        return try await RawHealthData(
            sleep: sleep,
            hrv: hrv,
            rmssd: rmssd,
            heartRateBuckets: heartRate,
            restingHeartRate: resting,
            respiratoryRate: respiratory,
            wristTemperature: temperature,
            oxygenSaturation: oxygen.map { TimedValue(date: $0.date, value: $0.value * 100) },
            workouts: workouts,
            activeEnergyDaily: energy,
            profile: UserProfile(age: age())
        )
    }

    /// Emits whenever HealthKit has new data for the inputs that drive the score.
    public func changes() -> AsyncStream<Void> {
        // Keep only the newest event so bursts of HealthKit notifications collapse into one refresh.
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let types: [HKSampleType] = [
                HKCategoryType(.sleepAnalysis),
                HKQuantityType(.heartRateVariabilitySDNN),
                HKQuantityType(.restingHeartRate),
                HKObjectType.workoutType(),
            ]
            let queries = types.map { type in
                HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                    if error == nil { continuation.yield() }
                    completion()
                }
            }
            queries.forEach(store.execute)
            let store = store
            continuation.onTermination = { _ in queries.forEach(store.stop) }
        }
    }

    // MARK: - Queries

    private func quantities(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        _ range: DateInterval
    ) async throws -> [TimedValue] {
        let predicate = Self.predicate(range)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store).map {
            TimedValue(date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
        }
    }

    private func sleepSegments(_ range: DateInterval) async throws -> [SleepSegment] {
        let predicate = Self.predicate(range)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store).compactMap { sample in
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }
            let stage: SleepStage = switch value {
            case .inBed: .inBed
            case .awake: .awake
            case .asleepCore: .core
            case .asleepDeep: .deep
            case .asleepREM: .rem
            case .asleepUnspecified: .asleepUnspecified
            @unknown default: .asleepUnspecified
            }
            return SleepSegment(
                start: sample.startDate,
                end: sample.endDate,
                stage: stage,
                sourceID: sample.sourceRevision.source.bundleIdentifier
            )
        }
    }

    /// RMSSD for each overnight heartbeat series (the beat-to-beat data behind Apple's HRV readings).
    ///
    /// Best effort: if heartbeat data is unavailable or declined, readiness falls back to SDNN, so
    /// failures here return what could be computed rather than failing the whole refresh.
    private func rmssdReadings(_ range: DateInterval) async -> [TimedValue] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.heartbeatSeries(Self.predicate(range))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let series = try? await descriptor.result(for: store) else { return [] }

        // Only readings that could fall within a night's sleep are scored as "overnight".
        let calendar = Calendar.current
        let overnight = series.filter {
            let hour = calendar.component(.hour, from: $0.startDate)
            return hour >= 20 || hour < 11
        }

        let cache = RMSSDCache.shared
        var readings: [TimedValue] = []
        var uncached: [HKHeartbeatSeriesSample] = []
        for sample in overnight {
            if let entry = await cache.entry(for: sample.uuid) {
                if let value = entry.rmssd { readings.append(TimedValue(date: sample.startDate, value: value)) }
            } else {
                uncached.append(sample)
            }
        }

        // Read uncached series a few at a time: enough parallelism to be quick, without flooding HealthKit.
        let batchSize = 8
        for start in stride(from: 0, to: uncached.count, by: batchSize) {
            let batch = uncached[start..<min(start + batchSize, uncached.count)]
            let computed = await withTaskGroup(of: (UUID, Date, Double?)?.self) { group in
                for sample in batch {
                    group.addTask { await self.rmssd(for: sample) }
                }
                var results: [(UUID, Date, Double?)] = []
                for await result in group {
                    if let result { results.append(result) }
                }
                return results
            }
            for (id, date, value) in computed {
                await cache.store(RMSSDCache.Entry(date: date, rmssd: value), for: id)
                if let value { readings.append(TimedValue(date: date, value: value)) }
            }
        }
        await cache.persist()
        return readings.sorted { $0.date < $1.date }
    }

    /// nil when the series couldn't be read (so it's retried next time); a nil RMSSD when it was
    /// read but had too few clean beats.
    private func rmssd(for sample: HKHeartbeatSeriesSample) async -> (UUID, Date, Double?)? {
        do {
            var beats: [Heartbeat] = []
            for try await beat in HKHeartbeatSeriesQueryDescriptor(sample).results(for: store) {
                beats.append(Heartbeat(time: beat.timeIntervalSinceStart, precededByGap: beat.precededByGap))
            }
            return (sample.uuid, sample.startDate, RMSSD.compute(beats))
        } catch {
            return nil
        }
    }

    /// 30-minute average heart rate. Far lighter than pulling every raw sample for months of data.
    private func heartRateBuckets(from start: Date, to end: Date) async throws -> [TimedValue] {
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.heartRate), predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: .discreteAverage,
            anchorDate: Calendar.current.startOfDay(for: start),
            intervalComponents: DateComponents(minute: 30)
        )
        let collection = try await descriptor.result(for: store)
        var buckets: [TimedValue] = []
        collection.enumerateStatistics(from: start, to: end) { statistics, _ in
            if let average = statistics.averageQuantity() {
                buckets.append(TimedValue(date: statistics.startDate, value: average.doubleValue(for: .beatsPerMinute)))
            }
        }
        return buckets
    }

    private func dailyActiveEnergy(from start: Date, to end: Date) async throws -> [TimedValue] {
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.activeEnergyBurned), predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: .cumulativeSum,
            anchorDate: Calendar.current.startOfDay(for: start),
            intervalComponents: DateComponents(day: 1)
        )
        let collection = try await descriptor.result(for: store)
        var days: [TimedValue] = []
        collection.enumerateStatistics(from: start, to: end) { statistics, _ in
            if let sum = statistics.sumQuantity() {
                days.append(TimedValue(date: statistics.startDate, value: sum.doubleValue(for: .kilocalorie())))
            }
        }
        return days
    }

    private func workoutRecords(_ range: DateInterval) async throws -> [WorkoutRecord] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(Self.predicate(range))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let workouts = try await descriptor.result(for: store)
        let efforts = try await effortScores(range)

        return workouts.map { workout in
            let interval = DateInterval(start: workout.startDate, end: max(workout.endDate, workout.startDate))
            // Prefer the user's own rating over Apple's estimate.
            let effort = efforts
                .filter { interval.contains($0.date) }
                .sorted { !$0.estimated && $1.estimated }
                .first
            return WorkoutRecord(
                start: workout.startDate,
                end: workout.endDate,
                activityName: workout.workoutActivityType.displayName,
                activeEnergyKcal: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                    .sumQuantity()?.doubleValue(for: .kilocalorie()),
                averageHeartRate: workout.statistics(for: HKQuantityType(.heartRate))?
                    .averageQuantity()?.doubleValue(for: .beatsPerMinute),
                effortScore: effort?.value,
                effortIsEstimated: effort?.estimated ?? false
            )
        }
    }

    private func effortScores(_ range: DateInterval) async throws -> [(date: Date, value: Double, estimated: Bool)] {
        guard #available(iOS 18.0, watchOS 11.0, macOS 15.0, *) else { return [] }
        let unit = HKUnit.appleEffortScore()
        let rated = try await quantities(.workoutEffortScore, unit: unit, range)
        let estimated = try await quantities(.estimatedWorkoutEffortScore, unit: unit, range)
        return rated.map { ($0.date, $0.value, false) } + estimated.map { ($0.date, $0.value, true) }
    }

    private static func predicate(_ range: DateInterval) -> NSPredicate {
        HKQuery.predicateForSamples(withStart: range.start, end: range.end)
    }

    private func age() -> Int? {
        guard let birthday = try? store.dateOfBirthComponents(),
              let date = Calendar.current.date(from: birthday)
        else { return nil }
        return Calendar.current.dateComponents([.year], from: date, to: .now).year
    }
}

extension HKUnit {
    static let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
    static let perMinute = HKUnit.count().unitDivided(by: .minute())
}

extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .running: "Running"
        case .walking: "Walking"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .hiking: "Hiking"
        case .rowing: "Rowing"
        case .elliptical: "Elliptical"
        case .stairClimbing: "Stair Climbing"
        case .yoga: "Yoga"
        case .pilates: "Pilates"
        case .dance: "Dance"
        case .traditionalStrengthTraining: "Strength Training"
        case .functionalStrengthTraining: "Functional Strength Training"
        case .coreTraining: "Core Training"
        case .highIntensityIntervalTraining: "HIIT"
        case .crossTraining: "Cross Training"
        case .mixedCardio: "Mixed Cardio"
        case .tennis: "Tennis"
        case .soccer: "Soccer"
        case .basketball: "Basketball"
        case .golf: "Golf"
        case .downhillSkiing: "Skiing"
        case .snowboarding: "Snowboarding"
        case .climbing: "Climbing"
        case .martialArts: "Martial Arts"
        case .boxing: "Boxing"
        case .cooldown: "Cooldown"
        case .flexibility: "Flexibility"
        default: "Workout"
        }
    }
}
