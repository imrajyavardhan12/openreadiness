import Foundation
import Observation
import OSLog
import ReadinessCore
import ReadinessHealthKit

/// App state: fetches raw data, runs the engine off the main thread, and publishes the analysis.
///
/// Raw data is kept in memory so settings changes (e.g. sleep goal) recompute instantly without
/// touching HealthKit again. Nothing is persisted or sent anywhere — HealthKit stays the single
/// source of truth.
@MainActor
@Observable
final class ReadinessStore {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var analysis: ReadinessAnalysis = .empty
    private(set) var lastUpdated: Date?

    var usesDemoData: Bool {
        didSet {
            guard usesDemoData != oldValue else { return }
            defaults.set(usesDemoData, forKey: Keys.demo)
            raw = nil
            Task { await refresh() }
        }
    }

    var sleepGoalHours: Double {
        didSet {
            guard sleepGoalHours != oldValue else { return }
            defaults.set(sleepGoalHours, forKey: Keys.sleepGoal)
            Task { await recompute() }
        }
    }

    /// Days of history to score. Baselines need extra lookback on top of this.
    let historyDays: Int

    private var raw: RawHealthData?
    private var observation: Task<Void, Never>?
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "org.openreadiness", category: "Store")

    private enum Keys {
        static let demo = "usesDemoData"
        static let sleepGoal = "sleepGoalHours"
    }

    init(historyDays: Int = 90, defaults: UserDefaults = .standard, forceDemo: Bool = false) {
        self.historyDays = historyDays
        self.defaults = defaults
        // HealthKit is unavailable on iPad without Health and has no data in the Simulator by default.
        self.usesDemoData = forceDemo || defaults.bool(forKey: Keys.demo) || !HealthKitDataSource.isAvailable
        let storedGoal = defaults.double(forKey: Keys.sleepGoal)
        self.sleepGoalHours = storedGoal > 0 ? storedGoal : 8
    }

    var configuration: ReadinessConfiguration {
        var configuration = ReadinessConfiguration.default
        configuration.sleepGoalHours = sleepGoalHours
        return configuration
    }

    private var source: any HealthDataSource {
        usesDemoData ? DemoDataSource() : HealthKitDataSource()
    }

    func requestAuthorization() async {
        do {
            try await source.requestAuthorization()
        } catch {
            logger.error("Authorization failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// Fetches fresh data and recomputes. Safe to call repeatedly (pull to refresh, foregrounding).
    func refresh() async {
        if phase != .loaded { phase = .loading }
        let now = Date.now
        let lookback = configuration.lookbackDays(historyDays: historyDays)
        let start = Calendar.current.date(byAdding: .day, value: -lookback, to: Calendar.current.startOfDay(for: now))!
        do {
            raw = try await source.fetch(from: start, to: now)
            await recompute()
        } catch {
            logger.error("Fetch failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// Re-runs the engine on already-fetched data.
    func recompute() async {
        guard let raw else { return await refresh() }
        let engine = ReadinessEngine(configuration: configuration, calendar: .current)
        let historyDays = historyDays
        let result = await Task.detached(priority: .userInitiated) {
            engine.analyze(raw, now: .now, historyDays: historyDays)
        }.value
        analysis = result
        lastUpdated = .now
        phase = .loaded
        #if os(iOS)
        let snapshot = ReadinessSnapshot(analysis: result, isSampleData: usesDemoData)
        SnapshotPublisher.publish(snapshot)
        WatchSync.shared.send(snapshot)
        #endif
    }

    /// Refreshes automatically when HealthKit receives new sleep, HRV, heart-rate or workout data.
    func observeHealthKitChanges() {
        guard observation == nil, HealthKitDataSource.isAvailable else { return }
        let changes = HealthKitDataSource().changes()
        observation = Task { [weak self] in
            for await _ in changes {
                // Observer queries fire in bursts after a sync; coalesce them.
                try? await Task.sleep(for: .seconds(2))
                guard let self, !self.usesDemoData else { continue }
                await self.refresh()
            }
        }
    }
}
