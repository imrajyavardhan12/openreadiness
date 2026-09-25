import Charts
import HealthInsights
import ReadinessCore
import SwiftUI

/// Training volume over time by activity, and every workout with zone analysis.
struct WorkoutsView: View {
    @Environment(ExplorerStore.self) private var explorer

    var body: some View {
        let calendar = Calendar.current
        let recent = explorer.workouts.filter {
            $0.start >= calendar.date(byAdding: .weekOfYear, value: -12, to: .now)!
        }
        let byWeek = Dictionary(grouping: explorer.workouts.prefix(60)) {
            calendar.dateInterval(of: .weekOfYear, for: $0.start)!.start
        }
        ScrollView {
            LazyVStack(spacing: 16) {
                if !explorer.hasLoaded {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 300)
                } else if explorer.workouts.isEmpty {
                    ContentUnavailableView("No workouts", systemImage: "figure.run", description: Text("Workouts you record on Apple Watch appear here."))
                } else {
                    WeekComparisonCard(workouts: explorer.workouts)
                    Card(title: "Minutes per week", systemImage: "chart.bar.fill") {
                        WeeklyVolumeChart(workouts: recent)
                    }
                    ForEach(byWeek.keys.sorted(by: >), id: \.self) { week in
                        Card(title: LocalizedStringKey(weekTitle(week)), systemImage: "calendar") {
                            VStack(spacing: 0) {
                                ForEach(byWeek[week]!.sorted { $0.start > $1.start }) { workout in
                                    NavigationLink(value: workout) { WorkoutRow(workout: workout) }
                                        .buttonStyle(.plain)
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Workouts")
        .navigationDestination(for: WorkoutSummary.self) { WorkoutDetailView(workout: $0) }
        .refreshable { await explorer.reload() }
        .task { await explorer.loadIfNeeded() }
    }

    private func weekTitle(_ start: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(start, equalTo: .now, toGranularity: .weekOfYear) { return String(localized: "This week") }
        let end = calendar.date(byAdding: .day, value: 6, to: start)!
        return (start..<end).formatted(.interval.day().month(.abbreviated))
    }
}

extension WorkoutSummary {
    var systemImage: String {
        switch activityName {
        case "Running": "figure.run"
        case "Walking": "figure.walk"
        case "Cycling": "figure.outdoor.cycle"
        case "Swimming": "figure.pool.swim"
        case "Hiking": "figure.hiking"
        case "Yoga": "figure.yoga"
        case "Strength Training", "Functional Strength Training": "figure.strengthtraining.functional"
        case "HIIT": "figure.highintensity.intervaltraining"
        case "Rowing": "figure.rower"
        default: "figure.mixed.cardio"
        }
    }

    /// Distance in km, pace-friendly.
    var distanceText: String? {
        distanceMeters.map { "\(Format.number($0 / 1000, digits: 2)) km" }
    }

    /// Minutes per km for foot-based activities.
    var paceText: String? {
        guard let meters = distanceMeters, meters > 0, ["Running", "Walking", "Hiking"].contains(activityName) else { return nil }
        let secondsPerKm = duration / (meters / 1000)
        return "\(Int(secondsPerKm) / 60)'\(String(format: "%02d", Int(secondsPerKm) % 60))\" /km"
    }
}

struct WorkoutRow: View {
    let workout: WorkoutSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.systemImage)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 36, height: 36)
                .background(.orange.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.activityName).font(.subheadline.weight(.semibold))
                Text([workout.start.relativeDayName, Format.duration(workout.duration), workout.distanceText].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let hr = workout.averageHeartRate {
                Label("\(Format.number(hr))", systemImage: "heart.fill")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.red)
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct WeekComparisonCard: View {
    let workouts: [WorkoutSummary]

    var body: some View {
        let calendar = Calendar.current
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now)!
        let lastWeek = DateInterval(start: calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek.start)!, end: thisWeek.start)
        let current = workouts.filter { thisWeek.contains($0.start) }
        let previous = workouts.filter { lastWeek.contains($0.start) }
        Card(title: "This week vs last week", systemImage: "calendar.badge.clock") {
            HStack {
                StatPill(title: "Workouts", value: "\(current.count)", note: LocalizedStringKey("Last week \(previous.count)"))
                StatPill(
                    title: "Time",
                    value: Format.duration(current.reduce(0) { $0 + $1.duration }),
                    note: LocalizedStringKey("Last week \(Format.duration(previous.reduce(0) { $0 + $1.duration }))")
                )
                StatPill(
                    title: "Energy",
                    value: "\(Format.number(current.compactMap(\.activeEnergyKcal).reduce(0, +))) kcal",
                    note: LocalizedStringKey("Last week \(Format.number(previous.compactMap(\.activeEnergyKcal).reduce(0, +)))")
                )
            }
        }
    }
}

private struct WeeklyVolumeChart: View {
    let workouts: [WorkoutSummary]

    var body: some View {
        let calendar = Calendar.current
        Chart(workouts) { workout in
            BarMark(
                x: .value("Week", calendar.dateInterval(of: .weekOfYear, for: workout.start)!.start, unit: .weekOfYear),
                y: .value("Minutes", workout.duration / 60)
            )
            .foregroundStyle(by: .value("Activity", workout.activityName))
            .cornerRadius(2)
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .frame(height: 220)
    }
}

/// One workout: heart rate over time on zone bands, and time in each zone.
struct WorkoutDetailView: View {
    let workout: WorkoutSummary

    @Environment(ExplorerStore.self) private var explorer
    @Environment(ReadinessStore.self) private var readiness
    @State private var samples: [TimedValue]?

    private static let zoneColors: [Color] = [.blue, .green, .yellow, .orange, .red]

    var body: some View {
        let zones = explorer.heartRateZones
        ScrollView {
            VStack(spacing: 16) {
                Card(title: LocalizedStringKey(workout.activityName), systemImage: workout.systemImage) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(workout.start.formatted(date: .complete, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            StatPill(title: "Duration", value: Format.duration(workout.duration))
                            if let kcal = workout.activeEnergyKcal { StatPill(title: "Active energy", value: "\(Format.number(kcal)) kcal") }
                            if let distance = workout.distanceText { StatPill(title: "Distance", value: distance) }
                            if let pace = workout.paceText { StatPill(title: "Avg pace", value: pace) }
                            if let hr = workout.averageHeartRate { StatPill(title: "Avg HR", value: "\(Format.number(hr)) bpm") }
                            if let max = workout.maxHeartRate { StatPill(title: "Max HR", value: "\(Format.number(max)) bpm") }
                            if let load = trainingLoad { StatPill(title: "Training load", value: Format.number(load.load), note: LocalizedStringKey("Effort \(Format.number(load.effort, digits: 1))")) }
                        }
                    }
                }

                if let samples {
                    if samples.isEmpty {
                        Card(title: "Heart rate", systemImage: "heart.fill") {
                            Text("No heart-rate samples for this workout.").foregroundStyle(.secondary)
                        }
                    } else {
                        Card(title: "Heart rate", systemImage: "heart.fill") {
                            WorkoutHeartRateChart(samples: samples, zones: zones, colors: Self.zoneColors, start: workout.start)
                        }
                        Card(title: "Time in zones", systemImage: "chart.bar.doc.horizontal") {
                            ZoneBreakdown(times: zones.timeInZones(samples, until: workout.end), zones: zones, colors: Self.zoneColors)
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(workout.activityName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            samples = (try? await explorer.heartRate(for: workout)) ?? []
        }
    }

    /// The same workout as scored by the readiness engine, if present.
    private var trainingLoad: ScoredWorkout? {
        readiness.analysis.metrics(for: workout.start)?.workouts.first { abs($0.workout.start.timeIntervalSince(workout.start)) < 60 }
    }
}

private struct WorkoutHeartRateChart: View {
    let samples: [TimedValue]
    let zones: HeartRateZones
    let colors: [Color]
    let start: Date

    var body: some View {
        let bounds = zones.lowerBounds
        let low = min(samples.map(\.value).min() ?? 80, bounds[0]) - 5
        let high = max(samples.map(\.value).max() ?? 180, bounds[4] + 5)
        Chart {
            ForEach(0..<5, id: \.self) { index in
                RectangleMark(
                    yStart: .value("From", index == 0 ? low : bounds[index]),
                    yEnd: .value("To", index == 4 ? high : bounds[index + 1])
                )
                .foregroundStyle(colors[index].opacity(0.1))
                .accessibilityHidden(true)
            }
            ForEach(samples, id: \.date) { sample in
                LineMark(x: .value("Minutes", sample.date.timeIntervalSince(start) / 60), y: .value("bpm", sample.value))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartYScale(domain: low...high)
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel { if let minutes = value.as(Double.self) { Text("\(Int(minutes))′") } }
            }
        }
        .frame(height: 220)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate during workout")
        .accessibilityValue("From \(Format.number(samples.map(\.value).min() ?? 0)) to \(Format.number(samples.map(\.value).max() ?? 0)) beats per minute")
    }
}

private struct ZoneBreakdown: View {
    let times: [TimeInterval]
    let zones: HeartRateZones
    let colors: [Color]

    var body: some View {
        let total = max(times.reduce(0, +), 1)
        let bounds = zones.lowerBounds
        VStack(alignment: .leading, spacing: 10) {
            ForEach((0..<5).reversed(), id: \.self) { index in
                HStack(spacing: 8) {
                    Text("Z\(index + 1)").font(.caption.bold()).foregroundStyle(colors[index]).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(HeartRateZones.names[index]) · \(index == 0 ? "<" : "")\(Format.number(index == 0 ? bounds[1] : bounds[index]))\(index == 0 ? "" : "+") bpm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        GeometryReader { proxy in
                            Capsule().fill(colors[index].gradient)
                                .frame(width: max(4, proxy.size.width * times[index] / total))
                        }
                        .frame(height: 8)
                    }
                    Text(Format.duration(times[index])).font(.subheadline.monospacedDigit()).frame(width: 60, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
            Text("Zones use your heart-rate reserve (resting \(Format.number(zones.resting)) bpm, estimated max \(Format.number(zones.maximum)) bpm).")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
