#if DEBUG
import SwiftUI

/// Debug-only: renders the real widget views at their system sizes, in the states that matter
/// (good day, poor day, stale/no data), so they can be reviewed and screenshotted without adding
/// widgets to a Home Screen.
struct WidgetGalleryView: View {
    private let states: [(title: String, entry: ReadinessEntry)] = [
        ("Go For It", ReadinessEntry(date: .now, snapshot: .sample(score: 8))),
        ("Pace Yourself", ReadinessEntry(date: .now, snapshot: .sample(score: 3))),
        ("No score today", ReadinessEntry(date: .now, snapshot: nil)),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section("Home Screen") {
                    ForEach(states, id: \.title) { state in
                        HStack(alignment: .top, spacing: 12) {
                            frame(width: 158, height: 158) { SmallReadinessView(entry: state.entry) }
                            frame(width: 158, height: 158) { SmallReadinessView(entry: state.entry) }
                                .environment(\.colorScheme, .dark)
                        }
                    }
                    frame(width: 338, height: 158) { MediumReadinessView(entry: states[0].entry) }
                    frame(width: 338, height: 158) { MediumReadinessView(entry: states[2].entry) }
                }
                section("Lock Screen & watch face") {
                    HStack(spacing: 16) {
                        ForEach(states, id: \.title) { state in
                            CircularReadinessView(entry: state.entry)
                                .frame(width: 64, height: 64)
                        }
                    }
                    RectangularReadinessView(entry: states[0].entry).frame(width: 172, height: 72, alignment: .leading)
                    InlineReadinessView(entry: states[0].entry)
                }
                .padding()
                .background(.black, in: RoundedRectangle(cornerRadius: 24))
                .environment(\.colorScheme, .dark)
            }
            .padding()
        }
        .navigationTitle("Widget gallery")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
    }

    private func frame<Content: View>(width: CGFloat, height: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(width: width, height: height)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.quaternary))
    }
}
#endif
