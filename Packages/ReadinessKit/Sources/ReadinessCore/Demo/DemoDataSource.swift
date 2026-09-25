import Foundation

/// Generates realistic, deterministic synthetic data for the Simulator, SwiftUI previews,
/// screenshots and tests.
///
/// The story it tells over ~5 months: steady base training, a build block, an illness around
/// three weeks ago (HRV down, resting HR / respiratory rate / temperature up), a rest week,
/// then a return to training — so every chart and contributor has something to show.
public struct DemoDataSource: HealthDataSource {
    public var seed: UInt64
    public var calendar: Calendar
    /// When the illness starts, in days before the end date.
    public var illnessDaysAgo: Int

    public init(seed: UInt64 = 42, calendar: Calendar = .current, illnessDaysAgo: Int = 21) {
        self.seed = seed
        self.calendar = calendar
        self.illnessDaysAgo = illnessDaysAgo
    }

    public func requestAuthorization() async throws {}

    public func fetch(from start: Date, to end: Date) async throws -> RawHealthData {
        generate(from: start, to: end)
    }

    public func generate(from start: Date, to end: Date) -> RawHealthData {
        var data = RawHealthData(profile: UserProfile(age: 38))
        let watch = "com.apple.health.demo-watch"

        // Randomness is keyed to each calendar day and generation starts with a warm-up period, so
        // any requested window shows exactly the same values for the same day.
        let requestedFirstDay = calendar.startOfDay(for: start)
        let firstDay = calendar.date(byAdding: .day, value: -Self.warmUpDays, to: requestedFirstDay)!
        let lastDay = calendar.startOfDay(for: end)
        let dayCount = (calendar.dateComponents([.day], from: firstDay, to: lastDay).day ?? 0) + 1
        var fatigue = 0.0 // carries over between days, decays

        for offset in 0..<dayCount {
            let day = calendar.date(byAdding: .day, value: offset, to: firstDay)!
            var rng = SplitMix64(seed: seed ^ (Self.dayNumber(day) &* 0x9E37_79B9_7F4A_7C15))
            let daysAgo = dayCount - 1 - offset
            let weekday = calendar.component(.weekday, from: day)
            let sick = (illnessDaysAgo - 4...illnessDaysAgo).contains(daysAgo)
            let recovering = (illnessDaysAgo - 9..<illnessDaysAgo - 4).contains(daysAgo)
            let buildBlock = (illnessDaysAgo + 3...illnessDaysAgo + 16).contains(daysAgo)

            // Sleep: bed ~23:00 ± 40 min, 6.3–8.3 h, shorter on Fridays.
            let bedtimeOffset = rng.normal(mean: -60, sd: 25) + (weekday == 7 ? 50 : 0)
            let sleepStart = calendar.date(byAdding: .minute, value: Int(bedtimeOffset), to: day)!
            var sleepHours = rng.normal(mean: 7.4, sd: 0.55) - (weekday == 6 ? 0.7 : 0) + (sick ? 0.6 : 0)
            if daysAgo == 1 { sleepHours = 5.9 } // one short night recently, to make the demo interesting
            sleepHours = min(max(sleepHours, 4.5), 9.5)
            let (segments, sleepEnd) = sleepNight(start: sleepStart, hours: sleepHours, source: watch, rng: &rng)
            if daysAgo > 0 || calendar.component(.hour, from: end) >= 8 {
                data.sleep += segments
            }

            // Physiology
            let illness = sick ? 1.0 : (recovering ? 0.45 : 0)
            // Short sleep lowers the next morning's HRV and raises heart rate, as it does in real life.
            let sleepEffect = sleepHours - 7.4
            let hrvMean = 52 * exp(-0.35 * illness - 0.12 * fatigue + 0.07 * sleepEffect)
            let rhrMean = 52 + 6 * illness + 2.5 * fatigue - 0.8 * sleepEffect
            for i in 0..<Int(rng.uniform(3, 6)) {
                let t = sleepStart.addingTimeInterval(Double(i) * sleepHours * 3600 / 5 + 1200)
                data.hrv.append(TimedValue(date: t, value: max(12, hrvMean * exp(rng.normal(mean: 0, sd: 0.18)))))
                // RMSSD from the same reading's beat-to-beat data: tracks recovery a little more tightly.
                data.rmssd.append(TimedValue(date: t, value: max(10, hrvMean * 1.08 * exp(rng.normal(mean: 0, sd: 0.13)))))
            }
            for hour in [10, 14, 17] where daysAgo > 0 {
                let t = calendar.date(byAdding: .hour, value: hour, to: day)!
                data.hrv.append(TimedValue(date: t, value: max(10, hrvMean * 0.8 * exp(rng.normal(mean: 0, sd: 0.25)))))
            }

            var bucket = sleepStart
            while bucket < sleepEnd {
                let progress = bucket.timeIntervalSince(sleepStart) / sleepEnd.timeIntervalSince(sleepStart)
                let dip = 4 * sin(progress * .pi) // lowest in the middle of the night
                data.heartRateBuckets.append(TimedValue(date: bucket, value: rhrMean + 4 - dip + rng.normal(mean: 0, sd: 0.8)))
                bucket = bucket.addingTimeInterval(1800)
            }
            if daysAgo > 0 {
                let noon = calendar.date(byAdding: .hour, value: 12, to: day)!
                data.restingHeartRate.append(TimedValue(date: noon, value: rhrMean + 4 + rng.normal(mean: 0, sd: 1)))
            }

            let mid = sleepStart.addingTimeInterval(sleepHours * 1800)
            data.respiratoryRate.append(TimedValue(date: mid, value: 14.6 + 1.6 * illness + rng.normal(mean: 0, sd: 0.3)))
            data.wristTemperature.append(TimedValue(date: sleepStart, value: 34.9 + 0.8 * illness + rng.normal(mean: 0, sd: 0.12)))
            for i in 0..<3 {
                let t = sleepStart.addingTimeInterval(Double(i + 1) * 5400)
                data.oxygenSaturation.append(TimedValue(date: t, value: min(100, 96.5 - 1.5 * illness + rng.normal(mean: 0, sd: 0.6))))
            }

            // Training: rest on Mondays, long run on Sundays, intervals Wednesdays.
            var dayLoad = 0.0
            if !sick && !recovering && weekday != 2 && (daysAgo > 0 || calendar.component(.hour, from: end) >= 19) {
                let base: (name: String, minutes: Double, effort: Double)? = switch weekday {
                case 1: ("Running", 75, 6)
                case 4: ("Running", 45, 8)
                case 3, 5: ("Functional Strength Training", 40, 6)
                case 6: rng.uniform(0, 1) < 0.5 ? ("Cycling", 50, 5) : nil
                case 7: ("Running", 35, 4)
                default: nil
                }
                if var session = base {
                    if buildBlock { session.minutes *= 1.45; session.effort = min(10, session.effort + 1) }
                    if (illnessDaysAgo - 16..<illnessDaysAgo - 9).contains(daysAgo) { session.minutes *= 0.6 }
                    let startTime = calendar.date(byAdding: .hour, value: 18, to: day)!
                    let minutes = session.minutes * rng.uniform(0.9, 1.1)
                    let rated = rng.uniform(0, 1) < 0.6
                    let effort = min(10, max(1, (session.effort + rng.normal(mean: 0, sd: 0.7)).rounded()))
                    data.workouts.append(WorkoutRecord(
                        start: startTime,
                        end: startTime.addingTimeInterval(minutes * 60),
                        activityName: session.name,
                        activeEnergyKcal: minutes * (4 + effort * 0.9),
                        averageHeartRate: 60 + effort * 11,
                        effortScore: effort,
                        effortIsEstimated: !rated
                    ))
                    dayLoad = minutes * effort
                }
            }
            fatigue = fatigue * 0.6 + dayLoad / 400

            let energy = (sick ? 180 : 420) + dayLoad * 1.1 + rng.normal(mean: 0, sd: 60)
            data.activeEnergyDaily.append(TimedValue(date: day, value: max(80, daysAgo == 0 ? energy * 0.4 : energy)))
        }
        return data.trimmed(before: calendar.date(byAdding: .day, value: -1, to: requestedFirstDay)!)
    }

    static let warmUpDays = 42

    /// A stable per-day number, independent of time zone offsets within the day.
    public static func dayNumber(_ day: Date) -> UInt64 {
        UInt64(max(0, (day.timeIntervalSinceReferenceDate / 86_400).rounded()))
    }

    /// A plausible hypnogram: ~90-minute cycles, more deep sleep early, more REM late, a couple of brief wakes.
    private func sleepNight(start: Date, hours: Double, source: String, rng: inout SplitMix64) -> ([SleepSegment], Date) {
        var segments: [SleepSegment] = []
        var t = start
        let end = start.addingTimeInterval(hours * 3600)
        let cycles = Int((hours * 60 / 90).rounded(.up))
        for cycle in 0..<cycles {
            let early = Double(cycles - cycle) / Double(cycles)
            let plan: [(SleepStage, Double)] = [
                (.core, rng.uniform(25, 40)),
                (.deep, rng.uniform(8, 18) * early * 1.6),
                (.core, rng.uniform(10, 20)),
                (.rem, rng.uniform(8, 18) * (1.6 - early)),
            ]
            for (stage, minutes) in plan where minutes > 1 {
                let segEnd = min(end, t.addingTimeInterval(minutes * 60))
                if segEnd > t { segments.append(SleepSegment(start: t, end: segEnd, stage: stage, sourceID: source)) }
                t = segEnd
            }
            if cycle > 0, rng.uniform(0, 1) < 0.35, t < end {
                let wakeEnd = min(end, t.addingTimeInterval(rng.uniform(2, 9) * 60))
                segments.append(SleepSegment(start: t, end: wakeEnd, stage: .awake, sourceID: source))
                t = wakeEnd
            }
            if t >= end { break }
        }
        if t < end { segments.append(SleepSegment(start: t, end: end, stage: .core, sourceID: source)) }
        segments.append(SleepSegment(start: start.addingTimeInterval(-900), end: end.addingTimeInterval(300), stage: .inBed, sourceID: source))
        return (segments, end)
    }
}

extension RawHealthData {
    /// Drops samples that start before `date` (used to discard the demo warm-up period).
    func trimmed(before date: Date) -> RawHealthData {
        var copy = self
        copy.sleep = sleep.filter { $0.start >= date }
        copy.hrv = hrv.filter { $0.date >= date }
        copy.rmssd = rmssd.filter { $0.date >= date }
        copy.heartRateBuckets = heartRateBuckets.filter { $0.date >= date }
        copy.restingHeartRate = restingHeartRate.filter { $0.date >= date }
        copy.respiratoryRate = respiratoryRate.filter { $0.date >= date }
        copy.wristTemperature = wristTemperature.filter { $0.date >= date }
        copy.oxygenSaturation = oxygenSaturation.filter { $0.date >= date }
        copy.workouts = workouts.filter { $0.start >= date }
        copy.activeEnergyDaily = activeEnergyDaily.filter { $0.date >= date }
        return copy
    }
}

/// Tiny deterministic RNG so demo data is identical on every run and platform.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    public mutating func uniform(_ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * Double(next() >> 11) / Double(1 << 53)
    }

    /// Box–Muller.
    public mutating func normal(mean: Double, sd: Double) -> Double {
        let u1 = max(uniform(0, 1), .leastNonzeroMagnitude)
        let u2 = uniform(0, 1)
        return mean + sd * sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}
