import Foundation
import Observation
import OSLog
import ReadinessCore
import ReadinessHealthKit

/// Where the app's data comes from.
enum DataMode: String, CaseIterable, Identifiable, Sendable {
    /// Live HealthKit data (the normal mode).
    case health
    /// Built-in synthetic data for exploring the app.
    case sample
    /// A Health app export the user imported (iPhone only).
    case imported

    var id: String { rawValue }
}

/// App state: fetches raw data, runs the engine off the main thread, and publishes the analysis.
///
/// Raw data is kept in memory so settings changes (e.g. sleep goal) recompute instantly without
/// touching HealthKit again. Nothing is sent anywhere — HealthKit (or the user's own imported
/// export) stays the single source of truth.
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

    var dataMode: DataMode {
        didSet {
            guard dataMode != oldValue else { return }
            defaults.set(dataMode.rawValue, forKey: Keys.dataMode)
            raw = nil
            Task { await refresh() }
        }
    }

    /// Convenience for the "sample data" switch and banners.
    var usesDemoData: Bool {
        get { dataMode == .sample }
        set { dataMode = newValue ? .sample : .health }
    }

    /// Supplied by the iPhone app's import controller when an export is loaded.
    var importedSource: (any HealthDataSource)?
    /// For imported data, the moment the export ends; scoring treats it as "now".
    var referenceDate: Date?

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

    enum Keys {
        static let dataMode = "dataMode"
        static let legacyDemo = "usesDemoData"
        static let sleepGoal = "sleepGoalHours"
    }

    init(historyDays: Int = 90, defaults: UserDefaults = .standard, forceDemo: Bool = false) {
        self.historyDays = historyDays
        self.defaults = defaults
        // Migrate the old boolean setting. HealthKit is unavailable on iPad without Health.
        let stored = defaults.string(forKey: Keys.dataMode).flatMap(DataMode.init)
            ?? (defaults.bool(forKey: Keys.legacyDemo) ? .sample : .health)
        // One-time migration: persist the mode and drop the legacy key so nothing reads it again.
        if defaults.object(forKey: Keys.legacyDemo) != nil {
            defaults.set(stored.rawValue, forKey: Keys.dataMode)
            defaults.removeObject(forKey: Keys.legacyDemo)
        }
        if forceDemo {
            self.dataMode = .sample
        } else if stored == .health, !HealthKitDataSource.isAvailable {
            self.dataMode = .sample
        } else {
            self.dataMode = stored
        }
        let storedGoal = defaults.double(forKey: Keys.sleepGoal)
        self.sleepGoalHours = storedGoal > 0 ? storedGoal : 8
    }

    var configuration: ReadinessConfiguration {
        var configuration = ReadinessConfiguration.default
        configuration.sleepGoalHours = sleepGoalHours
        return configuration
    }

    private var source: (any HealthDataSource)? {
        switch dataMode {
        case .health: HealthKitDataSource()
        case .sample: DemoDataSource()
        case .imported: importedSource
        }
    }

    /// "Now" for scoring: the end of an imported export, otherwise the real now.
    private var now: Date {
        guard dataMode == .imported, let referenceDate else { return .now }
        return min(referenceDate, .now)
    }

    func requestAuthorization() async {
        guard let source else { return }
        do {
            try await source.requestAuthorization()
        } catch {
            logger.error("Authorization failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// Fetches fresh data and recomputes. Safe to call repeatedly (pull to refresh, foregrounding).
    func refresh() async {
        // Imported data arrives asynchronously; the import controller refreshes once it's loaded.
        guard let source else { return }
        if phase != .loaded { phase = .loading }
        let now = now
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
        let now = now
        let result = await Task.detached(priority: .userInitiated) {
            engine.analyze(raw, now: now, historyDays: historyDays)
        }.value
        analysis = result
        lastUpdated = .now
        phase = .loaded
        #if os(iOS)
        // An imported export is for exploring history; widgets and the watch keep showing live data.
        if dataMode != .imported {
            let snapshot = ReadinessSnapshot(analysis: result, isSampleData: dataMode == .sample)
            SnapshotPublisher.publish(snapshot)
            WatchSync.shared.send(snapshot)
        }
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
                guard let self, self.dataMode == .health else { continue }
                await self.refresh()
            }
        }
    }
}
