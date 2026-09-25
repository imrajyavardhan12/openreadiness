import CoreTransferable
import HealthInsights
import ReadinessCore
import UniformTypeIdentifiers

/// A CSV file produced on demand when the user shares it — never written ahead of time.
struct CSVExport: Transferable, Sendable {
    enum Content: Sendable {
        case readiness(ReadinessAnalysis)
        case metrics([HealthMetric: [DailyValue]])
    }

    let content: Content

    var fileName: String {
        let stamp = CSVWriter.date(.now, calendar: .current)
        return switch content {
        case .readiness: "openreadiness-readiness-\(stamp).csv"
        case .metrics: "openreadiness-health-metrics-\(stamp).csv"
        }
    }

    func text() -> String {
        switch content {
        case .readiness(let analysis): ReadinessExport.csv(analysis)
        case .metrics(let series): MetricsExport.csv(series)
        }
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            // Temporary directory: the system cleans it up; the file exists only for the share.
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(export.fileName)
            try Data(export.text().utf8).write(to: url, options: [.atomic, .completeFileProtection])
            return SentTransferredFile(url)
        }
    }
}
