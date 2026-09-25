import AppleHealthImport
import Foundation
import HealthInsights
import ReadinessCore

// openreadiness-cli — run the readiness engine on a Health app export.
//
//   swift run -c release openreadiness-cli path/to/export.xml [--as-of 2026-07-14] [--days 365]
//                                          [--sleep-goal 8] [--csv scores.csv]
//
// Everything runs locally; nothing is uploaded. Useful for validating the model on real data
// without a paid developer account or a device build.

struct Options {
    var exportPath: String?
    var asOf: Date = .now
    var days = 365
    var sleepGoal: Double?
    var csvPath: String?
    var explain: Date?
}

func parseOptions() -> Options {
    var options = Options()
    var arguments = CommandLine.arguments.dropFirst().makeIterator()
    while let argument = arguments.next() {
        switch argument {
        case "--as-of":
            guard let value = arguments.next(), let date = ExportDay.parse(value) else { fail("--as-of expects YYYY-MM-DD") }
            // Evaluate at noon on that day, so the morning's score is complete.
            options.asOf = Calendar.current.date(byAdding: .hour, value: 12, to: date)!
        case "--days":
            guard let value = arguments.next().flatMap(Int.init), value > 0 else { fail("--days expects a positive number") }
            options.days = value
        case "--sleep-goal":
            guard let value = arguments.next().flatMap(Double.init) else { fail("--sleep-goal expects hours") }
            options.sleepGoal = value
        case "--csv":
            options.csvPath = arguments.next()
        case "--explain":
            guard let value = arguments.next(), let date = ExportDay.parse(value) else { fail("--explain expects YYYY-MM-DD") }
            options.explain = date
        case "-h", "--help":
            print("usage: openreadiness-cli <export.xml> [--as-of YYYY-MM-DD] [--days N] [--sleep-goal H] [--csv out.csv] [--explain YYYY-MM-DD]")
            exit(0)
        default:
            options.exportPath = argument
        }
    }
    return options
}

enum ExportDay {
    static func parse(_ string: String) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func percent(_ part: Int, _ whole: Int) -> String {
    whole == 0 ? "–" : "\(Int((Double(part) / Double(whole) * 100).rounded()))%"
}

func pad(_ string: String, _ width: Int) -> String {
    string.count >= width ? string : string + String(repeating: " ", count: width - string.count)
}

// MARK: - Run

let options = parseOptions()
guard let path = options.exportPath else { fail("pass the path to export.xml (see --help)") }
let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)

let clock = ContinuousClock()
let parseStart = clock.now
let imported: ImportedHealthData
do {
    imported = try AppleHealthExport.parse(contentsOf: url)
} catch {
    fail(error.localizedDescription)
}
let parseTime = clock.now - parseStart
let raw = imported.raw
let calendar = Calendar.current

print("OpenReadiness — Health export report")
print(String(repeating: "═", count: 60))
if let coverage = imported.coverage {
    print("Data from \(coverage.start.formatted(date: .abbreviated, time: .omitted)) to \(coverage.end.formatted(date: .abbreviated, time: .omitted)) · parsed in \(parseTime.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1))))")
}

let sleepNights = Set(raw.sleep.filter(\.stage.isAsleep).map { calendar.startOfDay(for: $0.end) }).count
let effortWorkouts = raw.workouts.filter { $0.effortScore != nil }.count
print("""

INPUTS
  Sleep                 \(sleepNights) nights with sleep samples\(raw.sleep.last.map { " (last: \($0.end.formatted(date: .abbreviated, time: .omitted)))" } ?? "")
  HRV (SDNN)            \(raw.hrv.count) readings
  HRV (RMSSD)           \(raw.rmssd.count) computed from beat-to-beat data (\(percent(raw.rmssd.count, raw.hrv.count)) of readings)
  Heart rate            \(raw.heartRateBuckets.count) half-hour buckets
  Resting HR            \(raw.restingHeartRate.count) days
  Respiratory rate      \(raw.respiratoryRate.count) · wrist temp \(raw.wristTemperature.count) · SpO₂ \(raw.oxygenSaturation.count)
  Workouts              \(raw.workouts.count) (\(effortWorkouts) with an Apple effort score)
  Age                   \(raw.profile.age.map(String.init) ?? "unknown")
""")

var configuration = ReadinessConfiguration.default
if let goal = options.sleepGoal { configuration.sleepGoalHours = goal }
let engine = ReadinessEngine(configuration: configuration, calendar: calendar)
let analysis = engine.analyze(raw, now: options.asOf, historyDays: options.days)
let scores = analysis.orderedScores

print("SCORES (\(options.days) days to \(options.asOf.formatted(date: .abbreviated, time: .omitted)))")
guard !scores.isEmpty else {
    print("  No days could be scored. Readiness needs sleep or overnight HRV/heart-rate data.")
    exit(0)
}
print("  Scored               \(scores.count) of \(analysis.days.count) days (\(percent(scores.count, analysis.days.count)))")
print("  Calibrating          \(scores.filter(\.isCalibrating).count) days")
let median = Stats.median(scores.map { Double($0.score) }) ?? 0
print("  Median score         \(Format.number(median, digits: 1))   (design target for an ordinary day: 7)")
print("")
for category in ReadinessCategory.allCases.reversed() {
    let count = scores.filter { $0.category == category }.count
    let bar = String(repeating: "█", count: Int((Double(count) / Double(scores.count) * 40).rounded()))
    print("  \(pad(category.title, 14)) \(pad(String(count), 4)) \(pad(percent(count, scores.count), 5)) \(bar)")
}

print("\nCONTRIBUTORS (share of scored days · median sub-score)")
for kind in ContributorKind.allCases {
    let present = scores.compactMap { $0.contributor(kind) }
    let medianSub = Stats.median(present.map(\.subscore)).map { Format.number($0) } ?? "–"
    print("  \(pad(kind.title, 24)) \(pad(percent(present.count, scores.count), 5)) median \(medianSub)")
}
let hrvSources = Dictionary(grouping: scores.compactMap { $0.contributor(.hrv)?.components.first?.label }, by: { $0 }).mapValues(\.count)
for (label, count) in hrvSources.sorted(by: { $0.value > $1.value }) {
    print("    HRV via \(label.replacingOccurrences(of: "Last night ", with: "")): \(count) days")
}
let limited = Dictionary(grouping: scores.compactMap(\.limitingFactor), by: { $0 }).mapValues(\.count)
if !limited.isEmpty {
    print("  Capped by a limiting factor: " + limited.map { "\($0.key.shortTitle) \($0.value)×" }.joined(separator: ", "))
}

print("\nLAST 14 SCORED DAYS")
print("  \(pad("Date", 12)) Score  \(pad("Band", 14)) " + ContributorKind.allCases.map { pad($0.shortTitle, 10) }.joined())
for score in scores.suffix(14) {
    let parts = ContributorKind.allCases.map { kind in
        pad(score.contributor(kind).map { Format.number($0.subscore) } ?? "·", 10)
    }.joined()
    print("  \(pad(CSVWriter.date(score.day, calendar: calendar), 12)) \(pad(String(score.score), 6)) \(pad(score.category.title, 14)) \(parts)")
}

if let day = options.explain {
    let start = calendar.startOfDay(for: day)
    print("\nEXPLAIN \(CSVWriter.date(start, calendar: calendar))")
    if let score = analysis.scores[start] {
        print("  Score \(score.score) · \(score.category.title) · raw \(Format.number(score.rawScore, digits: 1))\(score.limitingFactor.map { " · capped by \($0.shortTitle)" } ?? "")")
        for contributor in score.contributors {
            print("  ▸ \(contributor.kind.title): \(Format.number(contributor.subscore)) (weight \(Format.number(contributor.effectiveWeight * 100))%) — \(contributor.headline)")
            for component in contributor.components {
                print("      \(pad(component.label, 30)) \(pad(component.value, 16)) \(component.note ?? "")")
            }
        }
    } else {
        print("  Not scored (not enough data that day).")
    }
}

if let csvPath = options.csvPath {
    let csvURL = URL(fileURLWithPath: (csvPath as NSString).expandingTildeInPath)
    do {
        try ReadinessExport.csv(analysis, calendar: calendar).write(to: csvURL, atomically: true, encoding: .utf8)
        print("\nWrote \(csvURL.path)")
    } catch {
        fail("couldn't write CSV: \(error.localizedDescription)")
    }
}
