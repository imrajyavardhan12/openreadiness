import HealthInsights
import ReadinessCore
import SwiftUI

/// Everything about one metric: the chart, how this period compares, your records, weekly rhythm,
/// distribution and a year at a glance.
struct MetricExplorerView: View {
    let metric: HealthMetric

    @Environment(ExplorerStore.self) private var explorer
    @State private var range = ExplorerRange.month

    private var calendar: Calendar { .current }
    private var all: [DailyValue] { explorer.series[metric] ?? [] }
    private var daily: [DailyValue] { explorer.values(metric, lastDays: range.days) }

    var body: some View {
        let visible = daily
        let bucketed = SeriesAnalytics.bucketed(visible, by: range.bucket, aggregation: metric.aggregation, calendar: calendar)
        ScrollView {
            VStack(spacing: 16) {
                Picker("Range", selection: $range) {
                    ForEach(ExplorerRange.allCases) { Text($0.shortTitle).tag($0) }
                }
                .pickerStyle(.segmented)

                Card(title: LocalizedStringKey(metric.title), systemImage: metric.systemImage) {
                    VStack(alignment: .leading, spacing: 12) {
                        SummaryHeader(metric: metric, values: visible, range: range)
                        if visible.isEmpty {
                            Text("No data in this period.").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 120)
                        } else {
                            MetricExplorerChart(
                                metric: metric,
                                values: bucketed,
                                band: normalBand(for: visible),
                                rolling: rolling(for: visible),
                                bucket: range.bucket
                            )
                            ChartLegend(metric: metric, showsBand: showsBand, showsRolling: showsRolling)
                        }
                    }
                }

                if let comparison = SeriesAnalytics.comparePeriods(all, days: range.days, endingAt: .now, calendar: calendar) {
                    ComparisonCard(metric: metric, comparison: comparison, range: range)
                }

                if let records = SeriesAnalytics.records(visible) {
                    HighlightsCard(metric: metric, records: records, all: all)
                }

                if !metric.isSparse, range != .week {
                    let profile = SeriesAnalytics.weekdayProfile(visible, calendar: calendar)
                    if profile.count == 7 {
                        Card(title: "Day of the week", systemImage: "calendar.day.timeline.left") {
                            WeekdayPatternChart(metric: metric, stats: profile)
                        }
                    }
                }

                if visible.count >= 14 {
                    Card(title: "Distribution", systemImage: "chart.bar.xaxis") {
                        VStack(alignment: .leading, spacing: 8) {
                            HistogramChart(
                                metric: metric,
                                bins: SeriesAnalytics.histogram(visible.map(\.value)),
                                latest: visible.last?.value,
                                mean: Stats.mean(visible.map(\.value))
                            )
                            Text("How your days in this period spread out. Most people's values cluster; the latest day is marked.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !metric.isSparse, all.count > 60 {
                    Card(title: "Last 12 months", systemImage: "square.grid.3x3.fill") {
                        YearHeatmap(metric: metric, values: all)
                    }
                }

                AboutMetricCard(metric: metric)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(metric.shortTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var showsBand: Bool { metric.aggregation == .average && range.bucket == .day && !metric.isSparse }
    private var showsRolling: Bool { range.bucket == .day && range != .week && !metric.isSparse }

    private func normalBand(for visible: [DailyValue]) -> [BandPoint] {
        guard showsBand, let first = visible.first?.date else { return [] }
        return SeriesAnalytics.normalBand(all, calendar: calendar).filter { $0.date >= first }
    }

    private func rolling(for visible: [DailyValue]) -> [TimedValue] {
        guard showsRolling, let first = visible.first?.date else { return [] }
        return SeriesAnalytics.rollingMean(all, window: 7, calendar: calendar).filter { $0.date >= first }
    }
}

private struct SummaryHeader: View {
    let metric: HealthMetric
    let values: [DailyValue]
    let range: ExplorerRange

    var body: some View {
        let label: LocalizedStringKey = switch metric.aggregation {
        case .sum: "Daily average"
        case .range: "Range"
        case .average: "Average"
        }
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if metric.aggregation == .range,
                   let low = values.compactMap(\.min).min(), let high = values.compactMap(\.max).max() {
                    Text("\(Format.number(low))–\(Format.number(high))").font(.largeTitle.bold().monospacedDigit())
                } else if let mean = Stats.mean(values.map(\.value)) {
                    Text(metric.formatted(mean, includeUnit: false)).font(.largeTitle.bold().monospacedDigit())
                } else {
                    Text("–").font(.largeTitle.bold())
                }
                Text(metric.unit).font(.headline).foregroundStyle(.secondary)
            }
            Text(range.dateSpan()).font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ChartLegend: View {
    let metric: HealthMetric
    let showsBand: Bool
    let showsRolling: Bool

    var body: some View {
        ViewThatFits {
            HStack(spacing: 14) { items }
            VStack(alignment: .leading, spacing: 4) { items }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var items: some View {
        if showsBand {
            Label("Your normal range", systemImage: "square.fill")
                .labelStyle(LegendLabelStyle(color: .green.opacity(0.3)))
        }
        if showsRolling {
            Label("7-day average", systemImage: "line.diagonal")
                .labelStyle(LegendLabelStyle(color: Color.primary.opacity(0.6)))
        }
        ForEach(metric.referenceBands) { band in
            Label(band.label, systemImage: "square.fill")
                .labelStyle(LegendLabelStyle(color: band.tone.color.opacity(0.25)))
        }
    }
}

private struct ComparisonCard: View {
    let metric: HealthMetric
    let comparison: PeriodComparison
    let range: ExplorerRange

    var body: some View {
        Card(title: "Compared with the previous \(range.periodNoun)", systemImage: "arrow.left.arrow.right") {
            HStack(alignment: .bottom, spacing: 16) {
                column("This \(range.periodNoun)", comparison.current, emphasised: true)
                column("Previous", comparison.previous, emphasised: false)
                Spacer()
                if let percent = comparison.percentChange {
                    VStack(alignment: .trailing, spacing: 2) {
                        Image(systemName: comparison.delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text("\(Format.signed(percent))%").font(.headline.monospacedDigit())
                    }
                    .foregroundStyle(metric.tone(forChange: comparison.delta))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Change \(Format.signed(percent)) percent")
                }
            }
        }
    }

    private func column(_ title: LocalizedStringKey, _ value: Double, emphasised: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(metric.formatted(value))
                .font(emphasised ? .title3.bold().monospacedDigit() : .title3.monospacedDigit())
                .foregroundStyle(emphasised ? .primary : .secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HighlightsCard: View {
    let metric: HealthMetric
    let records: Records
    let all: [DailyValue]

    var body: some View {
        let calendar = Calendar.current
        let goal = metric.referenceGoal
        let streaks = goal.map { goal in
            SeriesAnalytics.streaks(all, today: .now, calendar: calendar) { $0 >= goal.value }
        }
        Card(title: "Highlights", systemImage: "star") {
            VStack(spacing: 10) {
                HStack {
                    StatPill(title: "Highest", value: metric.formatted(records.highest.value), note: LocalizedStringKey(records.highest.date.formatted(.dateTime.day().month(.abbreviated))))
                    StatPill(title: "Lowest", value: metric.formatted(records.lowest.value), note: LocalizedStringKey(records.lowest.date.formatted(.dateTime.day().month(.abbreviated))))
                }
                if let goal, let streaks {
                    HStack {
                        StatPill(title: "Current streak", value: "\(streaks.current?.length ?? 0) days", note: LocalizedStringKey("≥ \(metric.formatted(goal.value))"))
                        StatPill(title: "Longest streak", value: "\(streaks.longest?.length ?? 0) days", note: "Last 14 months")
                    }
                }
            }
        }
    }
}

struct AboutMetricCard: View {
    let metric: HealthMetric

    var body: some View {
        Card(title: "About \(metric.shortTitle)", systemImage: "book") {
            VStack(alignment: .leading, spacing: 10) {
                Text(metric.explanation).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                if let goal = metric.referenceGoal {
                    Text(goal.note).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(metric.referenceBands) { band in
                    Label {
                        Text("\(band.label): \(Format.number(band.lower))–\(Format.number(band.upper)) \(metric.unit)")
                    } icon: {
                        Circle().fill(band.tone.color).frame(width: 8, height: 8)
                    }
                    .font(.footnote)
                }
            }
        }
    }
}
