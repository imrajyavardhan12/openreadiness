import ReadinessCore
import SwiftUI
import WidgetKit

struct ReadinessEntry: TimelineEntry {
    let date: Date
    let snapshot: ReadinessSnapshot?

    /// nil when there's no score for this entry's day — shown as "–", never as yesterday's number.
    var score: ReadinessScore? { snapshot?.score(on: date) }
}

/// Reads the snapshot the app last wrote. The app (and HealthKit background delivery) call
/// `WidgetCenter.reloadAllTimelines()` whenever the score changes, so the timeline only needs one
/// extra entry: midnight, when today's score stops being today's.
struct ReadinessProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReadinessEntry {
        ReadinessEntry(date: .now, snapshot: .sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (ReadinessEntry) -> Void) {
        let stored = SnapshotStore.load()
        completion(ReadinessEntry(date: .now, snapshot: context.isPreview && stored == nil ? .sample() : stored))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReadinessEntry>) -> Void) {
        let now = Date.now
        let snapshot = SnapshotStore.load()
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
        let entries = [ReadinessEntry(date: now, snapshot: snapshot), ReadinessEntry(date: midnight, snapshot: snapshot)]
        // Ask again early in the morning in case the app hasn't run since new sleep data arrived.
        let refresh = Calendar.current.date(byAdding: .hour, value: 7, to: midnight) ?? midnight
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

/// Routes each widget family to its view.
struct ReadinessWidgetView: View {
    let entry: ReadinessEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        #if os(iOS)
        case .systemSmall:
            SmallReadinessView(entry: entry)
        case .systemMedium:
            MediumReadinessView(entry: entry)
        #endif
        case .accessoryRectangular:
            RectangularReadinessView(entry: entry)
        case .accessoryInline:
            InlineReadinessView(entry: entry)
        #if os(watchOS)
        case .accessoryCorner:
            CornerReadinessView(entry: entry)
        #endif
        default:
            CircularReadinessView(entry: entry)
        }
    }
}

// MARK: - Home screen (iOS)

struct SmallReadinessView: View {
    let entry: ReadinessEntry

    var body: some View {
        VStack(spacing: 2) {
            ScoreGauge(score: entry.score?.score, category: entry.score?.category, lineWidth: 10, showsCategory: false, animated: false)
            if let score = entry.score {
                Label(score.category.title, systemImage: score.category.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(score.category.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if entry.snapshot?.isSampleData == true {
                    Text("Sample data").font(.caption2).foregroundStyle(.orange)
                }
            } else {
                Text("Open app to update").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .widgetBackground(entry.score?.category.color)
    }
}

struct MediumReadinessView: View {
    let entry: ReadinessEntry

    var body: some View {
        HStack(spacing: 14) {
            ScoreGauge(score: entry.score?.score, category: entry.score?.category, lineWidth: 10, showsLabel: true, animated: false)
            VStack(alignment: .leading, spacing: 6) {
                if let score = entry.score {
                    ForEach(score.contributors.prefix(4)) { contributor in
                        HStack(spacing: 6) {
                            Image(systemName: contributor.kind.systemImage)
                                .font(.caption2)
                                .foregroundStyle(contributor.status.color)
                                .frame(width: 14)
                            Text(contributor.kind.shortTitle).font(.caption.weight(.semibold)).lineLimit(1)
                            Spacer(minLength: 2)
                            SubscoreBar(subscore: contributor.subscore, status: contributor.status, height: 4)
                                .frame(width: 44)
                        }
                    }
                    Text(entry.snapshot?.isSampleData == true ? "Sample data" : score.summary)
                        .font(.caption2)
                        .foregroundStyle(entry.snapshot?.isSampleData == true ? .orange : .secondary)
                        .lineLimit(2)
                } else {
                    Text("No score yet today").font(.headline)
                    Text("Wear your watch to sleep, then open OpenReadiness.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .widgetBackground(entry.score?.category.color)
    }
}

// MARK: - Lock screen & watch face

struct CircularReadinessView: View {
    let entry: ReadinessEntry

    var body: some View {
        Gauge(value: Double(entry.score?.score ?? 0), in: 0...10) {
            Image(systemName: "gauge.with.dots.needle.67percent")
        } currentValueLabel: {
            Text(entry.score.map { "\($0.score)" } ?? "–")
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
        .accessibilityLabel("Readiness")
        .accessibilityValue(entry.score.map { "\($0.score) out of 10, \($0.category.title)" } ?? "No score yet")
        .widgetBackground(nil)
    }
}

struct RectangularReadinessView: View {
    let entry: ReadinessEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: entry.score?.category.systemImage ?? "gauge.with.dots.needle.67percent")
                Text(entry.score.map { "\($0.score) · \($0.category.title)" } ?? "Readiness –")
                    .font(.headline)
            }
            .widgetAccentable()
            Text(entry.score?.summary ?? "Open OpenReadiness to update")
                .font(.caption)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .widgetBackground(nil)
    }
}

struct InlineReadinessView: View {
    let entry: ReadinessEntry

    var body: some View {
        Text(entry.score.map { "Readiness \($0.score) · \($0.category.title)" } ?? "Readiness –")
            .widgetBackground(nil)
    }
}

#if os(watchOS)
struct CornerReadinessView: View {
    let entry: ReadinessEntry

    var body: some View {
        Text(entry.score.map { "\($0.score)" } ?? "–")
            .font(.title2.bold())
            .widgetCurvesContent()
            .widgetLabel {
                Gauge(value: Double(entry.score?.score ?? 0), in: 0...10) {
                    Text("Readiness")
                }
                .tint(entry.score?.category.color ?? .gray)
            }
            .widgetBackground(nil)
    }
}
#endif

extension View {
    /// The required widget container background, tinted by category on the home screen.
    @ViewBuilder
    func widgetBackground(_ tint: Color?) -> some View {
        containerBackground(for: .widget) {
            if let tint {
                LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.04)], startPoint: .top, endPoint: .bottom)
            } else {
                Color.clear
            }
        }
    }
}
