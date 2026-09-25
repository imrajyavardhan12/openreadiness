import Charts
import ReadinessCore
import SwiftUI

/// A hypnogram: each stage on its own row, time across. Far easier to read than a stacked blob.
struct HypnogramChart: View {
    let sleep: SleepSummary

    private static let stageOrder: [SleepStage] = [.awake, .rem, .core, .deep, .asleepUnspecified]

    private var rows: [SleepStage] {
        let present = Set(sleep.segments.map(\.stage))
        return Self.stageOrder.filter(present.contains)
    }

    var body: some View {
        Chart(sleep.segments.filter { $0.stage != .inBed }, id: \.start) { segment in
            RectangleMark(
                xStart: .value("Start", segment.start),
                xEnd: .value("End", segment.end),
                y: .value("Stage", segment.stage.label),
                height: .ratio(0.8)
            )
            .foregroundStyle(segment.stage.color.gradient)
            .cornerRadius(2)
        }
        .chartYScale(domain: rows.map(\.label))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .frame(height: CGFloat(rows.count) * 30 + 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep stages")
        .accessibilityValue(stageSummary)
    }

    private var stageSummary: String {
        [(SleepStage.deep, sleep.deep), (.core, sleep.core), (.rem, sleep.rem), (.asleepUnspecified, sleep.unspecified)]
            .filter { $0.1 > 0 }
            .map { "\($0.0.label) \(Format.duration($0.1))" }
            .joined(separator: ", ")
    }
}

/// Totals per stage with share of the night, as a legend that doubles as the data.
struct SleepStageBreakdown: View {
    let sleep: SleepSummary

    private var items: [(stage: SleepStage, duration: TimeInterval)] {
        [(SleepStage.deep, sleep.deep), (.core, sleep.core), (.rem, sleep.rem), (.asleepUnspecified, sleep.unspecified), (.awake, sleep.awake)]
            .filter { $0.1 > 0 }
    }

    var body: some View {
        let total = items.reduce(0) { $0 + $1.duration }
        VStack(spacing: 8) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(items, id: \.stage) { item in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(item.stage.color.gradient)
                            .frame(width: max(2, (proxy.size.width - CGFloat(items.count - 1) * 2) * item.duration / total))
                    }
                }
            }
            .frame(height: 10)
            .accessibilityHidden(true)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(items, id: \.stage) { item in
                    GridRow {
                        Label {
                            Text(item.stage.label)
                        } icon: {
                            Circle().fill(item.stage.color).frame(width: 8, height: 8)
                        }
                        Text(Format.duration(item.duration)).monospacedDigit()
                        Text("\(Format.number(item.duration / total * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Stacked stage durations for recent nights, with the sleep goal as a reference line.
struct SleepHistoryChart: View {
    let days: [DayMetrics]
    let goalHours: Double

    private struct Entry: Identifiable {
        var day: Date
        var stage: SleepStage
        var hours: Double
        var id: String { "\(day.timeIntervalSince1970)-\(stage.rawValue)" }
    }

    private var entries: [Entry] {
        days.flatMap { day -> [Entry] in
            guard let sleep = day.sleep else { return [] }
            return [(SleepStage.deep, sleep.deep), (.core, sleep.core), (.rem, sleep.rem), (.asleepUnspecified, sleep.unspecified)]
                .filter { $0.1 > 0 }
                .map { Entry(day: day.day, stage: $0.0, hours: $0.1 / 3600) }
        }
    }

    var body: some View {
        Chart {
            ForEach(entries) { entry in
                BarMark(x: .value("Night", entry.day, unit: .day), y: .value("Hours", entry.hours))
                    .foregroundStyle(by: .value("Stage", entry.stage.label))
                    .cornerRadius(2)
            }
            RuleMark(y: .value("Goal", goalHours))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("Goal \(Format.number(goalHours, digits: 1))h").font(.caption2).foregroundStyle(.secondary)
                }
        }
        .chartForegroundStyleScale(
            domain: [SleepStage.deep, .core, .rem, .asleepUnspecified].map(\.label),
            range: [SleepStage.deep, .core, .rem, .asleepUnspecified].map(\.color)
        )
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: days.count > 14 ? 7 : 1)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
            }
        }
        .frame(height: 200)
    }
}
