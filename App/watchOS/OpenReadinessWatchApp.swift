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

/// Prefers today's score from the iPhone (months of baseline history). If the phone hasn't
/// synced today, scores locally from the watch's own, shorter HealthKit history.
@MainActor
@Observable
final class WatchModel {
    private(set) var payload: WatchPayload?
    private(set) var isComputingLocally = false
    private(set) var isLocal = false

    private let store = ReadinessStore(historyDays: 7)

    func start() async {
        WatchSync.shared.onReceive = { [weak self] payload in
            self?.payload = payload
            self?.isLocal = false
        }
        WatchSync.shared.activate()
        if payload == nil { payload = WatchSync.shared.receivedPayload }

        guard !isFromToday(payload) else { return }
        isComputingLocally = true
        await store.requestAuthorization()
        await store.refresh()
        isComputingLocally = false
        // A phone payload may have arrived meanwhile; don't overwrite it.
        if !isFromToday(payload), store.analysis.today != nil {
            payload = WatchPayload(analysis: store.analysis)
            isLocal = true
        }
    }

    private func isFromToday(_ payload: WatchPayload?) -> Bool {
        guard let day = payload?.today?.day else { return false }
        return Calendar.current.isDateInToday(day)
    }
}
