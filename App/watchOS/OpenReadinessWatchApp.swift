import Observation
import ReadinessCore
import SwiftUI

@main
struct OpenReadinessWatchApp: App {
    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(model)
                .task { await model.start() }
        }
    }
}

/// Prefers today's snapshot from the iPhone (months of baseline history). If the phone hasn't
/// synced today, scores locally from the watch's own, shorter HealthKit history.
@MainActor
@Observable
final class WatchModel {
    private(set) var payload: ReadinessSnapshot?
    private(set) var isComputingLocally = false
    private(set) var isLocal = false

    /// `-demo` shows sample data (Simulator, screenshots, UI tests) without HealthKit or a phone.
    let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")
    private let store: ReadinessStore

    init() {
        // 14 scored days so the trend pages have two weeks of context.
        store = ReadinessStore(historyDays: 14, forceDemo: isDemo)
    }

    func start() async {
        if isDemo {
            isComputingLocally = true
            await store.refresh()
            isComputingLocally = false
            payload = ReadinessSnapshot(analysis: store.analysis, isSampleData: true)
            return
        }

        WatchSync.shared.onReceive = { [weak self] payload in
            self?.payload = payload
            self?.isLocal = false
            SnapshotPublisher.publish(payload)
        }
        WatchSync.shared.activate()
        if payload == nil { payload = WatchSync.shared.receivedPayload ?? SnapshotStore.load() }

        guard !isFromToday(payload) else { return }
        isComputingLocally = true
        await store.requestAuthorization()
        await store.refresh()
        isComputingLocally = false
        // A phone payload may have arrived meanwhile; don't overwrite it.
        if !isFromToday(payload), store.analysis.today != nil {
            let snapshot = ReadinessSnapshot(analysis: store.analysis)
            payload = snapshot
            isLocal = true
            SnapshotPublisher.publish(snapshot)
        }
    }

    private func isFromToday(_ payload: ReadinessSnapshot?) -> Bool {
        guard let day = payload?.today?.day else { return false }
        return Calendar.current.isDateInToday(day)
    }
}
