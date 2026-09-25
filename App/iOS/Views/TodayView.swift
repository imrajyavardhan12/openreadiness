import ReadinessCore
import SwiftUI

struct TodayView: View {
    @Environment(ReadinessStore.self) private var store

    var body: some View {
        ScrollView {
            switch store.phase {
            case .idle:
                ProgressView("Reading your health data…")
                    .frame(maxWidth: .infinity, minHeight: 400)
            case .loading where store.analysis.days.isEmpty:
                ProgressView("Reading your health data…")
                    .frame(maxWidth: .infinity, minHeight: 400)
            case .failed(let message) where store.analysis.days.isEmpty:
                ContentUnavailableView {
                    Label("Couldn't read Health data", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await store.refresh() } }
                }
            default:
                if store.dataMode == .sample { SampleDataBanner() }
                if store.dataMode == .imported { ImportedDataBanner(through: store.referenceDate) }
                if let score = store.analysis.today {
                    ScoreDetailContent(score: score, analysis: store.analysis, showsWeek: true)
                } else {
                    NoScoreView(analysis: store.analysis)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(Date.now.formatted(.dateTime.weekday(.wide).day().month()))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    HistoryView()
                } label: {
                    Label("History", systemImage: "calendar")
                }
            }
        }
        .refreshable { await store.refresh() }
    }
}

/// Makes it impossible to mistake generated data for your own.
private struct SampleDataBanner: View {
    var body: some View {
        Label("Showing sample data — turn off in About", systemImage: "flask")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .padding([.horizontal, .top])
    }
}

/// Makes it clear the screen shows an imported export, not live data.
private struct ImportedDataBanner: View {
    let through: Date?

    var body: some View {
        Label {
            Text(through.map { "Imported Health export · data through \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Imported Health export")
        } icon: {
            Image(systemName: "tray.and.arrow.down")
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.blue)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .padding([.horizontal, .top])
    }
}

/// Score, contributors and last night — used for today and for any day in History.
struct ScoreDetailContent: View {
    let score: ReadinessScore
    let analysis: ReadinessAnalysis
    var showsWeek = false

    private var metrics: DayMetrics? { analysis.metrics(for: score.day) }

    var body: some View {
        VStack(spacing: 16) {
            HeroCard(score: score)

            if showsWeek {
                let week = analysis.orderedScores.suffix(7)
                if week.count > 1 {
                    Card(title: "Last 7 days", systemImage: "chart.bar") {
                        ScoreHistoryChart(scores: Array(week), height: 130)
                    }
                }
            }

            Card(title: "What's driving your score", systemImage: "slider.horizontal.3") {
                VStack(spacing: 0) {
                    ForEach(score.contributors) { contributor in
                        NavigationLink(value: contributor.kind) {
                            ContributorRow(contributor: contributor)
                        }
                        .buttonStyle(.plain)
                        if contributor.id != score.contributors.last?.id { Divider().padding(.leading, 40) }
                    }
                    let missing = ContributorKind.allCases.filter { score.contributor($0) == nil }
                    if !missing.isEmpty {
                        Divider()
                        Text("Not enough data yet for: \(missing.map(\.shortTitle).joined(separator: ", ")). Their weight is shared among the others.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 10)
                    }
                }
            }

            if let sleep = metrics?.sleep {
                Card(title: "Last night", systemImage: "moon.stars") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(Format.duration(sleep.asleep)).font(.title2.bold())
                            Text("asleep").foregroundStyle(.secondary)
                            Spacer()
                            Text("\(sleep.start.formatted(date: .omitted, time: .shortened)) – \(sleep.end.formatted(date: .omitted, time: .shortened))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if sleep.hasStages { HypnogramChart(sleep: sleep) }
                        SleepStageBreakdown(sleep: sleep)
                    }
                }
            }

            ConfidenceFooter(score: score)
        }
        .padding()
        .navigationDestination(for: ContributorKind.self) { kind in
            ContributorDetailView(kind: kind, day: score.day)
        }
    }
}

private struct HeroCard: View {
    let score: ReadinessScore

    var body: some View {
        VStack(spacing: 16) {
            ScoreGauge(score: score.score, category: score.category)
                .frame(maxWidth: 240)

            if score.isCalibrating {
                Label("Calibrating · \(score.baselineNights) of 7 nights", systemImage: "hourglass")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 8) {
                Text(score.summary)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(score.category.guidance)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            LinearGradient(colors: [score.category.color.opacity(0.14), .clear], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}

struct ContributorRow: View {
    let contributor: Contributor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: contributor.kind.systemImage)
                .font(.title3)
                .foregroundStyle(contributor.status.color)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(contributor.kind.title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(contributor.status.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(contributor.status.color)
                }
                Text(contributor.headline)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SubscoreBar(subscore: contributor.subscore, status: contributor.status)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(contributor.status.label), \(Int(contributor.subscore)) out of 100, weight \(Int(contributor.effectiveWeight * 100)) percent")
        .accessibilityHint("Shows how this was calculated")
    }
}

private struct ConfidenceFooter: View {
    let score: ReadinessScore
    @Environment(ReadinessStore.self) private var store

    var body: some View {
        VStack(spacing: 4) {
            Text("Confidence \(Int(score.confidence * 100))% · baseline from \(score.baselineNights) nights")
            if let updated = store.lastUpdated {
                Text("Updated \(updated.formatted(.relative(presentation: .named)))")
            }
            Text("Not medical advice. Readiness can't account for conditions or medications.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.top, 4)
    }
}

private struct NoScoreView: View {
    let analysis: ReadinessAnalysis

    var body: some View {
        let nights = analysis.days.suffix(60).filter { $0.sleep != nil }.count
        ContentUnavailableView {
            Label("No score yet", systemImage: "moon.zzz")
        } description: {
            Text(nights == 0
                 ? "Wear your Apple Watch to sleep with Sleep tracking turned on. Your first score appears after a night of data, and becomes personal after 7 nights."
                 : "Found \(nights) night(s) of sleep. Readiness needs last night's sleep or heart data — wear your watch tonight and check back in the morning.")
        } actions: {
            Link("How to set up Sleep on Apple Watch", destination: URL(string: "https://support.apple.com/guide/watch/track-your-sleep-apd830528336/watchos")!)
        }
        .padding(.top, 60)
    }
}

/// Grouped-style card with a small header.
struct Card<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

#Preview {
    @Previewable @State var store = ReadinessStore(forceDemo: true)
    NavigationStack { TodayView() }
        .environment(store)
        .task { await store.refresh() }
}
