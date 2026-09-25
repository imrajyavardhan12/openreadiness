import Charts
import HealthInsights
import ReadinessCore
import SwiftUI

/// One day, hour by hour: heart rate with sleep and workouts shaded in, plus steps.
/// Apple Health shows these on separate screens with no shared time axis.
struct DayTimelineView: View {
    @Environment(ExplorerStore.self) private var explorer
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var data: IntradayDay?
    @State private var errorMessage: String?

    private var calendar: Calendar { .current }
    private var dayEnd: Date { calendar.date(byAdding: .day, value: 1, to: day)! }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left").padding(8) }
                        .accessibilityLabel("Previous day")
                    Spacer()
                    Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.headline)
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right").padding(8) }
                        .disabled(calendar.isDateInToday(day))
                        .accessibilityLabel("Next day")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)

                if let data {
                    Card(title: "Heart rate", systemImage: "heart.fill") {
                        VStack(alignment: .leading, spacing: 10) {
                            heartSummary(data)
                            HeartTimelineChart(data: data, start: day, end: dayEnd)
                            HStack(spacing: 14) {
                                Label("Asleep", systemImage: "square.fill").labelStyle(LegendLabelStyle(color: .indigo.opacity(0.3)))
                                Label("Workout", systemImage: "square.fill").labelStyle(LegendLabelStyle(color: .orange.opacity(0.3)))
                                Label("Min–max per 5 min", systemImage: "square.fill").labelStyle(LegendLabelStyle(color: .red.opacity(0.25)))
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                    Card(title: "Steps by hour", systemImage: "shoeprints.fill") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(Format.number(data.hourlySteps.reduce(0) { $0 + $1.value })) steps")
                                .font(.title3.bold().monospacedDigit())
                            StepsByHourChart(steps: data.hourlySteps, start: day, end: dayEnd)
                        }
                    }
                    if !data.workouts.isEmpty {
                        Card(title: "Workouts", systemImage: "figure.run") {
                            ForEach(data.workouts) { workout in
                                NavigationLink(value: workout) { WorkoutRow(workout: workout) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                } else if let errorMessage {
                    ContentUnavailableView("Couldn't load this day", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: WorkoutSummary.self) { WorkoutDetailView(workout: $0) }
        .task(id: day) {
            data = nil
            errorMessage = nil
            do {
                data = try await explorer.intraday(on: day)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func shift(_ days: Int) {
        day = calendar.date(byAdding: .day, value: days, to: day)!
    }

    @ViewBuilder
    private func heartSummary(_ data: IntradayDay) -> some View {
        if let low = data.heartRate.map(\.min).min(), let high = data.heartRate.map(\.max).max(),
           let mean = Stats.mean(data.heartRate.map(\.average)) {
            HStack {
                StatPill(title: "Lowest", value: "\(Format.number(low)) bpm")
                StatPill(title: "Average", value: "\(Format.number(mean)) bpm")
                StatPill(title: "Highest", value: "\(Format.number(high)) bpm")
            }
        }
    }
}

private struct HeartTimelineChart: View {
    let data: IntradayDay
    let start: Date
    let end: Date

    var body: some View {
        let low = (data.heartRate.map(\.min).min() ?? 40) - 5
        let high = (data.heartRate.map(\.max).max() ?? 180) + 5
        Chart {
            ForEach(data.sleep.filter(\.stage.isAsleep), id: \.start) { segment in
                RectangleMark(
                    xStart: .value("Start", max(segment.start, start)),
                    xEnd: .value("End", min(segment.end, end)),
                    yStart: .value("Low", low),
                    yEnd: .value("High", high)
                )
                .foregroundStyle(.indigo.opacity(0.12))
                .accessibilityHidden(true)
            }
            ForEach(data.workouts) { workout in
                RectangleMark(
                    xStart: .value("Start", max(workout.start, start)),
                    xEnd: .value("End", min(workout.end, end)),
                    yStart: .value("Low", low),
                    yEnd: .value("High", high)
                )
                .foregroundStyle(.orange.opacity(0.18))
                .annotation(position: .top, alignment: .leading) {
                    Image(systemName: "figure.run").font(.caption2).foregroundStyle(.orange)
                }
                .accessibilityLabel(workout.activityName)
            }
            ForEach(data.heartRate) { bucket in
                AreaMark(
                    x: .value("Time", bucket.start),
                    yStart: .value("Min", bucket.min),
                    yEnd: .value("Max", bucket.max)
                )
                .foregroundStyle(.red.opacity(0.2))
                .interpolationMethod(.monotone)
                LineMark(x: .value("Time", bucket.start), y: .value("bpm", bucket.average))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
                    .interpolationMethod(.monotone)
            }
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: low...high)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .frame(height: 240)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate over the day")
        .accessibilityValue(summary)
    }

    private var summary: String {
        guard let low = data.heartRate.map(\.min).min(), let high = data.heartRate.map(\.max).max() else { return "No data" }
        return "Ranged from \(Format.number(low)) to \(Format.number(high)) beats per minute, \(data.workouts.count) workouts"
    }
}

private struct StepsByHourChart: View {
    let steps: [TimedValue]
    let start: Date
    let end: Date

    var body: some View {
        Chart(steps, id: \.date) { hour in
            BarMark(x: .value("Hour", hour.date, unit: .hour), y: .value("Steps", hour.value))
                .foregroundStyle(Color.orange.gradient)
                .cornerRadius(2)
                .accessibilityLabel(hour.date.formatted(date: .omitted, time: .shortened))
                .accessibilityValue("\(Format.number(hour.value)) steps")
        }
        .chartXScale(domain: start...end)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .frame(height: 130)
    }
}
