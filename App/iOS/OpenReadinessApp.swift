import SwiftUI

@main
struct OpenReadinessApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: ReadinessStore
    @State private var explorer: ExplorerStore
    @State private var importer: ImportController
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = ReadinessStore(forceDemo: ProcessInfo.processInfo.arguments.contains("-demo"))
        _store = State(initialValue: store)
        let explorer = ExplorerStore(dataMode: store.dataMode)
        _explorer = State(initialValue: explorer)
        _importer = State(initialValue: ImportController(store: store, explorer: explorer))
        WatchSync.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding || store.dataMode != .health {
                    RootView()
                } else {
                    OnboardingView {
                        await store.requestAuthorization()
                        hasCompletedOnboarding = true
                        BackgroundRefresher.shared.start()
                    }
                }
            }
            .environment(store)
            .environment(explorer)
            .environment(importer)
            .task(id: hasCompletedOnboarding) {
                await importer.restoreIfNeeded()
                #if DEBUG
                // Development: `-importHealthExport /path/to/export.xml` loads an export from the Mac
                // straight into the Simulator, without the file picker.
                let arguments = ProcessInfo.processInfo.arguments
                if let index = arguments.firstIndex(of: "-importHealthExport"), index + 1 < arguments.count, !importer.hasImport {
                    await importer.importExport(from: URL(fileURLWithPath: arguments[index + 1]))
                }
                #endif
                guard hasCompletedOnboarding || store.dataMode != .health else { return }
                // Asks only for types added since the user last answered (e.g. after an update).
                if store.dataMode == .health { await store.requestAuthorization() }
                store.observeHealthKitChanges()
                await store.refresh()
            }
            .onChange(of: store.dataMode) { _, mode in
                explorer.dataMode = mode
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, store.phase == .loaded {
                    Task {
                        await store.refresh()
                        if explorer.hasLoaded { await explorer.reload() }
                    }
                }
            }
        }
    }
}

struct RootView: View {
    var body: some View {
        // `.tabItem` rather than `Tab` keeps iOS 17 support.
        TabView {
            NavigationStack { TodayView() }
                .tabItem { Label("Today", systemImage: "gauge.with.dots.needle.67percent") }
            NavigationStack { HealthDashboardView() }
                .tabItem { Label("Health", systemImage: "heart.text.square") }
            NavigationStack { WorkoutsView() }
                .tabItem { Label("Workouts", systemImage: "figure.run") }
            NavigationStack { InsightsView() }
                .tabItem { Label("Insights", systemImage: "lightbulb") }
            NavigationStack { AboutView() }
                .tabItem { Label("About", systemImage: "info.circle") }
        }
    }
}
