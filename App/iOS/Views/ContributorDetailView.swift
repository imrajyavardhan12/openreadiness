import ReadinessCore
import SwiftUI

/// Everything behind one contributor: its score, weight, exact inputs, and history.
struct ContributorDetailView: View {
    let kind: ContributorKind
    let day: Date

    @Environment(ReadinessStore.self) private var store
    @State private var range = TrendRange.month

    private var score: ReadinessScore? { store.analysis.scores[Calendar.current.startOfDay(for: day)] }
    private var contributor: Contributor? { score?.contributor(kind) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let contributor {
                    header(contributor)
                    Card(title: "How it's calculated", systemImage: "function") {
                        VStack(spacing: 0) {
                            ForEach(contributor.components) { component in
                                ComponentRow(component: component)
                                if component.id != contributor.components.last?.id { Divider() }
                            }
                        }
                    }
                } else {
                    Card(title: "No data", systemImage: "questionmark.circle") {
                        Text("There wasn't enough \(kind.title.lowercased()) data to score this day. Its weight was shared among the other contributors.")
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("Range", selection: $range) {
                    ForEach(TrendRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                charts

                Card(title: "About this measure", systemImage: "book") {
                    Text(kind.explanation)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ contributor: Contributor) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(Format.number(contributor.subscore))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(contributor.status.color)
                Text("/ 100").font(.title3).foregroundStyle(.secondary)
                Spacer()
                Text(contributor.status.label)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(contributor.status.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(contributor.status.color)
            }
            .accessibilityElement(children: .combine)
            SubscoreBar(subscore: contributor.subscore, status: contributor.status, height: 10)
            Text(contributor.headline).font(.headline)

            HStack {
                StatPill(title: "Weight", value: "\(Format.number(contributor.effectiveWeight * 100))%")
                StatPill(
                    title: "Effect on score",
                    value: "\(Format.signed(contributor.impact, digits: 1)) pts",
                    note: "vs. a neutral 7"
                )
                if score?.limitingFactor == kind {
                    StatPill(title: "Limiting", value: "Capped", tint: .red)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private var charts: some View {
        let analysis = store.analysis
        let days = range.days
        switch kind {
        case .hrv:
            TrendCard(metric: .hrv, points: analysis.trend(.hrv, lastDays: days))
        case .restingHeartRate:
            TrendCard(metric: .restingHeartRate, points: analysis.trend(.restingHeartRate, lastDays: days))
        case .sleep:
            Card(title: "Sleep stages by night", systemImage: "chart.bar.xaxis") {
                SleepHistoryChart(days: Array(analysis.days.suffix(min(days, 30))), goalHours: store.sleepGoalHours)
            }
            TrendCard(metric: .sleepScore, points: analysis.trend(.sleepScore, lastDays: days))
        case .trainingLoad:
            Card(title: "Training load", systemImage: "chart.bar") {
                TrainingLoadChart(points: analysis.loadTrend(lastDays: max(days, 28)))
            }
            WorkoutList(days: Array(analysis.days.suffix(7)))
        case .vitals:
            TrendCard(metric: .respiratoryRate, points: analysis.trend(.respiratoryRate, lastDays: days))
            TrendCard(metric: .wristTemperature, points: analysis.trend(.wristTemperature, lastDays: days))
            TrendCard(metric: .oxygenSaturation, points: analysis.trend(.oxygenSaturation, lastDays: days))
        }
    }
}

enum TrendRange: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30
    case quarter = 90

    var id: Int { rawValue }
    var days: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .week: "7 days"
        case .month: "30 days"
        case .quarter: "90 days"
        }
    }
}

private struct ComponentRow: View {
    let component: ScoreComponent

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(component.label).font(.subheadline)
                if let note = component.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Text(component.value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

struct StatPill: View {
    let title: LocalizedStringKey
    let value: String
    var note: LocalizedStringKey?
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(tint)
            if let note { Text(note).font(.caption2).foregroundStyle(.tertiary) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

/// A metric chart with the latest value and where it sits against your normal.
struct TrendCard: View {
    let metric: MetricKind
    let points: [TrendPoint]

    var body: some View {
        let latest = points.last { $0.value != nil }
        Card(title: LocalizedStringKey(metric.title), systemImage: metric.systemImage) {
            VStack(alignment: .leading, spacing: 12) {
                if let latest, let value = latest.value {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(display(value)).font(.title2.bold().monospacedDigit())
                        if metric != .sleepDuration { Text(metric.unit).foregroundStyle(.secondary) }
                        Spacer()
                        if let normal = latest.normalRange {
                            Text("Normal \(Format.number(normal.low, digits: metric.fractionDigits))–\(Format.number(normal.high, digits: metric.fractionDigits))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    MetricTrendChart(metric: metric, points: points)
                    if metric.hasNormalRange {
                        Label("Shaded band = your personal normal range", systemImage: "square.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .labelStyle(LegendLabelStyle(color: .green.opacity(0.3)))
                    }
                } else {
                    Text("No \(metric.title.lowercased()) data in this period.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
            }
        }
    }

    private func display(_ value: Double) -> String {
        metric == .sleepDuration ? Format.duration(value * 3600) : Format.number(value, digits: metric.fractionDigits)
    }
}

struct LegendLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 8)
            configuration.title
        }
    }
}

private struct WorkoutList: View {
    let days: [DayMetrics]

    var body: some View {
        let workouts = days.flatMap(\.workouts).reversed()
        Card(title: "Workouts this week", systemImage: "figure.mixed.cardio") {
            if workouts.isEmpty {
                Text("No workouts in the last 7 days.").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(workouts)) { scored in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(scored.workout.activityName).font(.subheadline.weight(.semibold))
                                Text("\(scored.workout.start.relativeDayName) · \(Format.duration(scored.workout.duration)) · effort \(Format.number(scored.effort, digits: 1)) (\(scored.effortSource.label))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Format.number(scored.load))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                        }
                        .padding(.vertical, 8)
                        .accessibilityElement(children: .combine)
                        Divider()
                    }
                    Text("Load = minutes × effort (1–10).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
            }
        }
    }
}

extension WorkoutRecord.EffortSource {
    var label: String {
        switch self {
        case .userRated: String(localized: "you rated")
        case .appleEstimated: String(localized: "Apple estimate")
        case .heartRate: String(localized: "from heart rate")
        case .energy: String(localized: "from energy")
        case .assumed: String(localized: "assumed")
        }
    }
}
