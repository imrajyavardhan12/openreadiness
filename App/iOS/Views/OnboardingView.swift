import SwiftUI

/// Explains exactly what is read and why *before* the system permission sheet appears.
struct OnboardingView: View {
    let onContinue: () async -> Void

    @Environment(ReadinessStore.self) private var store
    @State private var isRequesting = false

    private let items: [(icon: String, title: String, detail: String)] = [
        ("waveform.path.ecg", "Heart rate variability & heart rate", "Compared with your own normal to see how recovered you are."),
        ("bed.double", "Sleep", "Duration, consistency and interruptions from your watch."),
        ("figure.run", "Workouts & active energy", "To weigh recent training against what you're used to."),
        ("lungs", "Overnight vitals", "Respiratory rate, wrist temperature and blood oxygen, where your watch records them."),
        ("chart.xyaxis.line", "Everything else your watch measures", "Steps, rings, cardio fitness, mobility, daylight and sound levels — for charts and insights."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    ScoreGauge(score: 7, category: .ready, lineWidth: 12, showsLabel: true)
                        .frame(width: 140)
                        .accessibilityHidden(true)
                    Text("Readiness for every Apple Watch")
                        .font(.largeTitle.bold())
                    Text("A transparent 0–10 readiness score built from data your watch already collects. Every number shows its working.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 18) {
                    Text("What OpenReadiness reads").font(.headline)
                    ForEach(items, id: \.title) { item in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: item.icon)
                                .font(.title2)
                                .foregroundStyle(.tint)
                                .frame(width: 32)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.subheadline.weight(.semibold))
                                Text(item.detail).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                Label {
                    Text("Everything is computed on this iPhone. No accounts, no servers, no analytics. The app never writes to Health.")
                } icon: {
                    Image(systemName: "lock.shield.fill").foregroundStyle(.green)
                }
                .font(.subheadline)
                .padding()
                .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button {
                    isRequesting = true
                    Task {
                        await onContinue()
                        isRequesting = false
                    }
                } label: {
                    Group {
                        if isRequesting { ProgressView() } else { Text("Connect to Health") }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isRequesting)

                Button("Explore with sample data") { store.usesDemoData = true }
                    .font(.subheadline)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .background(.bar)
        }
    }
}
