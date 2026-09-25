import Charts
import ReadinessCore
import SwiftUI

struct WatchRootView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        NavigationStack {
            if let snapshot = model.payload, let score = snapshot.today {
                TabView {
                    ScorePage(score: score, isLocal: model.isLocal, isSample: snapshot.isSampleData)
                    ContributorsPage(score: score, trends: snapshot.trends)
                    if let night = snapshot.trends?.lastNight {
                        LastNightPage(sleep: night)
                    }
                    if let hrv = snapshot.trends?.hrv, hrv.contains(where: { $0.value != nil }) {
                        TrendPage(title: "HRV", unit: "ms", systemImage: "waveform.path.ecg", tint: .green, points: hrv, higherIsBetter: true)
                    }
                    if let rhr = snapshot.trends?.restingHeartRate, rhr.contains(where: { $0.value != nil }) {
                        TrendPage(title: "Resting HR", unit: "bpm", systemImage: "heart.fill", tint: .red, points: rhr, higherIsBetter: false)
                    }
                    if snapshot.week.count > 1 {
                        WeekPage(week: snapshot.week)
                    }
                }
                .tabViewStyle(.verticalPage)
            } else if model.isComputingLocally {
                ProgressView("Calculating…")
            } else {
                ContentUnavailableView(
                    "No score yet",
                    systemImage: "moon.zzz",
                    description: Text("Wear your watch to sleep, then open OpenReadiness on your iPhone.")
                )
            }
        }
    }
}

// MARK: - Score

private struct ScorePage: View {
    let score: ReadinessScore
    let isLocal: Bool
    let isSample: Bool

    var body: some View {
        VStack(spacing: 4) {
            // Flexible height: shrinks first on 40–41 mm screens so nothing collides with the title.
            ScoreGauge(score: score.score, category: score.category, lineWidth: 9, showsCategory: false)
                .frame(minHeight: 56, maxHeight: 92)
                .layoutPriority(-1)
            Label(score.category.title, systemImage: score.category.systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(score.category.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(score.summary)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            if let note = footnote {
                Text(note).font(.caption2).foregroundStyle(.orange)
            }
        }
        .containerBackground(score.category.color.gradient.opacity(0.35), for: .tabView)
        .navigationTitle("Readiness")
    }

    private var footnote: String? {
        if isSample { return String(localized: "Sample data") }
        if score.isCalibrating { return String(localized: "Calibrating") }
        if isLocal { return String(localized: "Watch-only estimate") }
        return nil
    }
}

// MARK: - Contributors

private struct ContributorsPage: View {
    let score: ReadinessScore
    let trends: ReadinessSnapshot.Trends?

    var body: some View {
        List(score.contributors) { contributor in
            NavigationLink {
                ContributorDetailPage(contributor: contributor, trend: trend(for: contributor.kind))
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label(contributor.kind.shortTitle, systemImage: contributor.kind.systemImage)
                            .font(.headline)
                        Spacer()
                        Text(contributor.status.label)
                            .font(.caption2)
                            .foregroundStyle(contributor.status.color)
                    }
                    SubscoreBar(subscore: contributor.subscore, status: contributor.status, height: 4)
                }
                .padding(.vertical, 2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue("\(contributor.status.label), \(Int(contributor.subscore)) out of 100")
        }
        .navigationTitle("Contributors")
    }

    private func trend(for kind: ContributorKind) -> [ReadinessSnapshot.Point]? {
        switch kind {
        case .hrv: trends?.hrv
        case .restingHeartRate: trends?.restingHeartRate
        default: nil
        }
    }
}

/// The working behind one contributor, sized for the wrist.
private struct ContributorDetailPage: View {
    let contributor: Contributor
    let trend: [ReadinessSnapshot.Point]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.number(contributor.subscore))
                        .font(.system(.title, design: .rounded).bold())
                        .foregroundStyle(contributor.status.color)
                    Text("/ 100").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Format.number(contributor.effectiveWeight * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Weight \(Format.number(contributor.effectiveWeight * 100)) percent")
                }
                Text(contributor.headline).font(.footnote)
                if let trend, trend.contains(where: { $0.value != nil }) {
                    MiniTrendChart(points: trend, tint: contributor.status.color)
                        .frame(height: 64)
                }
                Divider()
                ForEach(contributor.components) { component in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text(component.label).font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text(component.value).font(.caption2.monospacedDigit().weight(.semibold))
                        }
                        if let note = component.note {
                            Text(note).font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle(contributor.kind.shortTitle)
    }
}

// MARK: - Last night

private struct LastNightPage: View {
    let sleep: SleepSummary

    private static let rows: [SleepStage] = [.awake, .rem, .core, .deep, .asleepUnspecified]

    var body: some View {
        let present = Set(sleep.segments.map(\.stage))
        let rows = Self.rows.filter(present.contains)
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Format.duration(sleep.asleep)).font(.title3.bold())
                Text("\(sleep.start.formatted(date: .omitted, time: .shortened)) – \(sleep.end.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)
            Chart(sleep.segments, id: \.start) { segment in
                RectangleMark(
                    xStart: .value("Start", segment.start),
                    xEnd: .value("End", segment.end),
                    y: .value("Stage", segment.stage.label),
                    height: .ratio(0.85)
                )
                .foregroundStyle(segment.stage.color.gradient)
                .cornerRadius(1.5)
            }
            .chartYScale(domain: rows.map(\.label))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(.system(size: 9))
                }
            }
            .frame(maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sleep stages")
            .accessibilityValue(stageSummary)

            HStack(spacing: 6) {
                ForEach([(SleepStage.deep, sleep.deep), (.rem, sleep.rem), (.core, sleep.core)], id: \.0) { stage, duration in
                    if duration > 0 {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 3) {
                                Circle().fill(stage.color).frame(width: 6, height: 6)
                                Text(stage.label).font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                            Text(Format.duration(duration)).font(.system(size: 11).monospacedDigit())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(stage.label) \(Format.duration(duration))")
                    }
                }
            }
        }
        .navigationTitle("Last Night")
    }

    private var stageSummary: String {
        [(SleepStage.deep, sleep.deep), (.core, sleep.core), (.rem, sleep.rem)]
            .filter { $0.1 > 0 }
            .map { "\($0.0.label) \(Format.duration($0.1))" }
            .joined(separator: ", ")
    }
}

// MARK: - Trends

/// Two weeks of a recovery signal against the personal normal band.
private struct TrendPage: View {
    let title: LocalizedStringKey
    let unit: String
    let systemImage: String
    let tint: Color
    let points: [ReadinessSnapshot.Point]
    let higherIsBetter: Bool

    var body: some View {
        let latest = points.last { $0.value != nil }
        VStack(alignment: .leading, spacing: 4) {
            if let latest, let value = latest.value {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Format.number(value)).font(.title2.bold().monospacedDigit())
                    Text(unit).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    if let low = latest.low, let high = latest.high {
                        Text("Normal \(Format.number(low))–\(Format.number(high))")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            MiniTrendChart(points: points, tint: tint)
                .frame(maxHeight: .infinity)
            Text("Last 14 days · shaded = your normal")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .navigationTitle {
            Label(title, systemImage: systemImage).foregroundStyle(tint)
        }
    }
}

private struct MiniTrendChart: View {
    let points: [ReadinessSnapshot.Point]
    let tint: Color

    var body: some View {
        let valued = points.filter { $0.value != nil }
        Chart {
            ForEach(points.filter { $0.low != nil && $0.high != nil }) { point in
                AreaMark(
                    x: .value("Day", point.day, unit: .day),
                    yStart: .value("Low", point.low ?? 0),
                    yEnd: .value("High", point.high ?? 0)
                )
                .foregroundStyle(.green.opacity(0.2))
                .interpolationMethod(.monotone)
            }
            ForEach(valued) { point in
                LineMark(x: .value("Day", point.day, unit: .day), y: .value("Value", point.value ?? 0))
                    .foregroundStyle(tint)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Day", point.day, unit: .day), y: .value("Value", point.value ?? 0))
                    .foregroundStyle(outside(point) ? Color.orange : tint)
                    .symbolSize(point.id == valued.last?.id ? 36 : 12)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(.system(size: 9))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                AxisValueLabel().font(.system(size: 9))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last 14 days")
        .accessibilityValue(summary(valued))
    }

    private func outside(_ point: ReadinessSnapshot.Point) -> Bool {
        guard let value = point.value, let low = point.low, let high = point.high else { return false }
        return value < low || value > high
    }

    private func summary(_ valued: [ReadinessSnapshot.Point]) -> String {
        let outsideCount = valued.filter(outside).count
        return "\(valued.count) readings, \(outsideCount) outside your normal range"
    }
}

// MARK: - Week

private struct WeekPage: View {
    let week: [ReadinessSnapshot.DayScore]

    var body: some View {
        Chart(week, id: \.day) { day in
            BarMark(x: .value("Day", day.day, unit: .day), y: .value("Score", day.score))
                .foregroundStyle(ReadinessCategory(score: day.score).color.gradient)
                .cornerRadius(2)
                .annotation(position: .top) {
                    Text("\(day.score)").font(.system(size: 10).monospacedDigit())
                }
                .accessibilityLabel(day.day.relativeDayName)
                .accessibilityValue("\(day.score)")
        }
        .chartYScale(domain: 0...11)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
            }
        }
        .padding(.horizontal, 4)
        .navigationTitle("This Week")
    }
}
