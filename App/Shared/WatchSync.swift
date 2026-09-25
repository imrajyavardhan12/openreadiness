import Foundation
import OSLog
import WatchConnectivity

/// Minimal WatchConnectivity bridge: the phone pushes the latest `WatchPayload` as application
/// context (only the newest value is kept, which is exactly the semantics we want); the watch
/// receives it. Nothing ever leaves the user's own devices.
@MainActor
final class WatchSync: NSObject {
    static let shared = WatchSync()

    /// Called on the main actor whenever a payload arrives (watch side).
    var onReceive: ((WatchPayload) -> Void)?

    private let logger = Logger(subsystem: "org.openreadiness", category: "WatchSync")

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// The last payload received, so the watch can show something before the phone next syncs.
    var receivedPayload: WatchPayload? {
        guard WCSession.isSupported(),
              let data = WCSession.default.receivedApplicationContext[WatchPayload.contextKey] as? Data
        else { return nil }
        return try? WatchPayload.decode(data)
    }

    func send(_ payload: WatchPayload) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        #if os(iOS)
        guard WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        #endif
        do {
            try WCSession.default.updateApplicationContext([WatchPayload.contextKey: payload.encoded()])
        } catch {
            logger.error("Failed to send payload to watch: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension WatchSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if let error {
            Logger(subsystem: "org.openreadiness", category: "WatchSync")
                .error("Activation failed: \(error.localizedDescription, privacy: .public)")
        }
        // Deliver whatever the phone sent while this app wasn't running.
        deliver(session.receivedApplicationContext)
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        deliver(context)
    }

    private nonisolated func deliver(_ context: [String: Any]) {
        guard let data = context[WatchPayload.contextKey] as? Data,
              let payload = try? WatchPayload.decode(data)
        else { return }
        Task { @MainActor in self.onReceive?(payload) }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate so a newly paired watch starts receiving updates.
        session.activate()
    }
    #endif
}
