import Charts
import ReadinessCore
import SwiftUI

/// Daily load as bars, with the 7-day (acute) and prior-3-week (chronic) averages as lines.
/// Where the acute line runs well above the chronic line, you're ramping up fast.
struct TrainingLoadChart: View {
    let points: [LoadPoint]

    @State private var selectedDay: Date?

    private var selected: LoadPoint? {
        guard let selectedDay else { return nil }
        return points.first { Calendar.current.isDate($0.day, inSameDayAs: selectedDay) }
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                BarMark(x: .value("Day", point.day, unit: .day), y: .value("Load", point.load))
                    .foregroundStyle(.gray.opacity(0.35))
                    .cornerRadius(2)
                LineMark(x: .value("Day", point.day, unit: .day), y: .value("Load", point.acute), series: .value("Series", "7-day"))
                    .foregroundStyle(by: .value("Series", "Last 7 days"))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                if let chronic = point.chronic {
                    LineMark(x: .value("Day", point.day, unit: .day), y: .value("Load", chronic), series: .value("Series", "chronic"))
                        .foregroundStyle(by: .value("Series", "Usual"))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                }
            }
            if let selected {
                RuleMark(x: .value("Selected", selected.day, unit: .day))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        SelectionCallout(
                            day: selected.day,
                            value: "\(Format.number(selected.load)) load",
                            normal: selected.ratio.map { "7-day ratio \(Format.number($0, digits: 2))×" }
                        )
                    }
            }
        }
        .chartForegroundStyleScale(["Last 7 days": Color.orange, "Usual": Color.blue])
        .chartLegend(position: .bottom, alignment: .leading)
        .chartXSelection(value: $selectedDay)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .frame(height: 220)
        .accessibilityLabel("Training load chart")
    }
}

/// Readiness per day as bars coloured by category, with faint category bands behind.
struct ScoreHistoryChart: View {
    let scores: [ReadinessScore]
    var height: CGFloat = 160

    @State private var selectedDay: Date?

    private var selected: ReadinessScore? {
        guard let selectedDay else { return nil }
        return scores.first { Calendar.current.isDate($0.day, inSameDayAs: selectedDay) }
    }

    var body: some View {
        Chart {
            ForEach(ReadinessCategory.allCases, id: \.self) { category in
                RectangleMark(
                    yStart: .value("Low", Double(category.scoreRange.lowerBound) - 0.5),
                    yEnd: .value("High", Double(category.scoreRange.upperBound) + 0.5)
                )
                .foregroundStyle(category.color.opacity(0.06))
                .accessibilityHidden(true)
            }
            ForEach(scores) { score in
                BarMark(x: .value("Day", score.day, unit: .day), y: .value("Score", max(score.score, 0)))
                    .foregroundStyle(score.category.color.gradient)
                    .opacity(selected == nil || selected?.day == score.day ? 1 : 0.4)
                    .cornerRadius(3)
                    .accessibilityLabel(score.day.relativeDayName)
                    .accessibilityValue("\(score.score), \(score.category.title)")
            }
            if let selected {
                RuleMark(x: .value("Selected", selected.day, unit: .day))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        SelectionCallout(day: selected.day, value: "\(selected.score) · \(selected.category.title)")
                    }
            }
        }
        .chartYScale(domain: 0...10.5)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 2, 5, 8, 10])
        }
        .chartXAxis {
            if scores.count > 45 {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            } else if scores.count > 14 {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            } else {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
        }
        .chartXSelection(value: $selectedDay)
        .frame(height: height)
    }
}

/// A compact line for list rows.
struct Sparkline: View {
    let values: [Double?]
    var color: Color = .accentColor

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                if let value {
                    LineMark(x: .value("i", index), y: .value("v", value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(color)
                }
            }
            if let lastIndex = values.lastIndex(where: { $0 != nil }), let last = values[lastIndex] {
                PointMark(x: .value("i", lastIndex), y: .value("v", last))
                    .symbolSize(20)
                    .foregroundStyle(color)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityHidden(true)
    }
}
