import HealthKit
import OSLog
import ReadinessCore
import ReadinessHealthKit
import UIKit

/// Keeps widgets, complications and the watch current while the app isn't open.
///
/// HealthKit background delivery wakes the app when the watch syncs new sleep, HRV, resting heart
/// rate or workouts. The score is recomputed headlessly and published as a `ReadinessSnapshot`.
/// When the app is in the foreground, `ReadinessStore` already handles refreshes, so this stays out
/// of the way.
final class BackgroundRefresher: @unchecked Sendable {
    // Mutable state is guarded by `lock`; HKHealthStore is thread-safe.
    static let shared = BackgroundRefresher()

    private let healthStore = HKHealthStore()
    private let lock = NSLock()
    private var started = false
    private var isComputing = false
    private let logger = Logger(subsystem: "org.openreadiness", category: "Background")

    private static let triggerTypes: [HKSampleType] = [
        HKCategoryType(.sleepAnalysis),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.restingHeartRate),
        HKObjectType.workoutType(),
    ]

    /// Registers observer queries and background delivery. Must run at every launch (including
    /// background launches), because iOS delivers updates only to queries registered by then.
    func start() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let alreadyStarted = lock.withLock {
            defer { started = true }
            return started
        }
        guard !alreadyStarted else { return }

        for type in Self.triggerTypes {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                // HealthKit waits for `completion` before delivering more; always call it.
                nonisolated(unsafe) let done = completion
                guard error == nil, let self else { return done() }
                Task {
                    await self.refreshIfBackgrounded()
                    done()
                }
            }
            healthStore.execute(query)
            healthStore.enableBackgroundDelivery(for: type, frequency: .hourly) { [logger] success, error in
                if !success {
                    logger.error("Background delivery for \(type.identifier, privacy: .public) failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
                }
            }
        }
    }

    private func refreshIfBackgrounded() async {
        let isActive = await MainActor.run { UIApplication.shared.applicationState == .active }
        let mode = UserDefaults.standard.string(forKey: ReadinessStore.Keys.dataMode) ?? DataMode.health.rawValue
        guard !isActive, mode == DataMode.health.rawValue else { return }
        await recompute()
    }

    func recompute() async {
        let shouldRun = lock.withLock {
            guard !isComputing else { return false }
            isComputing = true
            return true
        }
        guard shouldRun else { return }
        defer { lock.withLock { isComputing = false } }

        var configuration = ReadinessConfiguration.default
        let goal = UserDefaults.standard.double(forKey: "sleepGoalHours")
        if goal > 0 { configuration.sleepGoalHours = goal }

        let now = Date.now
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -configuration.lookbackDays(historyDays: 7), to: calendar.startOfDay(for: now))!
        do {
            let raw = try await HealthKitDataSource().fetch(from: start, to: now)
            let analysis = ReadinessEngine(configuration: configuration, calendar: calendar).analyze(raw, now: now, historyDays: 7)
            let snapshot = ReadinessSnapshot(analysis: analysis)
            await MainActor.run {
                SnapshotPublisher.publish(snapshot)
                WatchSync.shared.send(snapshot)
            }
            logger.info("Background refresh published score \(snapshot.today?.score ?? -1)")
        } catch let error as HKError where error.code == .errorDatabaseInaccessible {
            // Health data is encrypted while the device is locked; the next delivery after unlock catches up.
            logger.info("Health data locked; will refresh after unlock")
        } catch {
            logger.error("Background refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            BackgroundRefresher.shared.start()
        }
        return true
    }
}
