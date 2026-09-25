import Foundation
import ReadinessCore

public enum MetricsExport {
    public static let fileName = "openreadiness-health-metrics.csv"

    /// A wide table: one row per day, one column per metric (plus min/max for range metrics).
    public static func csv(_ series: [HealthMetric: [DailyValue]], calendar: Calendar = .current) -> String {
        let metrics = HealthMetric.allCases.filter { !(series[$0]?.isEmpty ?? true) }
        var header = ["date"]
        for metric in metrics {
            let column = "\(metric.rawValue)_\(unitSlug(metric))"
            header.append(column)
            if metric.aggregation == .range { header += ["\(column)_min", "\(column)_max"] }
        }
        var writer = CSVWriter(header: header)

        let byMetric = series.mapValues { values in
            Dictionary(values.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
        }
        let days = Set(byMetric.values.flatMap(\.keys)).sorted()
        for day in days {
            var row = [CSVWriter.date(day, calendar: calendar)]
            for metric in metrics {
                let value = byMetric[metric]?[day]
                row.append(CSVWriter.number(value?.value))
                if metric.aggregation == .range {
                    row += [CSVWriter.number(value?.min), CSVWriter.number(value?.max)]
                }
            }
            writer.append(row)
        }
        return writer.text
    }

    static func unitSlug(_ metric: HealthMetric) -> String {
        switch metric.unit {
        case "%": "pct"
        case "°C": "c"
        case "br/min": "brpm"
        case "km/h": "kmh"
        case "VO₂ max": "ml_kg_min"
        default: metric.unit.replacingOccurrences(of: " ", with: "_")
        }
    }
}
