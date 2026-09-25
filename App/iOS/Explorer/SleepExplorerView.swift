import Charts
import HealthInsights
import ReadinessCore
import SwiftUI

/// Sleep beyond "hours last night": when you sleep, how regular it is, how weekends shift it,
/// and how stages and duration trend.
struct SleepExplorerView: View {
    @Environment(ReadinessStore.self) private var readiness
    @State private var range = TrendRange.month

    var body: some View {
        let days = Array(readiness.analysis.days.suffix(range.days))
        let schedule = SleepScheduleAnalysis.analyze(days, calendar: .current)
        ScrollView {
            VStack(spacing: 16) {
                Picker("Range", selection: $range) {
                    ForEach(TrendRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                if days.allSatisfy({ $0.sleep == nil }) {
                    NoRecentSleepCard(lastNight: readiness.analysis.allDaysLastSleep)
                } else {
                    if let schedule {
                        Card(title: "Sleep schedule", systemImage: "clock") {
                            VStack(alignment: .leading, spacing: 12) {
                                SleepScheduleChart(analysis: schedule)
                                HStack(spacing: 14) {
                                    Label("Weeknights", systemImage: "square.fill").labelStyle(LegendLabelStyle(color: .indigo))
                                    Label("Weekend nights", systemImage: "square.fill").labelStyle(LegendLabelStyle(color: .purple.opacity(0.5)))
                                    Label("Median", systemImage: "line.diagonal").labelStyle(LegendLabelStyle(color: .secondary))
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                        ScheduleStatsCard(analysis: schedule)
                    }

                    TrendCard(metric: .sleepDuration, points: readiness.analysis.trend(.sleepDuration, lastDays: range.days))

                    Card(title: "Stages by night", systemImage: "chart.bar.xaxis") {
                        SleepHistoryChart(days: Array(days.suffix(min(range.days, 30))), goalHours: readiness.sleepGoalHours)
                    }

                    StageAveragesCard(days: days)

                    TrendCard(metric: .sleepScore, points: readiness.analysis.trend(.sleepScore, lastDays: range.days))
                }

                Card(title: "About sleep timing", systemImage: "book") {
                    Text("Going to bed and waking at consistent times is linked to better health, independent of how long you sleep. 'Social jetlag' is how much later your sleep shifts on weekends — like flying a time zone west every Friday and back every Monday.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Explains an empty period instead of showing blank charts.
private struct NoRecentSleepCard: View {
    let lastNight: Date?

    var body: some View {
        Card(title: "No sleep in this period", systemImage: "moon.zzz") {
            VStack(alignment: .leading, spacing: 8) {
                if let lastNight {
                    Text("Your most recent tracked night was \(lastNight.formatted(date: .long, time: .omitted)).")
                        .font(.subheadline.weight(.semibold))
                }
                Text("Sleep is the richest readiness signal: it adds overnight HRV, sleeping heart rate and overnight vitals. Turn on Sleep in the Health app (Browse › Sleep › Get Started) and wear your Apple Watch to bed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Each night as a floating bar from falling asleep to waking, evening at the top.
private struct SleepScheduleChart: View {
    let analysis: SleepScheduleAnalysis

    var body: some View {
        Chart {
            ForEach(analysis.nights) { night in
                BarMark(
                    x: .value("Night", night.day, unit: .day),
                    yStart: .value("Asleep", night.sleepStart),
                    yEnd: .value("Awake", night.wake),
                    width: .ratio(0.6)
                )
                .foregroundStyle(night.isWeekendNight ? AnyShapeStyle(Color.purple.opacity(0.5)) : AnyShapeStyle(Color.indigo.gradient))
                .clipShape(Capsule())
                .accessibilityLabel(night.day.relativeDayName)
                .accessibilityValue("\(InsightVariable.clock(minutes: night.sleepStart)) to \(InsightVariable.clock(minutes: night.wake))")
            }
            RuleMark(y: .value("Median bedtime", analysis.medianStart))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            RuleMark(y: .value("Median wake", analysis.medianWake))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartYScale(domain: .automatic(includesZero: false, reversed: true))
        .chartYAxis {
            AxisMarks(position: .leading, values: .stride(by: 120)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let minutes = value.as(Double.self) { Text(InsightVariable.clock(minutes: minutes)) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: analysis.nights.count > 10 ? 7 : 1)) { _ in
                AxisValueLabel(format: analysis.nights.count > 10 ? .dateTime.day().month(.abbreviated) : .dateTime.weekday(.narrow))
            }
        }
        .frame(height: 260)
    }
}

private struct ScheduleStatsCard: View {
    let analysis: SleepScheduleAnalysis

    var body: some View {
        Card(title: "Regularity", systemImage: "metronome") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    StatPill(title: "Typical bedtime", value: InsightVariable.clock(minutes: analysis.medianStart), note: LocalizedStringKey("±\(Format.number(analysis.startVariability)) min"))
                    StatPill(title: "Typical wake", value: InsightVariable.clock(minutes: analysis.medianWake), note: LocalizedStringKey("±\(Format.number(analysis.wakeVariability)) min"))
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(analysis.regularityLabel).font(.headline)
                    Spacer()
                    if let jetlag = analysis.socialJetlag {
                        Text(jetlagText(jetlag)).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }

    private func jetlagText(_ minutes: Double) -> String {
        if abs(minutes) < 20 { return "Weekends match weekdays" }
        return "Weekends \(Format.duration(abs(minutes) * 60)) \(minutes > 0 ? "later" : "earlier")"
    }
}

private struct StageAveragesCard: View {
    let days: [DayMetrics]

    var body: some View {
        let staged = days.compactMap(\.sleep).filter(\.hasStages)
        if !staged.isEmpty {
            let total = staged.reduce(0) { $0 + $1.asleep }
            let items: [(SleepStage, TimeInterval)] = [
                (.deep, staged.reduce(0) { $0 + $1.deep }),
                (.core, staged.reduce(0) { $0 + $1.core }),
                (.rem, staged.reduce(0) { $0 + $1.rem }),
            ]
            Card(title: "Average night", systemImage: "moon.zzz") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(items, id: \.0) { stage, duration in
                        HStack {
                            Circle().fill(stage.color).frame(width: 10, height: 10)
                            Text(stage.label).frame(width: 60, alignment: .leading)
                            GeometryReader { proxy in
                                Capsule().fill(stage.color.gradient)
                                    .frame(width: proxy.size.width * duration / total)
                            }
                            .frame(height: 10)
                            Text(Format.duration(duration / Double(staged.count)))
                                .font(.subheadline.monospacedDigit())
                                .frame(width: 64, alignment: .trailing)
                            Text("\(Format.number(duration / total * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                        .font(.subheadline)
                        .accessibilityElement(children: .combine)
                    }
                    Text("Typical adults spend roughly 10–25% of sleep in deep and 20–25% in REM. Wrist-based staging is an estimate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
