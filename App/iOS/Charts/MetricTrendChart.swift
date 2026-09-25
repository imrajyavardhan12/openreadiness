import Charts
import ReadinessCore
import SwiftUI

/// A metric over time drawn against *your own* normal range, the one thing Apple's Health charts
/// never show. Levels (HRV, heart rate…) render as a line with a shaded normal band; totals
/// (load, energy) render as bars. Drag to scrub.
struct MetricTrendChart: View {
    let metric: MetricKind
    let points: [TrendPoint]
    var height: CGFloat = 220
    var interactive = true

    @State private var selectedDay: Date?

    private var valued: [(day: Date, value: Double, normal: NormalRange?)] {
        points.compactMap { point in point.value.map { (point.day, $0, point.normalRange) } }
    }

    private var banded: [(day: Date, normal: NormalRange)] {
        points.compactMap { point in point.normalRange.map { (point.day, $0) } }
    }

    private var selected: TrendPoint? {
        guard let selectedDay else { return nil }
        let calendar = Calendar.current
        return points.first { calendar.isDate($0.day, inSameDayAs: selectedDay) }
    }

    var body: some View {
        Chart {
            ForEach(banded, id: \.day) { item in
                AreaMark(
                    x: .value("Day", item.day, unit: .day),
                    yStart: .value("Normal low", item.normal.low),
                    yEnd: .value("Normal high", item.normal.high)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(.green.opacity(0.12))
                .accessibilityHidden(true)
            }

            if metric.isCumulative {
                ForEach(valued, id: \.day) { item in
                    BarMark(x: .value("Day", item.day, unit: .day), y: .value(metric.title, item.value))
                        .foregroundStyle(barColor(for: item.day).gradient)
                        .cornerRadius(3)
                        .accessibilityLabel(item.day.relativeDayName)
                        .accessibilityValue(formatted(item.value))
                }
            } else {
                ForEach(valued, id: \.day) { item in
                    LineMark(x: .value("Day", item.day, unit: .day), y: .value(metric.title, item.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Color.accentColor.opacity(0.75))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("Day", item.day, unit: .day), y: .value(metric.title, item.value))
                        .symbolSize(points.count > 45 ? 12 : 30)
                        .foregroundStyle(pointColor(item.value, normal: item.normal))
                        .accessibilityLabel(item.day.relativeDayName)
                        .accessibilityValue(accessibilityValue(item.value, normal: item.normal))
                }
            }

            if let selected, let value = selected.value {
                RuleMark(x: .value("Selected", selected.day, unit: .day))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        SelectionCallout(day: selected.day, value: formatted(value), normal: selected.normalRange.map(formattedRange))
                    }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            if points.count > 45 {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            } else {
                AxisMarks(values: .stride(by: .day, count: xStride)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: points.count > 8 ? .dateTime.day() : .dateTime.weekday(.narrow))
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) { Text(Format.number(number, digits: metric.fractionDigits)) }
                }
            }
        }
        .chartXSelection(value: interactive ? $selectedDay : .constant(nil))
        .frame(height: height)
        .accessibilityLabel("\(metric.title) chart")
    }

    private var xStride: Int {
        switch points.count {
        case ...8: 1
        default: 7
        }
    }

    private var yDomain: ClosedRange<Double> {
        let values = valued.map(\.value) + banded.flatMap { [$0.normal.low, $0.normal.high] }
        guard var low = values.min(), var high = values.max() else { return 0...1 }
        if metric.isCumulative || metric == .readiness || metric == .sleepScore { low = 0 }
        if metric == .readiness { high = 10 }
        if metric == .sleepScore { high = max(high, 100) }
        let padding = max((high - low) * 0.12, 0.5)
        return (metric.isCumulative || low == 0 ? low : low - padding)...(high + padding)
    }

    private func pointColor(_ value: Double, normal: NormalRange?) -> Color {
        if metric == .readiness { return ReadinessCategory(score: Int(value)).color }
        guard let normal else { return .accentColor }
        return normal.contains(value) ? .accentColor : .orange
    }

    private func barColor(for day: Date) -> Color {
        guard let selectedDay else { return .accentColor }
        return Calendar.current.isDate(day, inSameDayAs: selectedDay) ? .accentColor : .accentColor.opacity(0.4)
    }

    private func formatted(_ value: Double) -> String {
        if metric == .sleepDuration { return Format.duration(value * 3600) }
        let number = Format.number(value, digits: metric.fractionDigits)
        return metric.unit.isEmpty ? number : "\(number) \(metric.unit)"
    }

    private func formattedRange(_ range: NormalRange) -> String {
        let digits = metric.fractionDigits
        return "Normal \(Format.number(range.low, digits: digits))–\(Format.number(range.high, digits: digits))"
    }

    private func accessibilityValue(_ value: Double, normal: NormalRange?) -> String {
        guard let normal else { return formatted(value) }
        let position = value < normal.low ? "below" : (value > normal.high ? "above" : "within")
        return "\(formatted(value)), \(position) your normal range"
    }
}

struct SelectionCallout: View {
    let day: Date
    let value: String
    var normal: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(day.relativeDayName).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.bold().monospacedDigit())
            if let normal {
                Text(normal).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
