import Foundation

/// Small, dependency-free statistics helpers. Robust (median/MAD) estimators are used throughout
/// because wearable data is full of outliers: a single missed night or a sensor glitch should not
/// drag a personal baseline around.
public enum Stats {
    public static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Median absolute deviation.
    public static func mad(_ values: [Double]) -> Double? {
        guard let m = median(values) else { return nil }
        return median(values.map { abs($0 - m) })
    }

    /// Geometric mean — the right average for log-normally distributed metrics such as HRV.
    public static func geometricMean(_ values: [Double]) -> Double? {
        let positive = values.filter { $0 > 0 }
        guard !positive.isEmpty else { return nil }
        return exp(positive.map(log).reduce(0, +) / Double(positive.count))
    }

    /// Weighted mean, ignoring zero-weight entries. Returns nil if the total weight is zero.
    public static func weightedMean(_ pairs: [(value: Double, weight: Double)]) -> Double? {
        let total = pairs.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return nil }
        return pairs.reduce(0) { $0 + $1.value * $1.weight } / total
    }

    /// Maps a z-score to a 0–100 subscore with a smooth logistic curve.
    ///
    /// Calibrated so that z = 0 (exactly your baseline) gives 70 — "Ready" territory — while
    /// z = +1 ≈ 88, z = −1 ≈ 44 and z = −2 ≈ 21. Being average for *you* is a good day, not a mediocre one.
    public static func subscore(fromZ z: Double) -> Double {
        let clamped = min(max(z, -4), 4)
        return 100 / (1 + exp(-(1.1 * clamped + 0.847)))
    }

    /// Linear interpolation of `x` from [x0, x1] to [y0, y1], clamped to the output range.
    public static func interpolate(_ x: Double, from x0: Double, _ x1: Double, to y0: Double, _ y1: Double) -> Double {
        guard x1 != x0 else { return y0 }
        let t = min(max((x - x0) / (x1 - x0), 0), 1)
        return y0 + t * (y1 - y0)
    }

    public static func clamp(_ x: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(x, lower), upper)
    }
}

extension Baseline {
    /// Builds a robust baseline, or nil if there are fewer than `minimumCount` values.
    ///
    /// - Parameter minimumSpread: floor for the spread so an unusually stable history doesn't turn
    ///   tiny day-to-day noise into large z-scores.
    public static func robust(_ values: [Double], minimumCount: Int, minimumSpread: Double) -> Baseline? {
        guard values.count >= minimumCount,
              let median = Stats.median(values),
              let mad = Stats.mad(values)
        else { return nil }
        return Baseline(median: median, spread: max(mad * 1.4826, minimumSpread), count: values.count)
    }
}
