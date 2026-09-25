import ReadinessCore
import SwiftUI

/// A calendar heatmap of scores plus category distribution. Tap a day for its full breakdown.
struct HistoryView: View {
    @Environment(ReadinessStore.self) private var store

    private var scores: [ReadinessScore] { store.analysis.orderedScores }

    private var months: [Date] {
        let calendar = Calendar.current
        let starts = Set(scores.map { calendar.dateInterval(of: .month, for: $0.day)!.start })
        return starts.sorted(by: >)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if scores.isEmpty {
                    ContentUnavailableView("No history yet", systemImage: "calendar", description: Text("Scores appear here day by day."))
                } else {
                    Card(title: "Last \(scores.count) days", systemImage: "chart.bar") {
                        ScoreHistoryChart(scores: scores, height: 160)
                        CategoryDistribution(scores: scores)
                    }
                    ForEach(months, id: \.self) { month in
                        Card(title: LocalizedStringKey(month.formatted(.dateTime.month(.wide).year())), systemImage: "calendar") {
                            MonthHeatmap(month: month, scores: store.analysis.scores)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("History")
        .navigationDestination(for: Date.self) { day in
            DayDetailView(day: day)
        }
    }
}

private struct CategoryDistribution: View {
    let scores: [ReadinessScore]

    var body: some View {
        let counts = Dictionary(grouping: scores, by: \.category).mapValues(\.count)
        HStack(spacing: 8) {
            ForEach(ReadinessCategory.allCases.reversed(), id: \.self) { category in
                VStack(spacing: 2) {
                    Text("\(counts[category] ?? 0)").font(.headline.monospacedDigit()).foregroundStyle(category.color)
                    Text(category.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, 8)
    }
}

private struct MonthHeatmap: View {
    let month: Date
    let scores: [Date: ReadinessScore]

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    private var cells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let days = (0..<dayCount).map { calendar.date(byAdding: .day, value: $0, to: interval.start) }
        return Array(repeating: nil, count: leading) + days
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        cell(for: day)
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(for day: Date) -> some View {
        let score = scores[calendar.startOfDay(for: day)]
        let content = VStack(spacing: 0) {
            Text("\(calendar.component(.day, from: day))")
                .font(.caption2)
                .foregroundStyle(score == nil ? .tertiary : .secondary)
            Text(score.map { "\($0.score)" } ?? " ")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(score?.category.color ?? .clear)
        }
        .frame(maxWidth: .infinity, minHeight: 38)
        .background(
            (score?.category.color ?? Color.gray).opacity(score == nil ? 0.05 : 0.16),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            if calendar.isDateInToday(day) {
                RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.6), lineWidth: 1.5)
            }
        }

        if let score {
            NavigationLink(value: score.day) { content }
                .buttonStyle(.plain)
                .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                .accessibilityValue("\(score.score), \(score.category.title)")
        } else {
            content
                .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                .accessibilityValue("No score")
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}

private struct DayDetailView: View {
    let day: Date
    @Environment(ReadinessStore.self) private var store

    var body: some View {
        ScrollView {
            if let score = store.analysis.scores[day] {
                ScoreDetailContent(score: score, analysis: store.analysis)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month()))
        .navigationBarTitleDisplayMode(.inline)
    }
}
