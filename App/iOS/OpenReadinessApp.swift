import SwiftUI

@main
struct OpenReadinessApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: ReadinessStore
    @State private var explorer: ExplorerStore
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = ReadinessStore(forceDemo: ProcessInfo.processInfo.arguments.contains("-demo"))
        _store = State(initialValue: store)
        _explorer = State(initialValue: ExplorerStore(usesDemoData: store.usesDemoData))
        WatchSync.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding || store.usesDemoData {
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
            .task(id: hasCompletedOnboarding) {
                guard hasCompletedOnboarding || store.usesDemoData else { return }
                // Asks only for types added since the user last answered (e.g. after an update).
                if !store.usesDemoData { await store.requestAuthorization() }
                store.observeHealthKitChanges()
                await store.refresh()
            }
            .onChange(of: store.usesDemoData) { _, demo in
                explorer.usesDemoData = demo
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
