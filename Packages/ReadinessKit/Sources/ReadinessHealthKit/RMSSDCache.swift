import Foundation
import OSLog

/// Remembers the RMSSD computed for each heartbeat series, keyed by the sample's UUID.
///
/// A recorded series never changes, so each one is read beat-by-beat only once. That keeps
/// refreshes fast, which matters most for background refreshes with their tight time budget.
/// The cache holds derived numbers only (no raw beats), lives in the app's private container, and
/// is written with iOS file protection so it's encrypted until the device is first unlocked.
actor RMSSDCache {
    static let shared = RMSSDCache()

    struct Entry: Codable, Sendable {
        var date: Date
        /// nil when the series had too few clean beats (so it isn't re-read every time).
        var rmssd: Double?
    }

    private var entries: [UUID: Entry]?
    private var isDirty = false
    private let logger = Logger(subsystem: "org.openreadiness", category: "RMSSDCache")
    /// Entries older than this are dropped; they're beyond any baseline window.
    private let retention: TimeInterval = 200 * 86_400

    private var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("OpenReadiness", isDirectory: true)
            .appendingPathComponent("rmssd-cache.json")
    }

    func entry(for id: UUID) -> Entry? {
        loadIfNeeded()
        return entries?[id]
    }

    func store(_ entry: Entry, for id: UUID) {
        loadIfNeeded()
        entries?[id] = entry
        isDirty = true
    }

    func persist() {
        guard isDirty, var entries, let fileURL else { return }
        let cutoff = Date.now.addingTimeInterval(-retention)
        entries = entries.filter { $0.value.date >= cutoff }
        self.entries = entries
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            #if os(iOS) || os(watchOS)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: fileURL, options: .atomic)
            #endif
            isDirty = false
        } catch {
            logger.error("Could not save RMSSD cache: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadIfNeeded() {
        guard entries == nil else { return }
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([UUID: Entry].self, from: data)
        else {
            entries = [:]
            return
        }
        entries = decoded
    }
}
