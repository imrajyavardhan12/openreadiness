import Foundation

/// One beat from an Apple Watch heartbeat series (`HKHeartbeatSeriesSample`).
public struct Heartbeat: Sendable, Hashable {
    /// Seconds since the start of the series.
    public var time: TimeInterval
    /// True when the watch lost contact before this beat, so the interval since the previous beat is unknown.
    public var precededByGap: Bool

    public init(time: TimeInterval, precededByGap: Bool = false) {
        self.time = time
        self.precededByGap = precededByGap
    }
}

/// Root mean square of successive differences between normal heartbeats — the HRV measure used by
/// most research, Oura and Whoop. Apple Watch only reports SDNN, but it also stores the beat-to-beat
/// timestamps behind each reading, from which RMSSD can be computed.
///
/// RMSSD reflects short-term, parasympathetic ("rest and digest") activity and is less influenced by
/// slow trends within a short recording than SDNN, which makes it the better recovery signal.
public enum RMSSD {
    /// Physiologically plausible RR interval range (ms): 30–200 bpm.
    public static let plausibleInterval: ClosedRange<Double> = 300...2000
    /// Successive intervals differing by more than this fraction are treated as artifacts or
    /// ectopic beats (the widely used 20% rule).
    public static let maximumRelativeChange = 0.2
    /// Fewer clean successive differences than this and the estimate is too noisy to use.
    public static let minimumDifferences = 20

    /// RMSSD in milliseconds, or nil when the series has too few clean beats.
    public static func compute(_ beats: [Heartbeat]) -> Double? {
        guard beats.count > 2 else { return nil }
        // RR intervals; nil marks a break in continuity (gap or implausible interval).
        var intervals: [Double?] = []
        intervals.reserveCapacity(beats.count)
        for (previous, beat) in zip(beats, beats.dropFirst()) {
            guard !beat.precededByGap else {
                intervals.append(nil)
                continue
            }
            let rr = (beat.time - previous.time) * 1000
            intervals.append(plausibleInterval.contains(rr) ? rr : nil)
        }

        var sumOfSquares = 0.0
        var count = 0
        for (a, b) in zip(intervals, intervals.dropFirst()) {
            guard let a, let b, abs(b - a) <= maximumRelativeChange * a else { continue }
            sumOfSquares += (b - a) * (b - a)
            count += 1
        }
        guard count >= minimumDifferences else { return nil }
        return (sumOfSquares / Double(count)).squareRoot()
    }
}
