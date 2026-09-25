import Foundation
import ReadinessCore

/// Synthetic data for every explorer screen, consistent with `DemoDataSource`: sleep, HRV,
/// heart rate, vitals and workouts come from the same generator the readiness engine sees;
/// other metrics (steps, rings, mobility…) are derived around them. Deterministic per day.
public struct DemoMetricsProvider: HealthMetricsProvider {
    public var seed: UInt64
    public var calendar: Calendar
    public var now: Date
    private let raw: RawHealthData

    public static let historyDays = 430

    public init(seed: UInt64 = 42, calendar: Calendar = .current, now: Date = .now) {
        self.seed = seed
        self.calendar = calendar
        self.now = now
        let start = calendar.date(byAdding: .day, value: -Self.historyDays, to: calendar.startOfDay(for: now))!
        self.raw = DemoDataSource(seed: seed, calendar: calendar).generate(from: start, to: now)
    }

    public func requestAuthorization() async throws {}

    public func profile() async -> HealthProfile { HealthProfile(age: raw.profile.age) }

    // MARK: - Daily series

    public func daily(_ metric: HealthMetric, in interval: DateInterval) async throws -> [DailyValue] {
        let values: [DailyValue] = switch metric {
        case .hrv: dailyMean(raw.hrv)
        case .restingHeartRate: dailyMean(raw.restingHeartRate)
        case .respiratoryRate: dailyMean(raw.respiratoryRate)
        case .oxygenSaturation: dailyMean(raw.oxygenSaturation)
        case .wristTemperature: dailyMean(raw.wristTemperature)
        case .activeEnergy: raw.activeEnergyDaily.map { DailyValue(date: calendar.startOfDay(for: $0.date), value: $0.value) }
        default: synthesized(metric)
        }
        return values.filter { interval.contains($0.date) }
    }

    private func dailyMean(_ samples: [TimedValue]) -> [DailyValue] {
        Dictionary(grouping: samples) { calendar.startOfDay(for: $0.date) }
            .compactMap { day, items in Stats.mean(items.map(\.value)).map { DailyValue(date: day, value: $0) } }
            .sorted { $0.date < $1.date }
    }

    private var days: [Date] {
        let first = raw.activeEnergyDaily.first.map { calendar.startOfDay(for: $0.date) } ?? now
        let last = calendar.startOfDay(for: now)
        var result: [Date] = []
        var day = first
        while day <= last {
            result.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }

    private func workouts(on day: Date) -> [WorkoutRecord] {
        raw.workouts.filter { calendar.isDate($0.start, inSameDayAs: day) }
    }

    private func rng(_ day: Date, _ salt: UInt64) -> SplitMix64 {
        SplitMix64(seed: seed &+ salt &* 0x2545_F491_4F6C_DD1D ^ DemoDataSource.dayNumber(day))
    }

    /// Fraction of the (demo) year elapsed, for slow fitness trends.
    private func progress(_ day: Date) -> Double {
        let total = Double(Self.historyDays)
        let elapsed = total - (calendar.dateComponents([.day], from: day, to: now).day.map(Double.init) ?? 0)
        return max(0, min(1, elapsed / total))
    }

    private func steps(on day: Date) -> Double {
        var r = rng(day, 1)
        let weekday = calendar.component(.weekday, from: day)
        let runMinutes = workouts(on: day).filter { $0.activityName == "Running" }.reduce(0) { $0 + $1.duration / 60 }
        let isToday = calendar.isDateInToday(day)
        let base = r.normal(mean: weekday == 1 || weekday == 7 ? 8200 : 6900, sd: 1600)
        let total = max(900, base + runMinutes * 165)
        return isToday ? total * 0.45 : total
    }

    private func synthesized(_ metric: HealthMetric) -> [DailyValue] {
        let restingMedian = Stats.median(raw.restingHeartRate.map(\.value)) ?? 56
        let sleepingMinimum = Dictionary(grouping: raw.heartRateBuckets) { calendar.startOfDay(for: $0.date) }
            .mapValues { $0.map(\.value).min() ?? restingMedian }
        return days.compactMap { day -> DailyValue? in
            var r = rng(day, UInt64(HealthMetric.allCases.firstIndex(of: metric)! + 10))
            let dayWorkouts = workouts(on: day)
            let p = progress(day)
            switch metric {
            case .heartRate:
                let sleepMin = sleepingMinimum[day] ?? restingMedian
                let peak = dayWorkouts.compactMap(\.averageHeartRate).max().map { $0 + 18 } ?? r.normal(mean: 118, sd: 8)
                return DailyValue(date: day, value: r.normal(mean: 71, sd: 3), min: sleepMin - 2, max: peak)
            case .walkingHeartRate:
                return DailyValue(date: day, value: r.normal(mean: 101 - 4 * p, sd: 2.5))
            case .heartRateRecovery:
                guard !dayWorkouts.isEmpty else { return nil }
                return DailyValue(date: day, value: r.normal(mean: 24 + 3 * p, sd: 3.5))
            case .vo2Max:
                guard dayWorkouts.contains(where: { $0.activityName == "Running" }) else { return nil }
                return DailyValue(date: day, value: r.normal(mean: 43.2 + 2.6 * p, sd: 0.5))
            case .steps:
                return DailyValue(date: day, value: steps(on: day).rounded())
            case .exerciseTime:
                let workoutMinutes = dayWorkouts.reduce(0) { $0 + $1.duration / 60 }
                return DailyValue(date: day, value: max(0, (workoutMinutes + r.normal(mean: 14, sd: 7)).rounded()))
            case .standTime:
                return DailyValue(date: day, value: max(40, r.normal(mean: 205, sd: 40)).rounded())
            case .distance:
                return DailyValue(date: day, value: steps(on: day) * 0.76 / 1000)
            case .flightsClimbed:
                return DailyValue(date: day, value: max(0, r.normal(mean: 9, sd: 4)).rounded())
            case .walkingSpeed:
                guard r.uniform(0, 1) < 0.45 else { return nil }
                return DailyValue(date: day, value: r.normal(mean: 5.0 + 0.2 * p, sd: 0.15))
            case .walkingStepLength:
                guard r.uniform(0, 1) < 0.45 else { return nil }
                return DailyValue(date: day, value: r.normal(mean: 73, sd: 1.5))
            case .walkingAsymmetry:
                guard r.uniform(0, 1) < 0.35 else { return nil }
                return DailyValue(date: day, value: max(0, r.normal(mean: 1.8, sd: 1.2)))
            case .environmentalAudio:
                let weekend = [1, 7].contains(calendar.component(.weekday, from: day))
                return DailyValue(date: day, value: r.normal(mean: weekend ? 70 : 64, sd: 4))
            case .headphoneAudio:
                guard r.uniform(0, 1) < 0.65 else { return nil }
                return DailyValue(date: day, value: r.normal(mean: 71, sd: 5))
            case .timeInDaylight:
                let weekend = [1, 7].contains(calendar.component(.weekday, from: day))
                let seasonal = 25 * sin(2 * .pi * Double(calendar.ordinality(of: .day, in: .year, for: day) ?? 180) / 365 - .pi / 2)
                return DailyValue(date: day, value: max(0, r.normal(mean: (weekend ? 95 : 45) - seasonal, sd: 22)).rounded())
            case .hrv, .restingHeartRate, .respiratoryRate, .oxygenSaturation, .wristTemperature, .activeEnergy:
                return nil // taken from the shared generator above
            }
        }
    }

    // MARK: - Rings, workouts, intraday

    public func activityRings(in interval: DateInterval) async throws -> [ActivityRingDay] {
        let energy = Dictionary(raw.activeEnergyDaily.map { (calendar.startOfDay(for: $0.date), $0.value) }, uniquingKeysWith: +)
        let exercise = Dictionary(synthesized(.exerciseTime).map { ($0.date, $0.value) }, uniquingKeysWith: +)
        return days.filter { interval.contains($0) }.map { day in
            var r = rng(day, 99)
            return ActivityRingDay(
                date: day,
                move: energy[day] ?? 0, moveGoal: 500,
                exercise: exercise[day] ?? 0, exerciseGoal: 30,
                stand: calendar.isDateInToday(day) ? 7 : max(4, r.normal(mean: 12, sd: 2).rounded()), standGoal: 12
            )
        }
    }

    public func workouts(in interval: DateInterval) async throws -> [WorkoutSummary] {
        raw.workouts.filter { interval.contains($0.start) }.map(summary)
    }

    private func summary(_ workout: WorkoutRecord) -> WorkoutSummary {
        var r = SplitMix64(seed: seed ^ UInt64(workout.start.timeIntervalSinceReferenceDate))
        let bytes = (0..<16).map { _ in UInt8(truncatingIfNeeded: r.next()) }
        let uuid = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                               bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        let hours = workout.duration / 3600
        let distance: Double? = switch workout.activityName {
        case "Running": hours * r.normal(mean: 10.6, sd: 0.6) * 1000
        case "Cycling": hours * r.normal(mean: 24, sd: 2) * 1000
        default: nil
        }
        return WorkoutSummary(
            id: uuid,
            activityName: workout.activityName,
            start: workout.start,
            end: workout.end,
            activeEnergyKcal: workout.activeEnergyKcal,
            distanceMeters: distance,
            averageHeartRate: workout.averageHeartRate,
            maxHeartRate: workout.averageHeartRate.map { $0 + 16 }
        )
    }

    public func heartRateSamples(in interval: DateInterval) async throws -> [TimedValue] {
        guard let workout = raw.workouts.first(where: { $0.start < interval.end && $0.end > interval.start }) else { return [] }
        var r = SplitMix64(seed: seed ^ UInt64(workout.start.timeIntervalSinceReferenceDate))
        let average = workout.averageHeartRate ?? 130
        let intervals = (workout.effortScore ?? 5) >= 8
        var samples: [TimedValue] = []
        var t = workout.start
        var hr = 95.0
        while t < workout.end {
            let elapsed = t.timeIntervalSince(workout.start)
            let remaining = workout.end.timeIntervalSince(t)
            var target = average
            if elapsed < 300 { target = 95 + (average - 95) * elapsed / 300 }             // warm-up
            if remaining < 240 { target = average - 25 * (1 - remaining / 240) }           // cool-down
            if intervals, elapsed > 600, Int(elapsed / 180) % 2 == 0 { target += 17 }     // work bouts
            hr += (target - hr) * 0.08 + r.normal(mean: 0, sd: 1.2)
            samples.append(TimedValue(date: t, value: hr))
            t = t.addingTimeInterval(5)
        }
        return samples.filter { interval.contains($0.date) }
    }

    public func intraday(on day: Date) async throws -> IntradayDay {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        let span = DateInterval(start: dayStart, end: min(dayEnd, now))
        let sleep = raw.sleep.filter { $0.end > dayStart && $0.start < dayEnd && $0.stage != .inBed }
        let asleep = sleep.filter { $0.stage.isAsleep }
        let dayWorkouts = raw.workouts.filter { $0.start < dayEnd && $0.end > dayStart }
        var r = rng(dayStart, 500)

        var buckets: [RangeBucket] = []
        var t = dayStart
        var level = 72.0
        while t < span.end {
            let mid = t.addingTimeInterval(150)
            let hour = calendar.component(.hour, from: t)
            var target: Double
            if asleep.contains(where: { $0.start <= mid && $0.end > mid }) {
                target = raw.heartRateBuckets.first { abs($0.date.timeIntervalSince(mid)) < 1800 }?.value ?? 55
            } else if let workout = dayWorkouts.first(where: { $0.start <= mid && $0.end > mid }) {
                target = workout.averageHeartRate ?? 135
            } else {
                target = [8, 12, 18].contains(hour) ? 88 : 70
            }
            level += (target - level) * 0.5 + r.normal(mean: 0, sd: 2)
            buckets.append(RangeBucket(start: t, min: level - r.uniform(2, 6), average: level, max: level + r.uniform(3, 12)))
            t = t.addingTimeInterval(300)
        }

        let totalSteps = steps(on: dayStart)
        let weights: [Double] = (0..<24).map { hour in
            let inWorkout = dayWorkouts.contains { calendar.component(.hour, from: $0.start) == hour }
            switch hour {
            case 0..<6: return 0
            case 7, 8, 17, 18: return inWorkout ? 12 : 4
            case 6, 22, 23: return 0.5
            default: return inWorkout ? 12 : 2
            }
        }
        let weightSum = weights.reduce(0, +)
        let hourlySteps = weights.enumerated().compactMap { hour, weight -> TimedValue? in
            let start = calendar.date(byAdding: .hour, value: hour, to: dayStart)!
            guard start < span.end else { return nil }
            return TimedValue(date: start, value: (totalSteps * weight / weightSum * r.uniform(0.7, 1.3)).rounded())
        }

        return IntradayDay(
            day: dayStart,
            heartRate: buckets,
            hourlySteps: hourlySteps,
            sleep: sleep,
            workouts: dayWorkouts.map(summary)
        )
    }
}
