import SwiftUI
import WidgetKit

@main
struct OpenReadinessWidgets: WidgetBundle {
    var body: some Widget {
        ReadinessWidget()
    }
}

struct ReadinessWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.readiness, provider: ReadinessProvider()) { entry in
            ReadinessWidgetView(entry: entry)
        }
        .configurationDisplayName("Readiness")
        .description("Today's readiness score and what's driving it.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .systemSmall) {
    ReadinessWidget()
} timeline: {
    ReadinessEntry(date: .now, snapshot: .sample())
    ReadinessEntry(date: .now, snapshot: .sample(score: 3))
    ReadinessEntry(date: .now, snapshot: nil)
}

#Preview(as: .systemMedium) {
    ReadinessWidget()
} timeline: {
    ReadinessEntry(date: .now, snapshot: .sample())
}
