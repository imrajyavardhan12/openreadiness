import ReadinessCore
import SwiftUI

/// Settings, the full method in plain language, and privacy.
struct AboutView: View {
    @Environment(ReadinessStore.self) private var store
    @Environment(ExplorerStore.self) private var explorer

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Stepper(value: $store.sleepGoalHours, in: 6...10, step: 0.25) {
                    LabeledContent("Sleep goal", value: "\(Format.number(store.sleepGoalHours, digits: 2))h")
                }
                Toggle("Use sample data", isOn: $store.usesDemoData)
            } header: {
                Text("Settings")
            } footer: {
                Text("Sample data lets you explore every screen without an Apple Watch. It is generated on device and never mixed with your real data.")
            }

            #if DEBUG
            Section("Developer") {
                NavigationLink("Widget gallery") { WidgetGalleryView() }
            }
            #endif

            Section {
                ShareLink(
                    item: CSVExport(content: .readiness(store.analysis)),
                    preview: SharePreview("Readiness history (CSV)")
                ) {
                    Label("Export readiness history", systemImage: "square.and.arrow.up")
                }
                .disabled(store.analysis.days.isEmpty)
                ShareLink(
                    item: CSVExport(content: .metrics(explorer.series)),
                    preview: SharePreview("Daily health metrics (CSV)")
                ) {
                    Label("Export daily health metrics", systemImage: "tablecells")
                }
                .disabled(!explorer.hasLoaded)
            } header: {
                Text("Your data")
            } footer: {
                Text("CSV files for spreadsheets or your own analysis: every daily score, contributor and input, and every metric the Health tab shows. They're created only when you tap, and go only where you choose to send them.")
            }

            Section("How the score works") {
                NavigationLink("The method, step by step") { MethodologyView() }
                ForEach(ContributorKind.allCases) { kind in
                    LabeledContent {
                        Text("\(Format.number((ReadinessConfiguration.defaultWeights[kind] ?? 0) * 100))%")
                            .monospacedDigit()
                    } label: {
                        Label(kind.title, systemImage: kind.systemImage)
                    }
                }
            }

            Section("Score bands") {
                ForEach(ReadinessCategory.allCases.reversed(), id: \.self) { category in
                    LabeledContent {
                        Text("\(category.scoreRange.lowerBound)–\(category.scoreRange.upperBound)").monospacedDigit()
                    } label: {
                        Label(category.title, systemImage: category.systemImage).foregroundStyle(category.color)
                    }
                }
            }

            Section {
                Label("All calculations happen on your device.", systemImage: "iphone")
                Label("No accounts, servers, analytics or ads.", systemImage: "network.slash")
                Label("Read-only access to Health. Nothing is written.", systemImage: "heart.text.square")
                Label("Your iPhone sends only today's score to your own Apple Watch.", systemImage: "applewatch")
            } header: {
                Text("Privacy")
            } footer: {
                Text("To change what OpenReadiness can read: Settings › Health › Data Access & Devices › OpenReadiness.")
            }

            Section {
                Link(destination: AppLinks.repository) {
                    Label("Source code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: AppLinks.issues) {
                    Label("Report a problem or suggest an idea", systemImage: "exclamationmark.bubble")
                }
                Link(destination: AppLinks.algorithm) {
                    Label("Full algorithm documentation", systemImage: "doc.text.magnifyingglass")
                }
            } header: {
                Text("Open source · MIT License")
            } footer: {
                Text("OpenReadiness is not a medical device and is not affiliated with Apple. Readiness can't account for existing conditions or medications and shouldn't be the only thing you rely on when deciding whether it is safe to exercise.")
            }
        }
        .navigationTitle("About")
    }
}

struct MethodologyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                step(1, "Build your personal normal",
                     "For each signal, the previous 60 days form your baseline, using the median and a robust spread (median absolute deviation) so a few odd nights don't distort it. At least 7 nights are needed; until then the score is marked Calibrating.")
                step(2, "Compare last night with your normal",
                     "HRV is RMSSD computed from your watch's beat-to-beat data (Apple's SDNN is the fallback), compared on a log scale (it naturally varies multiplicatively) and blended 70/30 with its 7-day trend. Resting heart rate is your lowest 30-minute average while asleep; lower than usual is better. Each difference becomes a z-score: how many 'normal days' away from typical you are.")
                step(3, "Turn each signal into a 0–100 sub-score",
                     "A smooth curve maps z-scores so that exactly your normal scores 70. Sleep uses a 0–100 sleep score (duration 50, bedtime consistency 30, interruptions 20) plus sleep debt. Training load compares your last 7 days with the 3 weeks before (acute:chronic ratio). Vitals flag respiratory rate, wrist temperature or blood oxygen outside your range.")
                step(4, "Weight and combine",
                     "HRV 30%, sleep 25%, training load 20%, resting heart rate 15%, vitals 10%. If a signal is missing, its weight is shared among the rest. With under 40% of the model available, no score is shown.")
                step(5, "Don't average away red flags",
                     "If HRV, resting heart rate, sleep or vitals is very poor (below 30), the overall score is capped near it. Several red flags at once — the typical illness pattern — cap harder.")
                step(6, "Round to 0–10",
                     "The result is divided by 10 and rounded, then mapped to the same bands as Apple's Readiness: Recover 0–1, Pace Yourself 2–4, Ready 5–7, Go For It 8–10.")

                Text("Every constant lives in ReadinessConfiguration.swift, and the full rationale with references is in docs/ALGORITHM.md in the source repository.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("The Method")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ number: Int, _ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 30, height: 30)
                .background(.tint.opacity(0.15), in: Circle())
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(body).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

enum AppLinks {
    static let repository = URL(string: "https://github.com/imrajyavardhan12/openreadiness")!
    static let issues = URL(string: "https://github.com/imrajyavardhan12/openreadiness/issues")!
    static let algorithm = URL(string: "https://github.com/imrajyavardhan12/openreadiness/blob/main/docs/ALGORITHM.md")!
}
