import Foundation

/// Reduces raw samples to one `DayMetrics` per wake day.
public struct DayMetricsBuilder: Sendable {
    public var calendar: Calendar
    /// Minimum number of 30-minute heart-rate buckets inside the sleep window before trusting "lowest bucket".
    public var minimumSleepingHeartRateBuckets = 4
    public var maxHeartRateOverride: Double?

    public init(calendar: Calendar, maxHeartRateOverride: Double? = nil) {
        self.calendar = calendar
        self.maxHeartRateOverride = maxHeartRateOverride
    }

    /// Builds metrics for every day from `firstDay` through `lastDay` inclusive, oldest first.
    public func build(from raw: RawHealthData, firstDay: Date, lastDay: Date) -> [DayMetrics] {
        let sleepAnalyzer = SleepAnalyzer(calendar: calendar)
        let hrv = SortedSeries(raw.hrv)
        let heartRate = SortedSeries(raw.heartRateBuckets)
        let resting = SortedSeries(raw.restingHeartRate)
        let respiratory = SortedSeries(raw.respiratoryRate)
        let temperature = SortedSeries(raw.wristTemperature)
        let oxygen = SortedSeries(raw.oxygenSaturation)

        let loadModel = WorkoutLoadModel(
            restingHeartRate: Stats.median(raw.restingHeartRate.map(\.value)) ?? 60,
            maxHeartRate: maxHeartRateOverride ?? WorkoutLoadModel.predictedMaxHeartRate(age: raw.profile.age)
        )
        let workoutsByDay = Dictionary(grouping: raw.workouts.map(loadModel.score)) {
            calendar.startOfDay(for: $0.workout.start)
        }
        let energyByDay = Dictionary(
            raw.activeEnergyDaily.map { (calendar.startOfDay(for: $0.date), $0.value) },
            uniquingKeysWith: +
        )

        var result: [DayMetrics] = []
        var day = calendar.startOfDay(for: firstDay)
        let end = calendar.startOfDay(for: lastDay)
        while day <= end {
            let sleep = sleepAnalyzer.summarize(raw.sleep, wakeDay: day)
            let nightWindow = sleepAnalyzer.nightWindow(for: day)
            // Vitals are read from the actual sleep (with a little slack), or the whole night window if no sleep was tracked.
            let vitalsWindow = sleep.map {
                DateInterval(start: $0.start.addingTimeInterval(-30 * 60), end: $0.end.addingTimeInterval(30 * 60))
            } ?? nightWindow
            let previousDay = calendar.date(byAdding: .day, value: -1, to: day)!
            let morningCutoff = calendar.date(byAdding: .hour, value: 10, to: day)!

            var metrics = DayMetrics(day: day, sleep: sleep)

            if let sleep {
                let asleep = DateInterval(start: sleep.start, end: sleep.end)
                metrics.hrvOvernight = Stats.geometricMean(hrv.values(in: asleep))
                let buckets = heartRate.values(in: asleep)
                if buckets.count >= minimumSleepingHeartRateBuckets {
                    metrics.sleepingHeartRate = buckets.min()
                }
            }
            metrics.hrvAllDay = Stats.geometricMean(hrv.values(in: DateInterval(start: previousDay, end: morningCutoff)))
            metrics.appleRestingHeartRate = resting.values(in: DateInterval(start: previousDay, end: day)).last
            metrics.respiratoryRate = Stats.median(respiratory.values(in: vitalsWindow))
            metrics.wristTemperature = Stats.mean(temperature.values(in: nightWindow))
            metrics.oxygenSaturation = Stats.median(oxygen.values(in: vitalsWindow))

            let workouts = (workoutsByDay[day] ?? []).sorted { $0.workout.start < $1.workout.start }
            metrics.workouts = workouts
            metrics.trainingLoad = workouts.reduce(0) { $0 + $1.load }
            metrics.activeEnergy = energyByDay[day]

            result.append(metrics)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }
}

/// A date-sorted series with O(log n) range lookup.
struct SortedSeries {
    private let items: [TimedValue]

    init(_ items: [TimedValue]) {
        self.items = items.sorted { $0.date < $1.date }
    }

    /// Values with `date` in the half-open interval [start, end).
    func values(in interval: DateInterval) -> [Double] {
        let lower = firstIndex(notBefore: interval.start)
        let upper = firstIndex(notBefore: interval.end)
        guard lower < upper else { return [] }
        return items[lower..<upper].map(\.value)
    }

    private func firstIndex(notBefore date: Date) -> Int {
        var low = 0
        var high = items.count
        while low < high {
            let mid = (low + high) / 2
            if items[mid].date < date { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
