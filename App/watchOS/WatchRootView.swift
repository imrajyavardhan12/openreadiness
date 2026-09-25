import Charts
import ReadinessCore
import SwiftUI

struct WatchRootView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        NavigationStack {
            if let score = model.payload?.today {
                TabView {
                    ScorePage(score: score, isLocal: model.isLocal)
                    ContributorsPage(score: score)
                    if let week = model.payload?.week, week.count > 1 {
                        WeekPage(week: week)
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

private struct ScorePage: View {
    let score: ReadinessScore
    let isLocal: Bool

    var body: some View {
        VStack(spacing: 6) {
            ScoreGauge(score: score.score, category: score.category, lineWidth: 9)
                .frame(maxHeight: 110)
            Text(score.summary)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            if score.isCalibrating || isLocal {
                Text(score.isCalibrating ? "Calibrating" : "Watch-only estimate")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .containerBackground(score.category.color.gradient.opacity(0.35), for: .tabView)
        .navigationTitle("Readiness")
    }
}

private struct ContributorsPage: View {
    let score: ReadinessScore

    var body: some View {
        List(score.contributors) { contributor in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(contributor.kind.shortTitle, systemImage: contributor.kind.systemImage)
                        .font(.headline)
                    Spacer()
                    Text(contributor.status.label)
                        .font(.caption2)
                        .foregroundStyle(contributor.status.color)
                }
                Text(contributor.headline)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                SubscoreBar(subscore: contributor.subscore, status: contributor.status, height: 4)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        }
        .navigationTitle("Contributors")
    }
}

private struct WeekPage: View {
    let week: [WatchPayload.DayScore]

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
