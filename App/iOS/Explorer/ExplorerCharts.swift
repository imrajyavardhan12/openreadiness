import Accessibility
import Charts
import HealthInsights
import ReadinessCore
import SwiftUI

/// The main chart for any metric: bars for totals, floating range bars for heart rate, lines for
/// levels — always with your personal normal band, a 7-day average and general reference ranges.
struct MetricExplorerChart: View {
    let metric: HealthMetric
    let values: [DailyValue]
    let band: [BandPoint]
    let rolling: [TimedValue]
    let bucket: Calendar.Component

    /// Owned here so scrubbing re-renders only the chart, not the page's derived statistics.
    @State private var selection: Date?

    private var selected: DailyValue? {
        guard let selection else { return nil }
        let calendar = Calendar.current
        return values.min { abs($0.date.timeIntervalSince(selection)) < abs($1.date.timeIntervalSince(selection)) }
            .flatMap { calendar.isDate($0.date, equalTo: selection, toGranularity: bucket) ? $0 : nil }
    }

    var body: some View {
        let domain = yDomain
        Chart {
            ForEach(metric.referenceBands) { reference in
                let lower = max(reference.lower, domain.lowerBound)
                let upper = min(reference.upper, domain.upperBound)
                if upper > lower {
                    RectangleMark(yStart: .value("Low", lower), yEnd: .value("High", upper))
                        .foregroundStyle(reference.tone.color.opacity(0.07))
                        .accessibilityHidden(true)
                }
            }

            ForEach(band) { point in
                AreaMark(
                    x: .value("Date", point.date, unit: bucket),
                    yStart: .value("Normal low", point.low),
                    yEnd: .value("Normal high", point.high),
                    series: .value("Series", "normal")
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(.green.opacity(0.14))
                .accessibilityHidden(true)
            }

            ForEach(values) { item in
                switch metric.aggregation {
                case .sum:
                    BarMark(x: .value("Date", item.date, unit: bucket), y: .value(metric.title, item.value))
                        .foregroundStyle(barStyle(item))
                        .cornerRadius(3)
                case .range:
                    if let low = item.min, let high = item.max {
                        BarMark(
                            x: .value("Date", item.date, unit: bucket),
                            yStart: .value("Min", low),
                            yEnd: .value("Max", high),
                            width: .ratio(0.45)
                        )
                        .foregroundStyle(barStyle(item))
                        .clipShape(Capsule())
                    }
                    PointMark(x: .value("Date", item.date, unit: bucket), y: .value("Average", item.value))
                        .symbolSize(values.count > 40 ? 8 : 18)
                        .foregroundStyle(Color.primary)
                case .average:
                    if !metric.isSparse {
                        LineMark(x: .value("Date", item.date, unit: bucket), y: .value(metric.title, item.value), series: .value("Series", "value"))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(metric.tint.opacity(0.55))
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                    PointMark(x: .value("Date", item.date, unit: bucket), y: .value(metric.title, item.value))
                        .symbolSize(values.count > 60 ? 10 : 24)
                        .foregroundStyle(metric.tint)
                }
            }

            ForEach(rolling, id: \.date) { point in
                LineMark(x: .value("Date", point.date, unit: .day), y: .value("7-day average", point.value), series: .value("Series", "rolling"))
                    .interpolationMethod(.monotone)
                    // Color.primary, not .primary: inside Charts the latter resolves to the accent colour.
                    .foregroundStyle(Color.primary.opacity(0.65))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
            }

            if let goal = metric.referenceGoal, metric.aggregation == .sum {
                RuleMark(y: .value("Goal", goal.value))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Target \(metric.formatted(goal.value, includeUnit: false))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }

            if let selected {
                RuleMark(x: .value("Selected", selected.date, unit: bucket))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        SelectionCallout(day: selected.date, value: calloutValue(selected), normal: calloutNote(selected))
                    }
            }
        }
        .chartYScale(domain: domain)
        .chartXAxis { xAxis }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) { Text(Format.number(number, digits: metric.fractionDigits)) }
                }
            }
        }
        .chartXSelection(value: $selection)
        .onChange(of: bucket) { selection = nil }
        .frame(height: 260)
        .accessibilityChartDescriptor(MetricChartDescriptor(metric: metric, values: values))
    }

    @AxisContentBuilder
    private var xAxis: some AxisContent {
        switch bucket {
        case .month:
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
            }
        case .weekOfYear:
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        default:
            if values.count <= 8 {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            } else {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
        }
    }

    private func barStyle(_ item: DailyValue) -> AnyShapeStyle {
        guard let selected else { return AnyShapeStyle(metric.tint.gradient) }
        return selected.date == item.date ? AnyShapeStyle(metric.tint.gradient) : AnyShapeStyle(metric.tint.opacity(0.35))
    }

    private var yDomain: ClosedRange<Double> {
        var all = values.flatMap { [$0.value, $0.min, $0.max].compactMap { $0 } }
        all += band.flatMap { [$0.low, $0.high] }
        if metric.aggregation == .sum, let goal = metric.referenceGoal { all.append(goal.value) }
        guard var low = all.min(), var high = all.max() else { return 0...1 }
        if metric.aggregation == .sum { low = 0 }
        let padding = max((high - low) * 0.1, pow(10, -Double(metric.fractionDigits)))
        if metric.aggregation != .sum { low -= padding }
        high += padding
        return low...high
    }

    private func calloutValue(_ item: DailyValue) -> String {
        if let low = item.min, let high = item.max, metric.aggregation == .range {
            return "\(Format.number(low))–\(Format.number(high)) \(metric.unit)"
        }
        return metric.formatted(item.value)
    }

    private func calloutNote(_ item: DailyValue) -> String? {
        if metric.aggregation == .range { return "Average \(metric.formatted(item.value))" }
        if bucket != .day { return metric.aggregation == .sum ? "Daily average" : "Average" }
        if let point = band.first(where: { $0.date == item.date }) {
            return "Normal \(Format.number(point.low, digits: metric.fractionDigits))–\(Format.number(point.high, digits: metric.fractionDigits))"
        }
        return nil
    }
}

/// Audio Graphs / data-table description for VoiceOver. A plain value type (not the View) so the
/// nonisolated protocol requirement doesn't cross into main-actor code.
private struct MetricChartDescriptor: AXChartDescriptorRepresentable {
    let metric: HealthMetric
    let values: [DailyValue]

    func makeChartDescriptor() -> AXChartDescriptor {
        let dates = values.map(\.date.timeIntervalSince1970)
        let xAxis = AXNumericDataAxisDescriptor(
            title: "Date",
            range: (dates.min() ?? 0)...(dates.max() ?? 1),
            gridlinePositions: []
        ) { Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .omitted) }
        let ys = values.map(\.value)
        let yAxis = AXNumericDataAxisDescriptor(
            title: metric.title,
            range: (ys.min() ?? 0)...(ys.max() ?? 1),
            gridlinePositions: []
        ) { metric.formatted($0) }
        let series = AXDataSeriesDescriptor(
            name: metric.title,
            isContinuous: metric.aggregation == .average && !metric.isSparse,
            dataPoints: values.map { AXDataPoint(x: $0.date.timeIntervalSince1970, y: $0.value) }
        )
        return AXChartDescriptor(
            title: metric.title,
            summary: "\(values.count) values. Average \(metric.formatted(Stats.mean(ys) ?? 0)).",
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}

/// Mean by weekday: reveals routines ("Mondays are my low-step day").
struct WeekdayPatternChart: View {
    let metric: HealthMetric
    let stats: [WeekdayStat]

    private var best: WeekdayStat? {
        metric.higherIsBetter == false ? stats.min { $0.mean < $1.mean } : stats.max { $0.mean < $1.mean }
    }

    var body: some View {
        let symbols = Calendar.current.shortWeekdaySymbols
        Chart(stats) { stat in
            BarMark(x: .value("Day", symbols[stat.weekday - 1]), y: .value(metric.title, stat.mean))
                .foregroundStyle(stat.weekday == best?.weekday ? AnyShapeStyle(metric.tint.gradient) : AnyShapeStyle(metric.tint.opacity(0.35)))
                .cornerRadius(4)
                .annotation(position: .top) {
                    Text(Format.number(stat.mean, digits: metric.fractionDigits))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(Calendar.current.weekdaySymbols[stat.weekday - 1])
                .accessibilityValue(metric.formatted(stat.mean))
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: metric.aggregation == .sum))
        .frame(height: 150)
    }
}

/// How your days are distributed, with the latest day marked.
struct HistogramChart: View {
    let metric: HealthMetric
    let bins: [HistogramBin]
    let latest: Double?
    let mean: Double?

    var body: some View {
        Chart {
            ForEach(bins) { bin in
                binMark(bin)
            }
            if let mean {
                RuleMark(x: .value("Average", mean))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center) {
                        Text("avg").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            if let latest {
                RuleMark(x: .value("Latest", latest))
                    .foregroundStyle(metric.tint)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .annotation(position: .top, alignment: .center) {
                        Text("latest").font(.caption2.bold()).foregroundStyle(metric.tint)
                    }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let number = value.as(Double.self) { Text(Format.number(number, digits: metric.fractionDigits)) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .frame(height: 160)
    }

    @ChartContentBuilder
    private func binMark(_ bin: HistogramBin) -> some ChartContent {
        let lower: Double = bin.lower
        let upper: Double = bin.upper
        let count: Int = bin.count
        // BarMark has no four-edge initialiser; a histogram bin is a rectangle from 0 to its count.
        RectangleMark(
            xStart: .value("From", lower),
            xEnd: .value("To", upper),
            yStart: .value("Zero", 0),
            yEnd: .value("Days", count)
        )
        .foregroundStyle(metric.tint.opacity(0.5))
        .accessibilityLabel(binLabel(bin))
        .accessibilityValue("\(count) days")
    }

    private func binLabel(_ bin: HistogramBin) -> String {
        let digits = metric.fractionDigits
        return "\(Format.number(bin.lower, digits: digits)) to \(Format.number(bin.upper, digits: digits))"
    }
}

/// A year of days as a GitHub-style grid. Drawn with Canvas: 365 cells without 365 views.
struct YearHeatmap: View {
    let metric: HealthMetric
    let values: [DailyValue]

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let byDay = Dictionary(values.map { (calendar.startOfDay(for: $0.date), $0.value) }, uniquingKeysWith: { a, _ in a })
        let sorted = values.map(\.value).sorted()
        let thresholds = [0.2, 0.4, 0.6, 0.8].map { sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * $0))] }
        // Align columns to weeks, ending with the current week.
        let weekdayOffset = (calendar.component(.weekday, from: today) - calendar.firstWeekday + 7) % 7
        let columns = 53
        let gridStart = calendar.date(byAdding: .day, value: -(columns - 1) * 7 - weekdayOffset, to: today)!

        VStack(alignment: .leading, spacing: 6) {
            Canvas { context, size in
                let spacing: CGFloat = 1.5
                let cell = min((size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns), (size.height - spacing * 6) / 7)
                for column in 0..<columns {
                    for row in 0..<7 {
                        guard let day = calendar.date(byAdding: .day, value: column * 7 + row, to: gridStart), day <= today else { continue }
                        let rect = CGRect(x: CGFloat(column) * (cell + spacing), y: CGFloat(row) * (cell + spacing), width: cell, height: cell)
                        let path = Path(roundedRect: rect, cornerRadius: cell * 0.25)
                        if let value = byDay[day] {
                            let level = thresholds.filter { value >= $0 }.count
                            context.fill(path, with: .color(metric.tint.opacity(0.2 + 0.2 * Double(level))))
                        } else {
                            context.fill(path, with: .color(.gray.opacity(0.12)))
                        }
                    }
                }
            }
            .aspectRatio(CGFloat(columns) / 7, contentMode: .fit)
            .accessibilityElement()
            .accessibilityLabel("\(metric.title), last 12 months")
            .accessibilityValue("\(values.count) days recorded")

            HStack(spacing: 4) {
                Text("Less").font(.caption2).foregroundStyle(.secondary)
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(metric.tint.opacity(0.2 + 0.2 * Double(level)))
                        .frame(width: 10, height: 10)
                }
                Text("More").font(.caption2).foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
        }
    }
}
