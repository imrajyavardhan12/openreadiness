import Foundation
import ReadinessCore
import WidgetKit

enum WidgetKinds {
    static let readiness = "org.openreadiness.readiness"
}

/// The one way to publish a new score outside the app: persist it for the widget extension and ask
/// WidgetKit to redraw. Reloads are budgeted by the system, so this skips them when nothing changed.
enum SnapshotPublisher {
    static func publish(_ snapshot: ReadinessSnapshot) {
        let previous = SnapshotStore.load()
        SnapshotStore.save(snapshot)
        guard previous?.today != snapshot.today || previous?.isSampleData != snapshot.isSampleData else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.readiness)
    }
}
