import Foundation

/// Minimal RFC 4180 CSV writer. Numbers are always formatted with a period decimal separator and no
/// grouping, regardless of the device locale, so files open correctly in any spreadsheet or script.
public struct CSVWriter: Sendable {
    public private(set) var text = ""

    public init(header: [String]) {
        append(header)
    }

    public mutating func append(_ fields: [String]) {
        text += fields.map(Self.escape).joined(separator: ",") + "\r\n"
    }

    public static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Empty for nil; otherwise fixed decimals with a period separator.
    public static func number(_ value: Double?, digits: Int = 2) -> String {
        guard let value, value.isFinite else { return "" }
        return String(format: "%.\(digits)f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    /// ISO 8601 calendar date (yyyy-MM-dd) in the given calendar's time zone.
    public static func date(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

public enum ReadinessExport {
    public static let fileName = "openreadiness-readiness.csv"

    /// One row per day: the score, each contributor's sub-score and weight, and every daily input.
    public static func csv(_ analysis: ReadinessAnalysis, calendar: Calendar = .current) -> String {
        let kinds = ContributorKind.allCases
        var header = ["date", "score", "band", "raw_score", "confidence", "calibrating", "limiting_factor"]
        header += kinds.flatMap { ["\($0.rawValue)_subscore", "\($0.rawValue)_weight"] }
        header += [
            "hrv_rmssd_overnight_ms", "hrv_sdnn_overnight_ms", "hrv_sdnn_24h_ms",
            "sleeping_hr_bpm", "apple_resting_hr_bpm",
            "sleep_start", "sleep_end", "asleep_h", "deep_h", "core_h", "rem_h", "awake_h", "interruptions",
            "respiratory_rate_brpm", "wrist_temperature_c", "spo2_pct",
            "training_load", "workouts", "active_energy_kcal",
        ]
        var writer = CSVWriter(header: header)
        let time = DateFormatter()
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        time.locale = Locale(identifier: "en_US_POSIX")
        time.dateFormat = "yyyy-MM-dd'T'HH:mm"

        for day in analysis.days {
            let score = analysis.scores[day.day]
            var row = [
                CSVWriter.date(day.day, calendar: calendar),
                score.map { String($0.score) } ?? "",
                score?.category.title ?? "",
                CSVWriter.number(score?.rawScore, digits: 1),
                CSVWriter.number(score?.confidence),
                score.map { $0.isCalibrating ? "true" : "false" } ?? "",
                score?.limitingFactor?.rawValue ?? "",
            ]
            for kind in kinds {
                let contributor = score?.contributor(kind)
                row += [CSVWriter.number(contributor?.subscore, digits: 1), CSVWriter.number(contributor?.effectiveWeight, digits: 3)]
            }
            let sleep = day.sleep
            row += [
                CSVWriter.number(day.rmssdOvernight, digits: 1),
                CSVWriter.number(day.hrvOvernight, digits: 1),
                CSVWriter.number(day.hrvAllDay, digits: 1),
                CSVWriter.number(day.sleepingHeartRate, digits: 1),
                CSVWriter.number(day.appleRestingHeartRate, digits: 1),
                sleep.map { time.string(from: $0.start) } ?? "",
                sleep.map { time.string(from: $0.end) } ?? "",
                CSVWriter.number(sleep.map { $0.asleep / 3600 }),
                CSVWriter.number(sleep.map { $0.deep / 3600 }),
                CSVWriter.number(sleep.map { $0.core / 3600 }),
                CSVWriter.number(sleep.map { $0.rem / 3600 }),
                CSVWriter.number(sleep.map { $0.awake / 3600 }),
                sleep.map { String($0.interruptions) } ?? "",
                CSVWriter.number(day.respiratoryRate),
                CSVWriter.number(day.wristTemperature),
                CSVWriter.number(day.oxygenSaturation, digits: 1),
                CSVWriter.number(day.trainingLoad, digits: 0),
                String(day.workouts.count),
                CSVWriter.number(day.activeEnergy, digits: 0),
            ]
            writer.append(row)
        }
        return writer.text
    }
}
