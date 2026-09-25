import ReadinessCore
import SwiftUI

/// Compact card: latest value, period average, direction, and a small chart.
private struct TrendSummaryCard: View {
    let metric: MetricKind
    let points: [TrendPoint]

    private var values: [Double] { points.compactMap(\.value) }

    var body: some View {
        Card(title: LocalizedStringKey(metric.title), systemImage: metric.systemImage) {
            if let latest = values.last, let average = Stats.mean(values) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading) {
                            Text("Latest").font(.caption).foregroundStyle(.secondary)
                            Text(display(latest)).font(.title3.bold().monospacedDigit())
                        }
                        Spacer()
                        VStack(alignment: .leading) {
                            Text("Average").font(.caption).foregroundStyle(.secondary)
                            Text(display(average)).font(.title3.monospacedDigit())
                        }
                        Spacer()
                        TrendDirectionBadge(values: values, inPoints: metric == .readiness || metric == .sleepScore)
                    }
                    MetricTrendChart(metric: metric, points: points, height: 120, interactive: false)
                }
                .accessibilityElement(children: .contain)
            } else {
                Text("No data in this period").foregroundStyle(.secondary)
            }
        }
    }

    private func display(_ value: Double) -> String {
        if metric == .sleepDuration { return Format.duration(value * 3600) }
        let number = Format.number(value, digits: metric.fractionDigits)
        return metric.unit.isEmpty ? number : "\(number) \(metric.unit)"
    }
}

/// Direction of the least-squares slope across the period: a percentage change for measurements,
/// or a change in points for scores (a "+70%" readiness trend would be meaningless).
struct TrendDirectionBadge: View {
    let values: [Double]
    var inPoints = false

    private var change: Double? {
        guard values.count >= 5, let mean = Stats.mean(values), mean != 0 else { return nil }
        let n = Double(values.count)
        let xMean = (n - 1) / 2
        var numerator = 0.0
        var denominator = 0.0
        for (i, y) in values.enumerated() {
            numerator += (Double(i) - xMean) * (y - mean)
            denominator += (Double(i) - xMean) * (Double(i) - xMean)
        }
        let total = numerator / denominator * (n - 1)
        return inPoints ? total : total / abs(mean) * 100
    }

    var body: some View {
        if let change {
            let flat = inPoints ? abs(change) < 0.5 : abs(change) < 3
            let text = inPoints ? "\(Format.signed(change, digits: 1)) pts" : "\(Format.signed(change))%"
            Label(flat ? "Steady" : text, systemImage: flat ? "arrow.right" : (change > 0 ? "arrow.up.right" : "arrow.down.right"))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
                .accessibilityLabel(flat ? "Trend steady" : "Trend \(text) over the period")
        }
    }
}

/// Full-screen, interactive version of one metric with summary statistics.
struct MetricDetailView: View {
    let metric: MetricKind

    @Environment(ReadinessStore.self) private var store
    @State private var range = TrendRange.month

    var body: some View {
        let points = store.analysis.trend(metric, lastDays: range.days)
        let values = points.compactMap(\.value)
        ScrollView {
            VStack(spacing: 16) {
                Picker("Range", selection: $range) {
                    ForEach(TrendRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                if metric == .trainingLoad {
                    Card(title: "Daily load and averages", systemImage: metric.systemImage) {
                        TrainingLoadChart(points: store.analysis.loadTrend(lastDays: max(range.days, 28)))
                    }
                } else {
                    TrendCard(metric: metric, points: points)
                }

                if let min = values.min(), let max = values.max(), let mean = Stats.mean(values) {
                    HStack {
                        StatPill(title: "Low", value: Format.number(min, digits: metric.fractionDigits))
                        StatPill(title: "Average", value: Format.number(mean, digits: metric.fractionDigits))
                        StatPill(title: "High", value: Format.number(max, digits: metric.fractionDigits))
                    }
                    let inRange = points.filter { point in
                        guard let value = point.value, let normal = point.normalRange else { return false }
                        return normal.contains(value)
                    }.count
                    let comparable = points.filter { $0.value != nil && $0.normalRange != nil }.count
                    if comparable > 0 {
                        Card(title: "Within your normal", systemImage: "scope") {
                            Text("\(inRange) of \(comparable) days (\(Format.number(Double(inRange) / Double(comparable) * 100))%) were inside your personal normal range.")
                                .font(.subheadline)
                        }
                    }
                }

                if let kind = contributorKind {
                    Card(title: "About this measure", systemImage: "book") {
                        Text(kind.explanation).font(.subheadline)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var contributorKind: ContributorKind? {
        switch metric {
        case .hrv: .hrv
        case .restingHeartRate: .restingHeartRate
        case .sleepDuration, .sleepScore: .sleep
        case .trainingLoad, .activeEnergy: .trainingLoad
        case .respiratoryRate, .wristTemperature, .oxygenSaturation: .vitals
        case .readiness: nil
        }
    }
}
