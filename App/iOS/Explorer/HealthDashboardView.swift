import HealthInsights
import ReadinessCore
import SwiftUI

enum HealthRoute: Hashable {
    case rings
    case timeline
    case sleep
}

/// Everything your watch measures, grouped by category, each tile showing where you are against
/// your own recent normal.
struct HealthDashboardView: View {
    @Environment(ExplorerStore.self) private var explorer
    @Environment(ReadinessStore.self) private var readiness

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if !explorer.hasLoaded {
                    ProgressView("Loading your health data…").frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        NavigationLink(value: HealthRoute.rings) { RingsTile(rings: explorer.rings) }
                        NavigationLink(value: HealthRoute.sleep) { SleepTile(days: readiness.analysis.days) }
                    }
                    NavigationLink(value: HealthRoute.timeline) { TimelineTile() }

                    ForEach(MetricCategory.allCases) { category in
                        let metrics = explorer.availableMetrics.filter { $0.category == category }
                        if !metrics.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(category.title, systemImage: category.systemImage)
                                    .font(.title3.bold())
                                    .foregroundStyle(category.tint)
                                    .accessibilityAddTraits(.isHeader)
                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(metrics) { metric in
                                        NavigationLink(value: metric) {
                                            MetricTile(metric: metric, values: explorer.series[metric] ?? [])
                                        }
                                    }
                                }
                            }
                        }
                    }

                    let missing = HealthMetric.allCases.filter { !explorer.availableMetrics.contains($0) }
                    if !missing.isEmpty {
                        Text("No data yet for \(missing.map(\.shortTitle).formatted(.list(type: .and))). Some need a newer watch, a specific activity (e.g. outdoor runs for Cardio Fitness), or Health permission.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Health")
        .navigationDestination(for: HealthMetric.self) { MetricExplorerView(metric: $0) }
        .navigationDestination(for: HealthRoute.self) { route in
            switch route {
            case .rings: ActivityRingsView()
            case .timeline: DayTimelineView()
            case .sleep: SleepExplorerView()
            }
        }
        .navigationDestination(for: MetricKind.self) { MetricDetailView(metric: $0) }
        .refreshable { await explorer.reload() }
        .task { await explorer.loadIfNeeded() }
    }
}

/// Latest value, 30-day sparkline and how the last week compares with the weeks before.
struct MetricTile: View {
    let metric: HealthMetric
    let values: [DailyValue]

    var body: some View {
        let recent = Array(values.suffix(30))
        let latest = values.last
        let weekly = SeriesAnalytics.comparePeriods(values, days: 7, endingAt: .now, calendar: .current)
        VStack(alignment: .leading, spacing: 8) {
            Label(metric.shortTitle, systemImage: metric.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(metric.tint)
                .lineLimit(1)
            if let latest {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(latestText(latest)).font(.title2.bold().monospacedDigit()).minimumScaleFactor(0.7).lineLimit(1)
                    Text(metric.unit).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(latest.date.relativeDayName).font(.caption2).foregroundStyle(.secondary)
            }
            Sparkline(values: recent.map { Optional($0.value) }, color: metric.tint)
                .frame(height: 34)
            if let weekly, let percent = weekly.percentChange {
                Text("7-day avg \(Format.signed(percent))%")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(metric.tone(forChange: weekly.delta))
            } else {
                Text(" ").font(.caption2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens charts and statistics")
    }

    private func latestText(_ value: DailyValue) -> String {
        if metric.aggregation == .range, let low = value.min, let high = value.max {
            return "\(Format.number(low))–\(Format.number(high))"
        }
        return metric.formatted(value.value, includeUnit: false)
    }
}

private struct RingsTile: View {
    let rings: [ActivityRingDay]

    var body: some View {
        let today = rings.last
        VStack(alignment: .leading, spacing: 8) {
            Label("Activity Rings", systemImage: "circle.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.pink)
            HStack(spacing: 10) {
                ActivityRingsGlyph(day: today, lineWidth: 7).frame(width: 64, height: 64)
                if let today {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Format.number(today.move))/\(Format.number(today.moveGoal))").foregroundStyle(ActivityRingsGlyph.moveColor)
                        Text("\(Format.number(today.exercise))/\(Format.number(today.exerciseGoal)) min").foregroundStyle(ActivityRingsGlyph.exerciseColor)
                        Text("\(Format.number(today.stand))/\(Format.number(today.standGoal)) h").foregroundStyle(ActivityRingsGlyph.standColor)
                    }
                    .font(.caption.weight(.semibold).monospacedDigit())
                }
            }
            HStack(spacing: 4) {
                ForEach(rings.suffix(7)) { day in
                    ActivityRingsGlyph(day: day, lineWidth: 2.5).frame(width: 16, height: 16)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

private struct SleepTile: View {
    let days: [DayMetrics]

    var body: some View {
        let recent = days.suffix(14)
        let last = days.last?.sleep
        VStack(alignment: .leading, spacing: 8) {
            Label("Sleep", systemImage: "bed.double.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.indigo)
            if let last {
                Text(Format.duration(last.asleep)).font(.title2.bold().monospacedDigit())
                Text("\(last.start.formatted(date: .omitted, time: .shortened)) – \(last.end.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("No sleep last night").font(.subheadline).foregroundStyle(.secondary)
            }
            Sparkline(values: recent.map { $0.sleep.map { $0.asleep / 3600 } }, color: .indigo)
                .frame(height: 34)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

private struct TimelineTile: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.title2)
                .foregroundStyle(.red)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your day, hour by hour").font(.subheadline.weight(.semibold))
                Text("Heart rate with sleep, workouts and steps in context")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

/// Move, Exercise and Stand as concentric rings.
struct ActivityRingsGlyph: View {
    let day: ActivityRingDay?
    var lineWidth: CGFloat = 8

    static let moveColor = Color(red: 0.98, green: 0.07, blue: 0.31)
    static let exerciseColor = Color(red: 0.62, green: 0.98, blue: 0.0)
    static let standColor = Color(red: 0.0, green: 0.86, blue: 0.95)

    var body: some View {
        ZStack {
            ring(day?.moveProgress ?? 0, Self.moveColor, inset: 0)
            ring(day?.exerciseProgress ?? 0, Self.exerciseColor, inset: lineWidth * 1.15)
            ring(day?.standProgress ?? 0, Self.standColor, inset: lineWidth * 2.3)
        }
        .accessibilityElement()
        .accessibilityLabel("Activity rings")
        .accessibilityValue(day.map {
            "Move \(Int($0.moveProgress * 100))%, Exercise \(Int($0.exerciseProgress * 100))%, Stand \(Int($0.standProgress * 100))%"
        } ?? "No data")
    }

    private func ring(_ progress: Double, _ color: Color, inset: CGFloat) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(inset + lineWidth / 2)
    }
}
