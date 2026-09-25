import Foundation
import HealthInsights
import Observation
import OSLog
import ReadinessCore
import ReadinessHealthKit

/// State for the Health, Workouts and Insights tabs.
///
/// Each metric is fetched once for the full history window and then sliced in memory for W/M/6M/Y,
/// so switching ranges is instant. All metrics load concurrently; a failure in one (for example a
/// type the user declined) never blocks the others. Nothing is written to disk.
@MainActor
@Observable
final class ExplorerStore {
    private(set) var series: [HealthMetric: [DailyValue]] = [:]
    private(set) var rings: [ActivityRingDay] = []
    private(set) var workouts: [WorkoutSummary] = []
    private(set) var profile = HealthProfile()
    private(set) var isLoading = false
    private(set) var hasLoaded = false

    var usesDemoData: Bool {
        didSet {
            guard usesDemoData != oldValue else { return }
            providerCache = nil
            Task { await reload() }
        }
    }

    static let historyDays = 430

    private var providerCache: (any HealthMetricsProvider)?
    private let logger = Logger(subsystem: "org.openreadiness", category: "Explorer")

    init(usesDemoData: Bool) {
        self.usesDemoData = usesDemoData
    }

    /// Created off the main actor: the demo provider generates ~14 months of data up front.
    private func resolveProvider() async -> any HealthMetricsProvider {
        if let providerCache { return providerCache }
        let demo = usesDemoData
        let created = await Task.detached(priority: .userInitiated) { () -> any HealthMetricsProvider in
            demo ? DemoMetricsProvider() : HealthKitMetricsProvider()
        }.value
        providerCache = created
        return created
    }

    var window: DateInterval {
        let end = Date.now
        let start = Calendar.current.date(byAdding: .day, value: -Self.historyDays, to: Calendar.current.startOfDay(for: end))!
        return DateInterval(start: start, end: end)
    }

    /// Metrics that actually have data, in catalogue order.
    var availableMetrics: [HealthMetric] {
        HealthMetric.allCases.filter { !(series[$0]?.isEmpty ?? true) }
    }

    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        let provider = await resolveProvider()
        let window = window
        let logger = logger

        // Demo generation and HealthKit queries both run off the main actor.
        let loaded = await withTaskGroup(of: (HealthMetric, [DailyValue]).self) { group in
            for metric in HealthMetric.allCases {
                group.addTask {
                    do {
                        return (metric, try await provider.daily(metric, in: window))
                    } catch {
                        logger.error("\(metric.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                        return (metric, [])
                    }
                }
            }
            var result: [HealthMetric: [DailyValue]] = [:]
            for await (metric, values) in group { result[metric] = values }
            return result
        }
        async let ringsResult = try? provider.activityRings(in: window)
        async let workoutsResult = try? provider.workouts(in: window)
        async let profileResult = provider.profile()

        series = loaded
        rings = await ringsResult ?? []
        workouts = (await workoutsResult ?? []).sorted { $0.start > $1.start }
        profile = await profileResult
        hasLoaded = true
    }

    func intraday(on day: Date) async throws -> IntradayDay {
        try await resolveProvider().intraday(on: day)
    }

    func heartRate(for workout: WorkoutSummary) async throws -> [TimedValue] {
        try await resolveProvider().heartRateSamples(in: DateInterval(start: workout.start, end: max(workout.end, workout.start)))
    }

    /// Heart-rate zones from your resting heart rate and age-predicted maximum.
    var heartRateZones: HeartRateZones {
        let resting = Stats.median((series[.restingHeartRate] ?? []).suffix(60).map(\.value)) ?? 60
        return HeartRateZones(resting: resting, maximum: WorkoutLoadModel.predictedMaxHeartRate(age: profile.age))
    }

    func values(_ metric: HealthMetric, lastDays days: Int) -> [DailyValue] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: .now))!
        return (series[metric] ?? []).filter { $0.date >= cutoff }
    }
}
