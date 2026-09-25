import SwiftUI
import WidgetKit

@main
struct OpenReadinessComplications: WidgetBundle {
    var body: some Widget {
        ReadinessComplication()
    }
}

struct ReadinessComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.readiness, provider: ReadinessProvider()) { entry in
            ReadinessWidgetView(entry: entry)
        }
        .configurationDisplayName("Readiness")
        .description("Today's readiness score on your watch face.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

#Preview(as: .accessoryRectangular) {
    ReadinessComplication()
} timeline: {
    ReadinessEntry(date: .now, snapshot: .sample())
}
