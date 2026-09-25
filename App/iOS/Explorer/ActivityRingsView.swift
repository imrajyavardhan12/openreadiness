import Charts
import HealthInsights
import ReadinessCore
import SwiftUI

/// A month of rings at a glance, plus how often each ring closes.
struct ActivityRingsView: View {
    @Environment(ExplorerStore.self) private var explorer
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)!.start

    private var calendar: Calendar { .current }

    var body: some View {
        let interval = calendar.dateInterval(of: .month, for: month)!
        let days = explorer.rings.filter { interval.contains($0.date) }
        ScrollView {
            VStack(spacing: 16) {
                MonthNavigator(month: $month, earliest: explorer.rings.first?.date)

                Card(title: "Rings", systemImage: "circle.circle") {
                    RingsMonthGrid(month: month, days: days)
                }

                if !days.isEmpty {
                    Card(title: "Closed this month", systemImage: "checkmark.circle") {
                        HStack {
                            closed("Move", days.filter { $0.moveProgress >= 1 }.count, of: days.count, ActivityRingsGlyph.moveColor)
                            closed("Exercise", days.filter { $0.exerciseProgress >= 1 }.count, of: days.count, ActivityRingsGlyph.exerciseColor)
                            closed("Stand", days.filter { $0.standProgress >= 1 }.count, of: days.count, ActivityRingsGlyph.standColor)
                        }
                        Text("All three closed on \(days.filter(\.allClosed).count) of \(days.count) days.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Card(title: "Move by day", systemImage: "flame.fill") {
                        Chart(days) { day in
                            BarMark(x: .value("Day", day.date, unit: .day), y: .value("kcal", day.move))
                                .foregroundStyle(day.moveProgress >= 1 ? AnyShapeStyle(ActivityRingsGlyph.moveColor.gradient) : AnyShapeStyle(ActivityRingsGlyph.moveColor.opacity(0.4)))
                                .cornerRadius(2)
                            RuleMark(y: .value("Goal", day.moveGoal))
                                .foregroundStyle(.secondary.opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                                AxisValueLabel(format: .dateTime.day())
                            }
                        }
                        .frame(height: 180)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Activity Rings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func closed(_ title: LocalizedStringKey, _ count: Int, of total: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)").font(.title2.bold().monospacedDigit()).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(Format.number(Double(count) / Double(max(total, 1)) * 100))%").font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct MonthNavigator: View {
    @Binding var month: Date
    var earliest: Date?

    var body: some View {
        let calendar = Calendar.current
        let current = calendar.dateInterval(of: .month, for: .now)!.start
        HStack {
            Button {
                month = calendar.date(byAdding: .month, value: -1, to: month)!
            } label: {
                Image(systemName: "chevron.left").padding(8)
            }
            .disabled(earliest.map { month <= $0 } ?? true)
            .accessibilityLabel("Previous month")
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
            Spacer()
            Button {
                month = calendar.date(byAdding: .month, value: 1, to: month)!
            } label: {
                Image(systemName: "chevron.right").padding(8)
            }
            .disabled(month >= current)
            .accessibilityLabel("Next month")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
    }
}

private struct RingsMonthGrid: View {
    let month: Date
    let days: [ActivityRingDay]

    /// One ForEach over uniquely identified cells. (Several ForEach groups sharing ids 0, 1, 2…
    /// inside one grid make SwiftUI silently drop cells.)
    private enum Cell: Identifiable {
        case header(Int, String)
        case padding(Int)
        case day(Date)

        var id: String {
            switch self {
            case .header(let index, _): "h\(index)"
            case .padding(let index): "p\(index)"
            case .day(let date): "d\(date.timeIntervalSince1970)"
            }
        }
    }

    private var cells: [Cell] {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: month)!
        let leading = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let ordered = Array(symbols[(calendar.firstWeekday - 1)...] + symbols[..<(calendar.firstWeekday - 1)])
        return ordered.enumerated().map { Cell.header($0.offset, $0.element) }
            + (0..<leading).map(Cell.padding)
            + (0..<count).map { Cell.day(calendar.date(byAdding: .day, value: $0, to: interval.start)!) }
    }

    var body: some View {
        let calendar = Calendar.current
        let byDay = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
            ForEach(cells) { cell in
                switch cell {
                case .header(_, let symbol):
                    Text(symbol).font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true)
                case .padding:
                    Color.clear.frame(height: 40)
                case .day(let date):
                    VStack(spacing: 2) {
                        ActivityRingsGlyph(day: byDay[date], lineWidth: 3.5)
                            .frame(width: 34, height: 34)
                            .opacity(date > .now ? 0.25 : 1)
                        Text("\(calendar.component(.day, from: date))").font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                }
            }
        }
    }
}
