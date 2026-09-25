import Foundation
import HealthInsights
import ReadinessCore

// MARK: - Providers

/// Serves the readiness engine from an imported export instead of HealthKit.
public struct ImportedDataSource: HealthDataSource {
    public let data: ImportedHealthData

    public init(data: ImportedHealthData) {
        self.data = data
    }

    public func requestAuthorization() async throws {}

    public func fetch(from start: Date, to end: Date) async throws -> RawHealthData {
        // The engine only reads the days it analyses; handing it everything is cheap and simpler
        // than slicing every series.
        data.raw
    }
}

/// Serves the Health, Workouts and Insights tabs from an imported export.
public struct ImportedMetricsProvider: HealthMetricsProvider {
    public let data: ImportedHealthData
    private let calendar: Calendar

    public init(data: ImportedHealthData, calendar: Calendar = .current) {
        self.data = data
        self.calendar = calendar
    }

    public func requestAuthorization() async throws {}

    public func profile() async -> HealthProfile { HealthProfile(age: data.raw.profile.age) }

    public func daily(_ metric: HealthMetric, in interval: DateInterval) async throws -> [DailyValue] {
        (data.daily[metric] ?? []).filter { interval.contains($0.date) }
    }

    public func activityRings(in interval: DateInterval) async throws -> [ActivityRingDay] {
        data.rings.filter { interval.contains($0.date) }
    }

    public func workouts(in interval: DateInterval) async throws -> [WorkoutSummary] {
        data.workouts.filter { interval.contains($0.start) }
    }

    public func heartRateSamples(in interval: DateInterval) async throws -> [TimedValue] {
        Self.slice(data.heartRateSamples, interval)
    }

    public func intraday(on day: Date) async throws -> IntradayDay {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let interval = DateInterval(start: start, end: end)

        // 5-minute min/mean/max buckets, like the HealthKit statistics query.
        let grouped = Dictionary(grouping: Self.slice(data.heartRateSamples, interval)) {
            Int(($0.date.timeIntervalSince(start) / 300).rounded(.down))
        }
        let heartRate = grouped.map { index, samples in
            let values = samples.map(\.value)
            return RangeBucket(
                start: start.addingTimeInterval(TimeInterval(index) * 300),
                min: values.min() ?? 0,
                average: values.reduce(0, +) / Double(values.count),
                max: values.max() ?? 0
            )
        }
        .sorted { $0.start < $1.start }

        // Sleep from the night before through today, one source only (as the engine does).
        let nightStart = calendar.date(byAdding: .hour, value: -8, to: start)!
        let candidates = data.raw.sleep.filter { $0.end > nightStart && $0.start < end }
        let source = SleepAnalyzer(calendar: calendar).preferredSourceID(in: candidates)
        let sleep = candidates.filter { $0.sourceID == source && $0.stage != .inBed && $0.end > start }

        return IntradayDay(
            day: start,
            heartRate: heartRate,
            hourlySteps: Self.slice(data.hourlySteps, interval),
            sleep: sleep,
            workouts: data.workouts.filter { $0.start < end && $0.end > start }
        )
    }

    /// Values in [start, end) from a date-sorted array, by binary search.
    static func slice(_ sorted: [TimedValue], _ interval: DateInterval) -> [TimedValue] {
        func firstIndex(notBefore date: Date) -> Int {
            var low = 0, high = sorted.count
            while low < high {
                let mid = (low + high) / 2
                if sorted[mid].date < date { low = mid + 1 } else { high = mid }
            }
            return low
        }
        let lower = firstIndex(notBefore: interval.start)
        let upper = firstIndex(notBefore: interval.end)
        return lower < upper ? Array(sorted[lower..<upper]) : []
    }
}

// MARK: - Persistence

/// Stores one imported export on device so it's parsed once, not at every launch.
///
/// Binary property list (compact, fast to decode), written atomically with iOS file protection.
/// Removing it deletes the only copy the app holds.
public enum ImportedDataFile {
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenReadiness", isDirectory: true)
            .appendingPathComponent("imported-health-export.plist")
    }

    public static func save(_ data: ImportedHealthData, to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let encoded = try encoder.encode(data)
        #if os(iOS) || os(watchOS)
        try encoded.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try encoded.write(to: url, options: .atomic)
        #endif
    }

    public static func load(from url: URL = defaultURL) throws -> ImportedHealthData {
        try PropertyListDecoder().decode(ImportedHealthData.self, from: Data(contentsOf: url))
    }

    public static func exists(at url: URL = defaultURL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public static func remove(at url: URL = defaultURL) throws {
        guard exists(at: url) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
