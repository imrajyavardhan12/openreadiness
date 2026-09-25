import Charts
import HealthInsights
import ReadinessCore
import SwiftUI

/// Relationships between your own metrics: curated automatic findings plus a free explorer.
struct InsightsView: View {
    @Environment(ExplorerStore.self) private var explorer
    @Environment(ReadinessStore.self) private var readiness
    @State private var insights: [Insight]?
    @State private var series: [InsightVariable: [Date: Double]] = [:]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text("Patterns in your own data from the last 90 days. They show what tends to happen together for you — not proof that one causes the other.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let insights {
                    if insights.isEmpty {
                        ContentUnavailableView(
                            "No clear patterns yet",
                            systemImage: "magnifyingglass",
                            description: Text("Insights need at least three weeks of paired data and a relationship strong enough to be unlikely by chance.")
                        )
                    } else {
                        ForEach(insights) { insight in
                            InsightCard(insight: insight, points: points(for: insight))
                        }
                    }
                } else {
                    ProgressView("Looking for patterns…").frame(maxWidth: .infinity, minHeight: 200)
                }

                if !series.isEmpty {
                    CorrelationExplorer(series: series)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Insights")
        .task(id: explorer.hasLoaded) {
            await explorer.loadIfNeeded()
            await compute()
        }
        .onChange(of: readiness.lastUpdated) { Task { await compute() } }
    }

    private func points(for insight: Insight) -> [PairedPoint] {
        Correlation.pairs(x: series[insight.x] ?? [:], y: series[insight.y] ?? [:], lag: insight.lag, calendar: .current)
    }

    private func compute() async {
        guard explorer.hasLoaded else { return }
        let built = buildSeries()
        series = built
        insights = await Task.detached(priority: .userInitiated) {
            InsightEngine.insights(series: built, calendar: .current)
        }.value
    }

    /// Daily values for every variable over the last 90 days.
    private func buildSeries() -> [InsightVariable: [Date: Double]] {
        let calendar = Calendar.current
        var result: [InsightVariable: [Date: Double]] = [:]
        for metric in [HealthMetric.steps, .exerciseTime, .activeEnergy, .timeInDaylight, .restingHeartRate, .standTime, .hrv] {
            let values = explorer.values(metric, lastDays: 91)
            if !values.isEmpty {
                // Today's totals are partial, so leave them out.
                result[.metric(metric)] = Dictionary(
                    values.filter { !calendar.isDateInToday($0.date) || metric.aggregation != .sum }.map { ($0.date, $0.value) },
                    uniquingKeysWith: { a, _ in a }
                )
            }
        }
        var sleep: [Date: Double] = [:], bedtime: [Date: Double] = [:], hrv: [Date: Double] = [:]
        var sleepingHR: [Date: Double] = [:], load: [Date: Double] = [:], score: [Date: Double] = [:]
        for day in readiness.analysis.days {
            if let s = day.sleep {
                sleep[day.day] = s.asleep / 3600
                bedtime[day.day] = s.start.timeIntervalSince(day.day) / 60
            }
            if let value = day.hrvOvernight { hrv[day.day] = value }
            if let value = day.sleepingHeartRate { sleepingHR[day.day] = value }
            if !calendar.isDateInToday(day.day) { load[day.day] = day.trainingLoad }
            if let value = readiness.analysis.scores[day.day] { score[day.day] = Double(value.score) }
        }
        result[.sleepDuration] = sleep
        result[.bedtime] = bedtime
        result[.overnightHRV] = hrv
        result[.sleepingHeartRate] = sleepingHR
        result[.trainingLoad] = load
        result[.readiness] = score
        return result.filter { $0.value.count >= 7 }
    }
}

private struct InsightCard: View {
    let insight: Insight
    let points: [PairedPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: insight.x.systemImage)
                Image(systemName: "arrow.right").font(.caption)
                Image(systemName: insight.y.systemImage)
                Spacer()
                Text(insight.correlation.strength)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.tint.opacity(0.12), in: Capsule())
            }
            .foregroundStyle(.tint)
            .accessibilityHidden(true)

            Text(insight.headline).font(.headline)
            Text(insight.detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScatterChart(points: points, x: insight.x, y: insight.y, threshold: insight.threshold)
                .frame(height: 170)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

/// Pick any two variables and a lag; see the scatter, trend line and strength.
private struct CorrelationExplorer: View {
    let series: [InsightVariable: [Date: Double]]

    @State private var x: InsightVariable = .sleepDuration
    @State private var y: InsightVariable = .overnightHRV
    @State private var lag = 0

    private var variables: [InsightVariable] {
        series.keys.sorted { $0.title < $1.title }
    }

    var body: some View {
        let points = Correlation.pairs(x: series[x] ?? [:], y: series[y] ?? [:], lag: lag, calendar: .current)
        let result = points.count >= 3 ? Correlation.spearman(points.map(\.x), points.map(\.y)) : nil
        Card(title: "Explore a relationship", systemImage: "point.3.connected.trianglepath.dotted") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("When", selection: $x) {
                    ForEach(variables) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                }
                Picker("Then", selection: $y) {
                    ForEach(variables) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                }
                Picker("Timing", selection: $lag) {
                    Text("Same day").tag(0)
                    Text("Next day").tag(1)
                    Text("2 days later").tag(2)
                }
                .pickerStyle(.segmented)

                if points.count >= 3 {
                    ScatterChart(points: points, x: x, y: y, threshold: nil).frame(height: 220)
                }
                if let result {
                    Text("\(result.strength) \(result.rho >= 0 ? "positive" : "negative") relationship · ρ = \(Format.number(result.rho, digits: 2)) · \(result.n) days\(result.isSignificant ? "" : " · could be chance")")
                        .font(.subheadline)
                        .foregroundStyle(result.isSignificant ? .primary : .secondary)
                } else {
                    Text("Not enough overlapping days for these two.").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            // Start on a meaningful question the data can answer, not an arbitrary (or trivially
            // related) pair: sleep → overnight HRV if sleep is tracked, else training → next-day HRV.
            let preferred: [(InsightVariable, InsightVariable, Int)] = [
                (.sleepDuration, .overnightHRV, 0),
                (.trainingLoad, .metric(.hrv), 1),
                (.trainingLoad, .metric(.restingHeartRate), 1),
            ]
            if let pair = preferred.first(where: { (series[$0.0]?.count ?? 0) >= 14 && (series[$0.1]?.count ?? 0) >= 14 }) {
                (x, y, lag) = pair
            } else if let first = variables.first, let last = variables.last {
                (x, y) = (first, last)
            }
        }
    }
}

private struct ScatterChart: View {
    let points: [PairedPoint]
    let x: InsightVariable
    let y: InsightVariable
    let threshold: Double?

    var body: some View {
        let line = Correlation.regressionLine(points)
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        Chart {
            ForEach(points) { point in
                PointMark(x: .value(x.title, point.x), y: .value(y.title, point.y))
                    .foregroundStyle(threshold.map { point.x > $0 ? Color.accentColor : Color.gray.opacity(0.6) } ?? Color.accentColor)
                    .symbolSize(28)
            }
            if let line, let low = xs.min(), let high = xs.max() {
                LineMark(x: .value(x.title, low), y: .value(y.title, line.intercept + line.slope * low), series: .value("fit", "fit"))
                    .foregroundStyle(.primary.opacity(0.6))
                LineMark(x: .value(x.title, high), y: .value(y.title, line.intercept + line.slope * high), series: .value("fit", "fit"))
                    .foregroundStyle(.primary.opacity(0.6))
            }
        }
        .chartXScale(domain: .automatic(includesZero: false))
        .chartYScale(domain: (ys.min() ?? 0)...(ys.max() ?? 1))
        .chartXAxisLabel(x.title)
        .chartYAxisLabel(y.title)
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel { if let v = value.as(Double.self) { Text(axisLabel(x, v)) } }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel { if let v = value.as(Double.self) { Text(axisLabel(y, v)) } }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scatter plot of \(x.title) against \(y.title), \(points.count) days")
    }

    private func axisLabel(_ variable: InsightVariable, _ value: Double) -> String {
        switch variable {
        case .bedtime: InsightVariable.clock(minutes: value)
        case .sleepDuration: "\(Format.number(value, digits: 1))h"
        default: Format.number(value)
        }
    }
}
