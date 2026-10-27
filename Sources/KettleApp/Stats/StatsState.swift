import Foundation
import KettleCore
import Observation

/// What the Stats window shows. It loads `daily-totals.json` once when the window opens and is
/// dropped with the window.
@Observable
final class StatsState {
    enum Period: Hashable, CaseIterable {
        case today, thisWeek, thisMonth, custom
    }

    var period = Period.thisWeek
    var customStart: Date
    var customEnd: Date
    private(set) var loadError: String?

    @ObservationIgnored private let totals: DailyTotals
    @ObservationIgnored private let labels: [KettleCore.Label]
    @ObservationIgnored private let today: LocalDate
    @ObservationIgnored private let weekStartsOn: Weekday
    @ObservationIgnored let calendar = Calendar.autoupdatingCurrent

    init(model: KettleModel) {
        do {
            totals = try model.loadStats()
        } catch {
            totals = DailyTotals()
            loadError = "The stats file couldn't be read: \(error.localizedDescription)"
        }
        labels = model.labels
        today = model.today
        weekStartsOn = model.settings.weekStartsOn
        let now = Date()
        customEnd = now
        customStart = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -29, to: now) ?? now
    }

    var range: ClosedRange<LocalDate> {
        let statsPeriod: StatsPeriod = switch period {
        case .today: .today
        case .thisWeek: .thisWeek
        case .thisMonth: .thisMonth
        case .custom:
            .custom(Self.ordered(LocalDate(customStart, in: calendar), LocalDate(customEnd, in: calendar)))
        }
        return statsPeriod.range(today: today, weekStartsOn: weekStartsOn)
    }

    var rows: [StatsRow] {
        StatsCalculator.rows(StatsCalculator.totalsByLabel(totals, in: range), labels: labels)
    }

    var days: [DaySeconds] {
        StatsCalculator.dailySeconds(totals, in: range)
    }

    func name(of id: UUID?) -> String {
        guard let id else { return "No label" }
        return labels.first { $0.id == id }?.name ?? "Unknown label"
    }

    func colorHex(of id: UUID?) -> String? {
        id.flatMap { id in labels.first { $0.id == id }?.colorHex }
    }

    private static func ordered(_ first: LocalDate, _ second: LocalDate) -> ClosedRange<LocalDate> {
        min(first, second) ... max(first, second)
    }
}
