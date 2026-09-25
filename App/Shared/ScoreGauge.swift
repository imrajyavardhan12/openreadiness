import ReadinessCore
import SwiftUI

/// A 270° arc gauge for a 0–10 score. Faint band segments show where each category begins,
/// so the gauge explains itself without a legend.
struct ScoreGauge: View {
    let score: Int?
    let category: ReadinessCategory?
    var lineWidth: CGFloat = 18
    var showsLabel = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedFraction: Double = 0

    private let sweep = 0.75 // of a full circle
    private var fraction: Double { Double(score ?? 0) / 10 }
    private var tint: Color { category?.color ?? .secondary }

    var body: some View {
        ZStack {
            // Category bands.
            ForEach(ReadinessCategory.allCases, id: \.self) { band in
                arc(
                    from: max(0, Double(band.scoreRange.lowerBound) - 0.5) / 10,
                    to: min(10, Double(band.scoreRange.upperBound) + 0.5) / 10
                )
                .stroke(band.color.opacity(0.18), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            }
            if score != nil {
                arc(from: 0, to: animatedFraction)
                    .stroke(
                        AngularGradient(
                            colors: [tint.opacity(0.6), tint],
                            center: .center,
                            startAngle: .degrees(135),
                            endAngle: .degrees(135 + 360 * sweep * max(animatedFraction, 0.01))
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
            }
            if showsLabel {
                VStack(spacing: 0) {
                    Text(score.map(String.init) ?? "–")
                        .font(.system(size: 200, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.1)
                        .contentTransition(.numericText())
                        .foregroundStyle(tint)
                    if let category {
                        Label(category.title, systemImage: category.systemImage)
                            .font(.headline)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(lineWidth * 2)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { animate() }
        .onChange(of: score) { animate() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Readiness")
        .accessibilityValue(
            score.map { "\($0) out of 10, \(category?.title ?? "")" } ?? String(localized: "No score yet")
        )
    }

    private func animate() {
        if reduceMotion {
            animatedFraction = fraction
        } else {
            withAnimation(.spring(duration: 0.9, bounce: 0.15)) { animatedFraction = fraction }
        }
    }

    private func arc(from start: Double, to end: Double) -> some Shape {
        ArcShape(start: 135 + 360 * sweep * start, end: 135 + 360 * sweep * end)
    }
}

private struct ArcShape: Shape {
    var start: Double
    var end: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(start, end) }
        set { (start, end) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2,
            startAngle: .degrees(start),
            endAngle: .degrees(end),
            clockwise: false
        )
        return path
    }
}

/// A 0–100 bar with a tick at 70 marking "your normal".
struct SubscoreBar: View {
    let subscore: Double
    let status: ContributorStatus
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(status.color.gradient)
                    .frame(width: max(height, proxy.size.width * subscore / 100))
                Rectangle()
                    .fill(.primary.opacity(0.5))
                    .frame(width: 1.5, height: height + 4)
                    .offset(x: proxy.size.width * 0.7)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack {
        ScoreGauge(score: 7, category: .ready)
        ScoreGauge(score: 2, category: .paceYourself, lineWidth: 10)
            .frame(width: 120)
        SubscoreBar(subscore: 62, status: .neutral)
    }
    .padding()
}
