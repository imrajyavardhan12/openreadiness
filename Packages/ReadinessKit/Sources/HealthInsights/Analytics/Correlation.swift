import Foundation
import ReadinessCore

/// Anything that has one value per day and can be related to something else.
public enum InsightVariable: Sendable, Hashable, Identifiable {
    case metric(HealthMetric)
    case sleepDuration
    /// Minutes relative to midnight of the wake day (negative = before midnight).
    case bedtime
    case overnightHRV
    case sleepingHeartRate
    case trainingLoad
    case readiness

    public var id: String {
        switch self {
        case .metric(let metric): "metric.\(metric.rawValue)"
        case .sleepDuration: "sleepDuration"
        case .bedtime: "bedtime"
        case .overnightHRV: "overnightHRV"
        case .sleepingHeartRate: "sleepingHeartRate"
        case .trainingLoad: "trainingLoad"
        case .readiness: "readiness"
        }
    }

    public var title: String {
        switch self {
        case .metric(let metric): metric.title
        case .sleepDuration: "Time Asleep"
        case .bedtime: "Bedtime"
        case .overnightHRV: "Overnight HRV"
        case .sleepingHeartRate: "Sleeping Heart Rate"
        case .trainingLoad: "Training Load"
        case .readiness: "Readiness"
        }
    }

    public var systemImage: String {
        switch self {
        case .metric(let metric): metric.systemImage
        case .sleepDuration: "bed.double.fill"
        case .bedtime: "moon.fill"
        case .overnightHRV: "waveform.path.ecg"
        case .sleepingHeartRate: "heart"
        case .trainingLoad: "figure.run"
        case .readiness: "gauge.with.dots.needle.67percent"
        }
    }

    /// Formats a value of this variable for display.
    public func format(_ value: Double) -> String {
        switch self {
        case .metric(let metric):
            let number = Format.number(value, digits: metric.fractionDigits)
            return "\(number) \(metric.unit)"
        case .sleepDuration: return Format.duration(value * 3600)
        case .bedtime: return Self.clock(minutes: value)
        case .overnightHRV: return "\(Format.number(value)) ms"
        case .sleepingHeartRate: return "\(Format.number(value)) bpm"
        case .trainingLoad: return Format.number(value)
        case .readiness: return Format.number(value, digits: 1)
        }
    }

    /// Formats a difference between two values of this variable.
    public func formatDifference(_ delta: Double) -> String {
        switch self {
        case .sleepDuration, .bedtime:
            let minutes = self == .sleepDuration ? delta * 60 : delta
            return "\(Format.number(abs(minutes))) min"
        default:
            return format(abs(delta))
        }
    }

    /// Title for use mid-sentence: lower-cased, but acronyms kept ("overnight HRV").
    var inlineTitle: String {
        title.lowercased().replacingOccurrences(of: "hrv", with: "HRV")
    }

    /// "longer sleep", "later bedtimes", "more steps" — used in insight headlines.
    var morePhrase: String {
        switch self {
        case .sleepDuration: "longer sleep"
        case .bedtime: "later bedtimes"
        case .trainingLoad: "harder training days"
        case .metric(let metric) where metric.aggregation == .sum: "more \(metric.title.lowercased())"
        default: "higher \(inlineTitle)"
        }
    }

    /// "11:15 PM" for minutes relative to midnight (negative = the evening before).
    public static func clock(minutes: Double) -> String {
        let total = (Int(minutes.rounded()) % 1440 + 1440) % 1440
        var components = DateComponents()
        components.hour = total / 60
        components.minute = total % 60
        let date = Calendar(identifier: .gregorian).date(from: components) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

public struct CorrelationResult: Sendable, Hashable {
    /// Spearman's rank correlation, −1…1.
    public var rho: Double
    public var n: Int
    /// t statistic for rho; |t| ≳ 2 is roughly p < 0.05.
    public var t: Double

    public var isSignificant: Bool { n >= 10 && abs(t) >= 2 }

    public var strength: String {
        switch abs(rho) {
        case ..<0.1: "No clear"
        case ..<0.3: "Weak"
        case ..<0.5: "Moderate"
        default: "Strong"
        }
    }
}

public struct PairedPoint: Sendable, Hashable, Identifiable {
    public var day: Date
    public var x: Double
    public var y: Double
    public var id: Date { day }
}

public enum Correlation {
    public static func pearson(_ x: [Double], _ y: [Double]) -> Double? {
        guard x.count == y.count, x.count >= 3,
              let mx = Stats.mean(x), let my = Stats.mean(y)
        else { return nil }
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for (a, b) in zip(x, y) {
            sxy += (a - mx) * (b - my)
            sxx += (a - mx) * (a - mx)
            syy += (b - my) * (b - my)
        }
        guard sxx > 0, syy > 0 else { return nil }
        return sxy / (sxx * syy).squareRoot()
    }

    /// Ranks with ties sharing their average rank.
    static func ranks(_ values: [Double]) -> [Double] {
        let order = values.indices.sorted { values[$0] < values[$1] }
        var ranks = Array(repeating: 0.0, count: values.count)
        var i = 0
        while i < order.count {
            var j = i
            while j + 1 < order.count, values[order[j + 1]] == values[order[i]] { j += 1 }
            let average = Double(i + j) / 2 + 1
            for k in i...j { ranks[order[k]] = average }
            i = j + 1
        }
        return ranks
    }

    /// Spearman's rho: robust to outliers and to non-linear but monotonic relationships.
    public static func spearman(_ x: [Double], _ y: [Double]) -> CorrelationResult? {
        guard let rho = pearson(ranks(x), ranks(y)) else { return nil }
        let n = x.count
        let t = abs(rho) >= 1 ? .infinity : rho * (Double(n - 2) / (1 - rho * rho)).squareRoot()
        return CorrelationResult(rho: rho, n: n, t: t)
    }

    /// Pairs x on day D with y on day D + `lag`.
    public static func pairs(x: [Date: Double], y: [Date: Double], lag: Int, calendar: Calendar) -> [PairedPoint] {
        x.compactMap { day, xValue in
            guard let yDay = calendar.date(byAdding: .day, value: lag, to: day), let yValue = y[yDay] else { return nil }
            return PairedPoint(day: day, x: xValue, y: yValue)
        }
        .sorted { $0.day < $1.day }
    }

    /// Least-squares line through the points, for drawing on a scatter plot.
    public static func regressionLine(_ points: [PairedPoint]) -> (slope: Double, intercept: Double)? {
        guard points.count >= 3,
              let mx = Stats.mean(points.map(\.x)), let my = Stats.mean(points.map(\.y))
        else { return nil }
        let sxx = points.reduce(0) { $0 + ($1.x - mx) * ($1.x - mx) }
        guard sxx > 0 else { return nil }
        let slope = points.reduce(0) { $0 + ($1.x - mx) * ($1.y - my) } / sxx
        return (slope, my - slope * mx)
    }
}

/// One plain-language finding about how two of your own metrics move together.
public struct Insight: Sendable, Hashable, Identifiable {
    public var x: InsightVariable
    public var y: InsightVariable
    public var lag: Int
    public var correlation: CorrelationResult
    /// Median of x, used to split days into "higher" and "lower".
    public var threshold: Double
    public var highMean: Double
    public var lowMean: Double
    public var headline: String
    public var detail: String

    public var id: String { "\(x.id)->\(y.id)@\(lag)" }
}

public struct InsightCandidate: Sendable, Hashable {
    public var x: InsightVariable
    public var y: InsightVariable
    /// Days from x to y (1 = "the next day/night").
    public var lag: Int

    public init(_ x: InsightVariable, _ y: InsightVariable, lag: Int) {
        self.x = x
        self.y = y
        self.lag = lag
    }

    /// Relationships that are plausible and actionable, chosen up front rather than mined from every
    /// possible pair — testing everything against everything would mostly surface chance findings.
    public static let curated: [InsightCandidate] = [
        InsightCandidate(.sleepDuration, .overnightHRV, lag: 0),
        InsightCandidate(.sleepDuration, .sleepingHeartRate, lag: 0),
        InsightCandidate(.bedtime, .sleepDuration, lag: 0),
        InsightCandidate(.bedtime, .overnightHRV, lag: 0),
        InsightCandidate(.trainingLoad, .overnightHRV, lag: 1),
        InsightCandidate(.trainingLoad, .sleepingHeartRate, lag: 1),
        InsightCandidate(.metric(.steps), .sleepDuration, lag: 1),
        InsightCandidate(.metric(.exerciseTime), .sleepDuration, lag: 1),
        InsightCandidate(.metric(.timeInDaylight), .sleepDuration, lag: 1),
        InsightCandidate(.metric(.activeEnergy), .overnightHRV, lag: 1),
        InsightCandidate(.sleepDuration, .readiness, lag: 0),
        // Daytime signals, so people who don't wear the watch to bed still get insights.
        InsightCandidate(.trainingLoad, .metric(.hrv), lag: 1),
        InsightCandidate(.trainingLoad, .metric(.restingHeartRate), lag: 1),
    ]
}

public enum InsightEngine {
    public static let minimumDays = 21

    public static func evaluate(
        _ candidate: InsightCandidate,
        series: [InsightVariable: [Date: Double]],
        calendar: Calendar
    ) -> Insight? {
        guard let xs = series[candidate.x], let ys = series[candidate.y] else { return nil }
        let points = Correlation.pairs(x: xs, y: ys, lag: candidate.lag, calendar: calendar)
        guard points.count >= minimumDays,
              let result = Correlation.spearman(points.map(\.x), points.map(\.y)),
              result.isSignificant, abs(result.rho) >= 0.15,
              let threshold = Stats.median(points.map(\.x))
        else { return nil }

        let high = points.filter { $0.x > threshold }.map(\.y)
        let low = points.filter { $0.x <= threshold }.map(\.y)
        guard let highMean = Stats.mean(high), let lowMean = Stats.mean(low), !high.isEmpty, !low.isEmpty else { return nil }

        let x = candidate.x
        let y = candidate.y
        let when = candidate.lag == 0 ? "" : (candidate.lag == 1 ? " the following night" : " \(candidate.lag) days later")
        let direction = highMean >= lowMean ? "higher" : "lower"
        let xCondition = x == .bedtime ? "you went to bed after \(x.format(threshold))" : "your \(x.inlineTitle) was above \(x.format(threshold))"
        let headline = "\(y.title) is \(direction) after \(x.morePhrase)"
        let detail = "When \(xCondition), your \(y.inlineTitle)\(when) averaged \(y.format(highMean)) versus \(y.format(lowMean)) otherwise — \(y.formatDifference(highMean - lowMean)) \(direction). \(result.strength) relationship across \(result.n) days (ρ = \(Format.number(result.rho, digits: 2)))."

        return Insight(
            x: x, y: y, lag: candidate.lag, correlation: result, threshold: threshold,
            highMean: highMean, lowMean: lowMean, headline: headline, detail: detail
        )
    }

    /// Significant insights, strongest first.
    public static func insights(
        series: [InsightVariable: [Date: Double]],
        candidates: [InsightCandidate] = InsightCandidate.curated,
        calendar: Calendar
    ) -> [Insight] {
        candidates
            .compactMap { evaluate($0, series: series, calendar: calendar) }
            .sorted { abs($0.correlation.rho) > abs($1.correlation.rho) }
    }
}
