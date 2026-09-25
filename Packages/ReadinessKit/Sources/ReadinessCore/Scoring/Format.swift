import Foundation

/// Locale-aware formatting used in engine-generated explanations.
public enum Format {
    public static func number(_ value: Double, digits: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }

    public static func signed(_ value: Double, digits: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(digits)).sign(strategy: .always(includingZero: false)))
    }

    /// "7h 32m".
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        let h = minutes / 60
        let m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    /// "12% above" / "8% below" / "right at".
    public static func relative(_ value: Double, to reference: Double) -> String {
        guard reference != 0 else { return "—" }
        let pct = (value / reference - 1) * 100
        if abs(pct) < 1 { return "right at" }
        return "\(number(abs(pct)))% \(pct > 0 ? "above" : "below")"
    }
}
