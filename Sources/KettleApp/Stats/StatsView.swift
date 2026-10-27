import Charts
import KettleCore
import SwiftUI

/// Time per label, a stacked daily chart, and the totals table with planned vs. actual.
struct StatsView: View {
    @Bindable var state: StatsState

    var body: some View {
        let rows = state.rows
        VStack(alignment: .leading, spacing: 16) {
            periodPicker
            if let error = state.loadError {
                Text(error).foregroundStyle(.red)
            }
            if rows.allSatisfy({ $0.totals.seconds == 0 && $0.totals.tasksDone == 0 }) {
                Text("Nothing brewed in this period yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                perLabelChart(rows)
                dailyChart
                totalsTable(rows)
            }
        }
        .padding(20)
        .frame(width: 680, height: 640)
    }

    private var periodPicker: some View {
        HStack {
            Picker("Period", selection: $state.period) {
                Text("Today").tag(StatsState.Period.today)
                Text("This week").tag(StatsState.Period.thisWeek)
                Text("This month").tag(StatsState.Period.thisMonth)
                Text("Custom").tag(StatsState.Period.custom)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if state.period == .custom {
                DatePicker("From", selection: $state.customStart, displayedComponents: .date).labelsHidden()
                Text("to")
                DatePicker("To", selection: $state.customEnd, displayedComponents: .date).labelsHidden()
            }
        }
    }

    // MARK: Charts

    private func perLabelChart(_ rows: [StatsRow]) -> some View {
        Chart(rows, id: \.labelID) { row in
            BarMark(
                x: .value("Minutes", row.totals.seconds / 60),
                y: .value("Label", state.name(of: row.labelID))
            )
            .foregroundStyle(color(for: row.labelID))
            .annotation(position: .trailing) {
                Text(DurationText.short(seconds: row.totals.seconds)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .chartXAxisLabel("Minutes")
        .frame(height: CGFloat(max(rows.count, 1)) * 26 + 30)
        .accessibilityLabel("Time per label")
    }

    private struct DayBar: Identifiable {
        let id: String
        let date: Date
        let label: String
        let minutes: Double
    }

    private var dailyChart: some View {
        let bars = state.days.flatMap { day in
            day.secondsByLabel.map { labelID, seconds in
                DayBar(
                    id: "\(day.date)-\(labelID?.uuidString ?? "none")",
                    date: day.date.date(in: state.calendar),
                    label: state.name(of: labelID),
                    minutes: Double(seconds) / 60
                )
            }
        }
        let names = state.rows.map { state.name(of: $0.labelID) }
        let colors = state.rows.map { color(for: $0.labelID) }
        return Chart(bars) { bar in
            BarMark(x: .value("Day", bar.date, unit: .day), y: .value("Minutes", bar.minutes))
                .foregroundStyle(by: .value("Label", bar.label))
        }
        .chartForegroundStyleScale(domain: names, range: colors)
        .chartYAxisLabel("Minutes")
        .frame(height: 170)
        .accessibilityLabel("Minutes per day, stacked by label")
    }

    // MARK: Table

    private func totalsTable(_ rows: [StatsRow]) -> some View {
        ScrollView {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Label")
                    Text("Brewed")
                    Text("Planned → actual (done tasks)")
                    Text("Extended")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                Divider()
                ForEach(rows, id: \.labelID) { row in
                    GridRow {
                        HStack(spacing: 6) {
                            Circle().fill(color(for: row.labelID)).frame(width: 8, height: 8)
                            Text(state.name(of: row.labelID))
                            if case let .label(label) = row.kind, label.isArchived {
                                Text("archived").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text(DurationText.short(seconds: row.totals.seconds)).monospacedDigit()
                        Text(plannedVersusActual(row.totals)).monospacedDigit()
                        Text("\(row.totals.tasksExtended) of \(row.totals.tasksDone)").monospacedDigit()
                    }
                }
            }
        }
    }

    private func plannedVersusActual(_ totals: LabelTotals) -> String {
        guard totals.tasksDone > 0 else { return "–" }
        return "\(DurationText.short(seconds: totals.plannedMinutes * 60)) → "
            + DurationText.short(seconds: totals.doneSeconds)
    }

    private func color(for labelID: UUID?) -> Color {
        state.colorHex(of: labelID).map { Color(hex: $0) } ?? .gray
    }
}
