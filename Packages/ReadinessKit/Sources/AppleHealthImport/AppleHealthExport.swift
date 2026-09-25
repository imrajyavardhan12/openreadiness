import Foundation
import HealthInsights
import ReadinessCore

/// Everything recovered from a Health app export, in the same shapes the engine and explorer use.
public struct ImportedHealthData: Sendable, Codable {
    public var raw: RawHealthData
    public var daily: [HealthMetric: [DailyValue]]
    public var workouts: [WorkoutSummary]
    public var rings: [ActivityRingDay]
    /// Every heart-rate sample, for the day timeline and workout zone charts.
    public var heartRateSamples: [TimedValue]
    /// Steps per hour (largest single source per hour), for the day timeline.
    public var hourlySteps: [TimedValue]
    /// When the user exported the data, if recorded in the file.
    public var exportDate: Date?
    /// Earliest and latest sample seen.
    public var coverage: DateInterval?

    public init(
        raw: RawHealthData, daily: [HealthMetric: [DailyValue]], workouts: [WorkoutSummary],
        rings: [ActivityRingDay], heartRateSamples: [TimedValue] = [], hourlySteps: [TimedValue] = [],
        exportDate: Date?, coverage: DateInterval?
    ) {
        self.raw = raw
        self.daily = daily
        self.workouts = workouts
        self.rings = rings
        self.heartRateSamples = heartRateSamples
        self.hourlySteps = hourlySteps
        self.exportDate = exportDate
        self.coverage = coverage
    }
}

public enum AppleHealthExportError: Error, LocalizedError {
    case unreadable(URL)
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let url): "Couldn't open \(url.lastPathComponent). Choose the export.xml file from the unzipped Health export."
        case .malformed(let reason): "This doesn't look like a Health export: \(reason)"
        }
    }
}

/// Parses `export.xml` from the Health app's "Export All Health Data".
///
/// The file is streamed (exports are routinely hundreds of MB) and only the record types the app
/// uses are kept. Unlike HealthKit queries, the export is not de-duplicated, so cumulative totals
/// (steps, energy) take the largest single source per day rather than summing iPhone + Watch.
public enum AppleHealthExport {
    public static func parse(contentsOf url: URL, calendar: Calendar = .current) throws -> ImportedHealthData {
        guard let stream = InputStream(url: url) else { throw AppleHealthExportError.unreadable(url) }
        return try parse(XMLParser(stream: stream), calendar: calendar)
    }

    public static func parse(data: Data, calendar: Calendar = .current) throws -> ImportedHealthData {
        try parse(XMLParser(data: data), calendar: calendar)
    }

    private static func parse(_ parser: XMLParser, calendar: Calendar) throws -> ImportedHealthData {
        let delegate = ExportParserDelegate(calendar: calendar)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            throw AppleHealthExportError.malformed(parser.parserError?.localizedDescription ?? "unknown XML error")
        }
        guard delegate.sawHealthData else {
            throw AppleHealthExportError.malformed("no <HealthData> element")
        }
        return delegate.result()
    }
}

// MARK: - Parsing helpers (internal for tests)

enum ExportDates {
    /// Parses "2026-09-24 21:03:11 +0530" without DateFormatter (≈50× faster over a million records).
    static func parse(_ string: String) -> Date? {
        let bytes = Array(string.utf8)
        guard bytes.count >= 25 else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for index in range {
                let digit = Int(bytes[index]) - 48
                guard (0...9).contains(digit) else { return nil }
                value = value * 10 + digit
            }
            return value
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
              let hour = number(11..<13), let minute = number(14..<16), let second = number(17..<19),
              let offsetHours = number(21..<23), let offsetMinutes = number(23..<25)
        else { return nil }
        let sign = bytes[20] == UInt8(ascii: "-") ? -1 : 1
        let days = daysFromCivil(year: year, month: month, day: day)
        let local = days * 86_400 + hour * 3_600 + minute * 60 + second
        let offset = sign * (offsetHours * 3_600 + offsetMinutes * 60)
        return Date(timeIntervalSince1970: TimeInterval(local - offset))
    }

    /// Days since 1970-01-01 for a proleptic Gregorian date (Howard Hinnant's algorithm).
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let monthIndex = month > 2 ? month - 3 : month + 9
        let dayOfYear = (153 * monthIndex + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// Seconds after midnight for a beat time such as "9:41:23.45 PM".
    ///
    /// Recent iOS versions separate the time and AM/PM with U+202F (narrow no-break space), so split
    /// on any whitespace rather than an ASCII space.
    static func secondsOfDay(_ string: String) -> Double? {
        let parts = string.split(whereSeparator: \.isWhitespace)
        guard let clock = parts.first else { return nil }
        let fields = clock.split(separator: ":")
        guard fields.count == 3, var hour = Double(fields[0]), let minute = Double(fields[1]), let second = Double(fields[2]) else {
            return nil
        }
        if parts.count > 1 {
            let meridiem = parts[1].uppercased()
            if meridiem == "PM", hour < 12 { hour += 12 }
            if meridiem == "AM", hour == 12 { hour = 0 }
        }
        return hour * 3_600 + minute * 60 + second
    }

    /// Beats from clock times, unwrapping midnight so time keeps increasing.
    static func heartbeats(fromClockTimes times: [Double]) -> [Heartbeat] {
        guard let first = times.first else { return [] }
        var dayOffset = 0.0
        var previous = first
        return times.map { time in
            if time + dayOffset < previous - 43_200 { dayOffset += 86_400 }
            let absolute = time + dayOffset
            previous = absolute
            return Heartbeat(time: absolute - first)
        }
    }
}

enum ExportTypes {
    /// HealthKit identifier (as written in the export) → explorer metric.
    static let metrics: [String: HealthMetric] = [
        "HKQuantityTypeIdentifierHeartRate": .heartRate,
        "HKQuantityTypeIdentifierRestingHeartRate": .restingHeartRate,
        "HKQuantityTypeIdentifierWalkingHeartRateAverage": .walkingHeartRate,
        "HKQuantityTypeIdentifierHeartRateVariabilitySDNN": .hrv,
        "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute": .heartRateRecovery,
        "HKQuantityTypeIdentifierVO2Max": .vo2Max,
        "HKQuantityTypeIdentifierStepCount": .steps,
        "HKQuantityTypeIdentifierActiveEnergyBurned": .activeEnergy,
        "HKQuantityTypeIdentifierAppleExerciseTime": .exerciseTime,
        "HKQuantityTypeIdentifierAppleStandTime": .standTime,
        "HKQuantityTypeIdentifierDistanceWalkingRunning": .distance,
        "HKQuantityTypeIdentifierFlightsClimbed": .flightsClimbed,
        "HKQuantityTypeIdentifierRespiratoryRate": .respiratoryRate,
        "HKQuantityTypeIdentifierOxygenSaturation": .oxygenSaturation,
        "HKQuantityTypeIdentifierAppleSleepingWristTemperature": .wristTemperature,
        "HKQuantityTypeIdentifierWalkingSpeed": .walkingSpeed,
        "HKQuantityTypeIdentifierWalkingStepLength": .walkingStepLength,
        "HKQuantityTypeIdentifierWalkingAsymmetryPercentage": .walkingAsymmetry,
        "HKQuantityTypeIdentifierEnvironmentalAudioExposure": .environmentalAudio,
        "HKQuantityTypeIdentifierHeadphoneAudioExposure": .headphoneAudio,
        "HKQuantityTypeIdentifierTimeInDaylight": .timeInDaylight,
    ]

    /// Converts an exported value to the explorer's display unit.
    static func normalize(_ value: Double, unit: String, for metric: HealthMetric) -> Double {
        switch (metric, unit) {
        case (.activeEnergy, "kJ"): value / 4.184
        case (.distance, "mi"): value * 1.609344
        case (.distance, "m"): value / 1000
        case (.walkingSpeed, "mi/hr"): value * 1.609344
        case (.walkingSpeed, "m/s"): value * 3.6
        case (.walkingStepLength, "in"): value * 2.54
        case (.walkingStepLength, "m"): value * 100
        case (.wristTemperature, "degF"): (value - 32) * 5 / 9
        case (.oxygenSaturation, _), (.walkingAsymmetry, _): value <= 1 ? value * 100 : value
        default: value
        }
    }

    static let sleepStages: [String: SleepStage] = [
        "HKCategoryValueSleepAnalysisInBed": .inBed,
        "HKCategoryValueSleepAnalysisAwake": .awake,
        "HKCategoryValueSleepAnalysisAsleepCore": .core,
        "HKCategoryValueSleepAnalysisAsleepDeep": .deep,
        "HKCategoryValueSleepAnalysisAsleepREM": .rem,
        "HKCategoryValueSleepAnalysisAsleepUnspecified": .asleepUnspecified,
        "HKCategoryValueSleepAnalysisAsleep": .asleepUnspecified,
    ]

    /// "HKWorkoutActivityTypeFunctionalStrengthTraining" → "Functional Strength Training".
    static func activityName(_ type: String) -> String {
        let name = type.replacingOccurrences(of: "HKWorkoutActivityType", with: "")
        let overrides = [
            "TraditionalStrengthTraining": "Strength Training",
            "HighIntensityIntervalTraining": "HIIT",
            "DownhillSkiing": "Skiing",
        ]
        if let override = overrides[name] { return override }
        var words = ""
        for character in name {
            if character.isUppercase, !words.isEmpty { words += " " }
            words.append(character)
        }
        return words.isEmpty ? "Workout" : words
    }
}

// MARK: - SAX delegate

/// Accumulates state while streaming. Not thread-safe; used from a single `XMLParser.parse()` call.
final class ExportParserDelegate: NSObject, XMLParserDelegate {
    private let calendar: Calendar
    private(set) var sawHealthData = false

    private var sleep: [SleepSegment] = []
    private var sdnn: [TimedValue] = []
    private var rmssd: [TimedValue] = []
    private var resting: [TimedValue] = []
    private var respiratory: [TimedValue] = []
    private var temperature: [TimedValue] = []
    private var oxygen: [TimedValue] = []
    private var heartRateBuckets: [Int: (sum: Double, count: Int)] = [:]
    private var heartRateSamples: [TimedValue] = []
    private var hourlySteps: [Int: [String: Double]] = [:]
    private var efforts: [(date: Date, value: Double, estimated: Bool)] = []
    private var age: Int?
    private var exportDate: Date?
    private var earliest: Date?
    private var latest: Date?

    /// Discrete samples per metric per day: (sum, count, min, max).
    private var discrete: [HealthMetric: [Date: (sum: Double, count: Int, min: Double, max: Double)]] = [:]
    /// Cumulative samples per metric per day per source.
    private var cumulative: [HealthMetric: [Date: [String: Double]]] = [:]

    private var rings: [ActivityRingDay] = []
    private var workouts: [(record: WorkoutRecord, summary: WorkoutSummary)] = []

    // Open-element state
    private var hrvRecordStart: Date?
    private var beatClockTimes: [Double] = []
    private var openWorkout: [String: String]?
    private var workoutStats: [String: [String: String]] = [:]

    init(calendar: Calendar) {
        self.calendar = calendar
    }

    func parser(
        _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
        qualifiedName: String?, attributes: [String: String] = [:]
    ) {
        switch name {
        case "Record": record(attributes)
        case "InstantaneousBeatsPerMinute":
            if hrvRecordStart != nil, let time = attributes["time"].flatMap(ExportDates.secondsOfDay) {
                beatClockTimes.append(time)
            }
        case "Workout":
            openWorkout = attributes
            workoutStats = [:]
        case "WorkoutStatistics":
            if openWorkout != nil, let type = attributes["type"] { workoutStats[type] = attributes }
        case "ActivitySummary": activitySummary(attributes)
        case "Me":
            if let birthday = attributes["HKCharacteristicTypeIdentifierDateOfBirth"], birthday.count >= 4,
               let year = Int(birthday.prefix(4)) {
                age = calendar.component(.year, from: exportDate ?? .now) - year
            }
        case "ExportDate": exportDate = attributes["value"].flatMap(ExportDates.parse)
        case "HealthData": sawHealthData = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "Record":
            if let start = hrvRecordStart {
                if let value = RMSSD.compute(ExportDates.heartbeats(fromClockTimes: beatClockTimes)) {
                    rmssd.append(TimedValue(date: start, value: value))
                }
                hrvRecordStart = nil
                beatClockTimes = []
            }
        case "Workout":
            if let attributes = openWorkout { workout(attributes, stats: workoutStats) }
            openWorkout = nil
        default: break
        }
    }

    private func record(_ attributes: [String: String]) {
        guard let type = attributes["type"],
              let start = attributes["startDate"].flatMap(ExportDates.parse)
        else { return }
        let end = attributes["endDate"].flatMap(ExportDates.parse) ?? start
        let source = attributes["sourceName"] ?? "unknown"
        earliest = min(earliest ?? start, start)
        latest = max(latest ?? end, end)

        if type == "HKCategoryTypeIdentifierSleepAnalysis" {
            if let stage = attributes["value"].flatMap({ ExportTypes.sleepStages[$0] }) {
                sleep.append(SleepSegment(start: start, end: end, stage: stage, sourceID: source))
            }
            return
        }
        guard let value = attributes["value"].flatMap(Double.init) else { return }
        let unit = attributes["unit"] ?? ""

        switch type {
        case "HKQuantityTypeIdentifierEstimatedWorkoutEffortScore":
            efforts.append((start, value, true))
        case "HKQuantityTypeIdentifierWorkoutEffortScore":
            efforts.append((start, value, false))
        default: break
        }

        guard let metric = ExportTypes.metrics[type] else { return }
        let normalized = ExportTypes.normalize(value, unit: unit, for: metric)

        // Readiness engine inputs.
        switch metric {
        case .hrv:
            sdnn.append(TimedValue(date: start, value: normalized))
            hrvRecordStart = start
            beatClockTimes = []
        case .heartRate:
            let bucket = Int((start.timeIntervalSince1970 / 1800).rounded(.down))
            let current = heartRateBuckets[bucket] ?? (0, 0)
            heartRateBuckets[bucket] = (current.sum + normalized, current.count + 1)
            heartRateSamples.append(TimedValue(date: start, value: normalized))
        case .steps:
            let hour = Int((start.timeIntervalSince1970 / 3600).rounded(.down))
            hourlySteps[hour, default: [:]][source, default: 0] += normalized
        case .restingHeartRate: resting.append(TimedValue(date: start, value: normalized))
        case .respiratoryRate: respiratory.append(TimedValue(date: start, value: normalized))
        case .wristTemperature: temperature.append(TimedValue(date: start, value: normalized))
        case .oxygenSaturation: oxygen.append(TimedValue(date: start, value: normalized))
        default: break
        }

        // Explorer daily series.
        let day = calendar.startOfDay(for: start)
        if metric.aggregation == .sum {
            cumulative[metric, default: [:]][day, default: [:]][source, default: 0] += normalized
        } else {
            let current = discrete[metric]?[day] ?? (0, 0, .infinity, -.infinity)
            discrete[metric, default: [:]][day] = (
                current.sum + normalized, current.count + 1,
                Swift.min(current.min, normalized), Swift.max(current.max, normalized)
            )
        }
    }

    private func activitySummary(_ attributes: [String: String]) {
        guard let components = attributes["dateComponents"], components.count == 10,
              let date = ExportDates.parse(components + " 12:00:00 +0000")
        else { return }
        func value(_ key: String) -> Double { attributes[key].flatMap(Double.init) ?? 0 }
        rings.append(ActivityRingDay(
            date: calendar.startOfDay(for: date),
            move: value("activeEnergyBurned"), moveGoal: value("activeEnergyBurnedGoal"),
            exercise: value("appleExerciseTime"), exerciseGoal: max(value("appleExerciseTimeGoal"), 1),
            stand: value("appleStandHours"), standGoal: max(value("appleStandHoursGoal"), 1)
        ))
    }

    private func workout(_ attributes: [String: String], stats: [String: [String: String]]) {
        guard let start = attributes["startDate"].flatMap(ExportDates.parse),
              let end = attributes["endDate"].flatMap(ExportDates.parse)
        else { return }
        let name = ExportTypes.activityName(attributes["workoutActivityType"] ?? "")
        let heartRate = stats["HKQuantityTypeIdentifierHeartRate"]
        var energy = stats["HKQuantityTypeIdentifierActiveEnergyBurned"]?["sum"].flatMap(Double.init)
            ?? attributes["totalEnergyBurned"].flatMap(Double.init)
        if stats["HKQuantityTypeIdentifierActiveEnergyBurned"]?["unit"] == "kJ" { energy = energy.map { $0 / 4.184 } }
        let distanceStats = ["HKQuantityTypeIdentifierDistanceWalkingRunning", "HKQuantityTypeIdentifierDistanceCycling", "HKQuantityTypeIdentifierDistanceSwimming"]
            .compactMap { stats[$0] }.first
        var distanceMeters: Double?
        if let distanceStats, let sum = distanceStats["sum"].flatMap(Double.init) {
            distanceMeters = switch distanceStats["unit"] {
            case "km": sum * 1000
            case "mi": sum * 1609.344
            case "yd": sum * 0.9144
            default: sum
            }
        }
        let average = heartRate?["average"].flatMap(Double.init)
        let record = WorkoutRecord(start: start, end: end, activityName: name, activeEnergyKcal: energy, averageHeartRate: average)
        let summary = WorkoutSummary(
            id: Self.stableID(for: start, name: name),
            activityName: name, start: start, end: end,
            activeEnergyKcal: energy, distanceMeters: distanceMeters,
            averageHeartRate: average, maxHeartRate: heartRate?["maximum"].flatMap(Double.init)
        )
        workouts.append((record, summary))
    }

    /// Deterministic ID so re-importing the same export yields the same workout identities.
    static func stableID(for start: Date, name: String) -> UUID {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325 // FNV-1a
        for byte in "\(start.timeIntervalSince1970)|\(name)".utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        let a = hash, b = hash &* 0x9E37_79B9_7F4A_7C15
        let bytes = (0..<8).map { UInt8(truncatingIfNeeded: a >> ($0 * 8)) } + (0..<8).map { UInt8(truncatingIfNeeded: b >> ($0 * 8)) }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    func result() -> ImportedHealthData {
        // Attach effort scores to the workouts they fall within; a user rating beats Apple's estimate.
        let scoredWorkouts = workouts.map { item -> (WorkoutRecord, WorkoutSummary) in
            var record = item.record
            let interval = DateInterval(start: record.start, end: max(record.end, record.start))
            if let effort = efforts.filter({ interval.contains($0.date) }).sorted(by: { !$0.estimated && $1.estimated }).first {
                record.effortScore = effort.value
                record.effortIsEstimated = effort.estimated
            }
            return (record, item.summary)
        }

        var daily: [HealthMetric: [DailyValue]] = [:]
        for (metric, days) in discrete where metric.aggregation != .range {
            daily[metric] = days.map { day, v in
                DailyValue(date: day, value: v.sum / Double(v.count), min: metric.aggregation == .range ? v.min : nil, max: metric.aggregation == .range ? v.max : nil)
            }
            .sorted { $0.date < $1.date }
        }
        // Heart rate: time-weighted from hourly buckets (see SeriesAnalytics.dailyFromHourly).
        let hourly = Dictionary(grouping: heartRateSamples) { Int(($0.date.timeIntervalSince1970 / 3600).rounded(.down)) }
            .map { hour, samples in
                let values = samples.map(\.value)
                return DailyValue(
                    date: Date(timeIntervalSince1970: TimeInterval(hour) * 3600),
                    value: values.reduce(0, +) / Double(values.count),
                    min: values.min(),
                    max: values.max()
                )
            }
        if !hourly.isEmpty {
            daily[.heartRate] = SeriesAnalytics.dailyFromHourly(hourly, calendar: calendar)
        }
        for (metric, days) in cumulative {
            // Largest single source per day, instead of double counting iPhone + Watch.
            daily[metric] = days.map { day, bySource in DailyValue(date: day, value: bySource.values.max() ?? 0) }
                .sorted { $0.date < $1.date }
        }

        let raw = RawHealthData(
            sleep: sleep.sorted { $0.start < $1.start },
            hrv: sdnn.sorted { $0.date < $1.date },
            rmssd: rmssd.sorted { $0.date < $1.date },
            heartRateBuckets: heartRateBuckets
                .map { TimedValue(date: Date(timeIntervalSince1970: TimeInterval($0.key) * 1800), value: $0.value.sum / Double($0.value.count)) }
                .sorted { $0.date < $1.date },
            restingHeartRate: resting.sorted { $0.date < $1.date },
            respiratoryRate: respiratory.sorted { $0.date < $1.date },
            wristTemperature: temperature.sorted { $0.date < $1.date },
            oxygenSaturation: oxygen.sorted { $0.date < $1.date },
            workouts: scoredWorkouts.map(\.0).sorted { $0.start < $1.start },
            activeEnergyDaily: (daily[.activeEnergy] ?? []).map { TimedValue(date: $0.date, value: $0.value) },
            profile: UserProfile(age: age)
        )
        return ImportedHealthData(
            raw: raw,
            daily: daily,
            workouts: scoredWorkouts.map(\.1).sorted { $0.start > $1.start },
            rings: rings.sorted { $0.date < $1.date },
            heartRateSamples: heartRateSamples.sorted { $0.date < $1.date },
            hourlySteps: hourlySteps
                .map { TimedValue(date: Date(timeIntervalSince1970: TimeInterval($0.key) * 3600), value: $0.value.values.max() ?? 0) }
                .sorted { $0.date < $1.date },
            exportDate: exportDate,
            coverage: earliest.flatMap { start in latest.map { DateInterval(start: start, end: max($0, start)) } }
        )
    }
}
