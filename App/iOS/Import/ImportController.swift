import AppleHealthImport
import Foundation
import Observation
import OSLog
import ReadinessCore

/// Owns the imported Health export: parsing a new one, restoring it at launch, and removing it.
///
/// Parsing and decoding run off the main actor. The parsed result is kept in one protected file in
/// the app's container, so a multi-hundred-MB export is only ever parsed once.
@MainActor
@Observable
final class ImportController {
    enum State: Equatable {
        case idle
        case working(String)
        case failed(String)
    }

    struct Summary: Equatable {
        var coverage: DateInterval?
        var exportDate: Date?
        var nightsOfSleep: Int
        var hrvReadings: Int
        var workouts: Int
    }

    private(set) var state: State = .idle
    private(set) var summary: Summary?

    private let store: ReadinessStore
    private let explorer: ExplorerStore
    private let logger = Logger(subsystem: "org.openreadiness", category: "Import")

    init(store: ReadinessStore, explorer: ExplorerStore) {
        self.store = store
        self.explorer = explorer
    }

    var hasImport: Bool { summary != nil }

    /// Loads a previously imported export if the app is in imported mode (or one exists).
    func restoreIfNeeded() async {
        guard ImportedDataFile.exists() else {
            if store.dataMode == .imported { fallBackToDefaultMode() }
            return
        }
        guard summary == nil else { return }
        state = .working(String(localized: "Loading your imported data…"))
        do {
            let data = try await Task.detached(priority: .userInitiated) { try ImportedDataFile.load() }.value
            apply(data)
            state = .idle
            if store.dataMode == .imported { await refreshAll() }
        } catch {
            logger.error("Restoring import failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(String(localized: "The saved import couldn't be read. Import your export again."))
            if store.dataMode == .imported { fallBackToDefaultMode() }
        }
    }

    /// Parses an `export.xml`, saves the result, and switches the app to it.
    func importExport(from url: URL) async {
        state = .working(String(localized: "Reading your Health export… this can take a minute."))
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                let parsed = try AppleHealthExport.parse(contentsOf: url)
                try ImportedDataFile.save(parsed)
                return parsed
            }.value
            apply(data)
            state = .idle
            if store.dataMode == .imported {
                await refreshAll()
            } else {
                // Setting the mode triggers both stores to reload from the new source.
                store.dataMode = .imported
                explorer.dataMode = .imported
            }
        } catch {
            logger.error("Import failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    /// Deletes the imported data (the only copy the app holds) and returns to live or sample data.
    func remove() {
        do {
            try ImportedDataFile.remove()
        } catch {
            logger.error("Removing import failed: \(error.localizedDescription, privacy: .public)")
        }
        summary = nil
        store.importedSource = nil
        explorer.importedProvider = nil
        if store.dataMode == .imported { fallBackToDefaultMode() }
    }

    private func apply(_ data: ImportedHealthData) {
        let end = data.coverage?.end
        store.importedSource = ImportedDataSource(data: data)
        store.referenceDate = end
        explorer.importedProvider = ImportedMetricsProvider(data: data)
        explorer.referenceDate = end
        let calendar = Calendar.current
        summary = Summary(
            coverage: data.coverage,
            exportDate: data.exportDate,
            nightsOfSleep: Set(data.raw.sleep.filter(\.stage.isAsleep).map { calendar.startOfDay(for: $0.end) }).count,
            hrvReadings: data.raw.hrv.count,
            workouts: data.workouts.count
        )
    }

    private func refreshAll() async {
        await store.refresh()
        await explorer.reload()
    }

    private func fallBackToDefaultMode() {
        store.dataMode = .health
        explorer.dataMode = store.dataMode
    }
}
