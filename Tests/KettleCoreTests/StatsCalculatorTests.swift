import Foundation
@testable import KettleCore
import Testing

struct StatsCalculatorTests {
    let calendar = Calendar.gregorian("Europe/Copenhagen")
    let work = Label(name: "work", colorHex: "#C8743A")
    let health = Label(name: "health", colorHex: "#2E8B7A", isArchived: true)

    func session(_ start: String, _ end: String, label: UUID? = nil) -> Session {
        Session(taskID: UUID(), labelID: label, start: .iso(start), end: .iso(end))
    }

    // MARK: Midnight splitting

    @Test func sessionWithinADayIsOnePart() {
        let parts = StatsCalculator.split(session("2026-10-26T08:00:00Z", "2026-10-26T08:45:00Z"), calendar: calendar)
        #expect(parts.map(\.date) == [.ymd("2026-10-26")])
        #expect(parts.map(\.seconds) == [2700])
    }

    @Test func sessionCrossingMidnightIsSplitInLocalTime() {
        // 23:30 to 00:15 in Copenhagen (UTC+1 in late October).
        let parts = StatsCalculator.split(session("2026-10-26T22:30:00Z", "2026-10-26T23:15:00Z"), calendar: calendar)
        #expect(parts.map(\.date) == [.ymd("2026-10-26"), .ymd("2026-10-27")])
        #expect(parts.map(\.seconds) == [1800, 900])
    }

    @Test func longSessionSpansWholeDays() {
        let parts = StatsCalculator.split(session("2026-10-26T22:00:00Z", "2026-10-28T23:30:00Z"), calendar: calendar)
        #expect(parts.map(\.date) == [.ymd("2026-10-26"), .ymd("2026-10-27"), .ymd("2026-10-28"), .ymd("2026-10-29")])
        #expect(parts.map(\.seconds) == [3600, 86400, 86400, 1800])
    }

    @Test func daylightSavingDayHas25Hours() {
        // 25 October 2026: clocks go back in Copenhagen, so the day lasts 25 hours.
        let parts = StatsCalculator.split(session("2026-10-24T22:00:00Z", "2026-10-25T23:00:00Z"), calendar: calendar)
        #expect(parts.map(\.date) == [.ymd("2026-10-25")])
        #expect(parts.map(\.seconds) == [25 * 3600])
    }

    @Test func emptyOrBackwardsSessionHasNoParts() {
        #expect(StatsCalculator.split(session("2026-10-26T08:00:00Z", "2026-10-26T08:00:00Z"), calendar: calendar)
            .isEmpty)
        #expect(StatsCalculator.split(session("2026-10-26T09:00:00Z", "2026-10-26T08:00:00Z"), calendar: calendar)
            .isEmpty)
    }

    // MARK: Ranges

    @Test func todayIsOneDay() {
        let today = LocalDate.ymd("2026-10-28")
        #expect(StatsPeriod.today.range(today: today, weekStartsOn: .monday) == today ... today)
    }

    @Test(arguments: [
        (Weekday.monday, "2026-10-26", "2026-11-01"),
        (Weekday.sunday, "2026-10-25", "2026-10-31"),
        (Weekday.wednesday, "2026-10-28", "2026-11-03"),
        (Weekday.thursday, "2026-10-22", "2026-10-28"),
    ])
    func weekRespectsTheFirstWeekday(first: Weekday, start: String, end: String) {
        let range = StatsPeriod.thisWeek.range(today: .ymd("2026-10-28"), weekStartsOn: first)
        #expect(range == LocalDate.ymd(start) ... LocalDate.ymd(end))
    }

    @Test(arguments: [
        ("2026-10-28", "2026-10-01", "2026-10-31"),
        ("2024-02-10", "2024-02-01", "2024-02-29"),
        ("2026-02-28", "2026-02-01", "2026-02-28"),
        ("2026-12-01", "2026-12-01", "2026-12-31")
    ])
    func monthIsTheWholeCalendarMonth(today: String, start: String, end: String) {
        let range = StatsPeriod.thisMonth.range(today: .ymd(today), weekStartsOn: .monday)
        #expect(range == LocalDate.ymd(start) ... LocalDate.ymd(end))
    }

    @Test func customRangeIsUsedAsIs() {
        let range = LocalDate.ymd("2026-01-05") ... LocalDate.ymd("2026-03-01")
        #expect(StatsPeriod.custom(range).range(today: .ymd("2026-10-28"), weekStartsOn: .monday) == range)
    }

    @Test func weekdaysMatchTheCalendar() {
        let gregorian = Calendar.gregorian("UTC")
        for offset in -400 ... 400 {
            let date = LocalDate.ymd("2026-10-28").adding(days: offset)
            #expect(date.weekday == gregorian.component(.weekday, from: date.date(in: gregorian)))
        }
    }

    // MARK: Aggregation

    func sampleTotals() -> DailyTotals {
        var totals = DailyTotals()
        totals[.ymd("2026-10-26"), work.id].seconds = 3600
        totals[.ymd("2026-10-26"), work.id].plannedMinutes = 45
        totals[.ymd("2026-10-26"), work.id].tasksDone = 1
        totals[.ymd("2026-10-27"), work.id].seconds = 1800
        totals[.ymd("2026-10-27"), health.id].seconds = 2400
        totals[.ymd("2026-10-27"), nil].seconds = 600
        totals[.ymd("2026-11-02"), work.id].seconds = 999
        return totals
    }

    @Test func aggregatesByLabelWithinTheRange() {
        let byLabel = StatsCalculator.totalsByLabel(sampleTotals(), in: .ymd("2026-10-26") ... .ymd("2026-11-01"))
        #expect(byLabel[work.id]?.seconds == 5400)
        #expect(byLabel[work.id]?.plannedMinutes == 45)
        #expect(byLabel[work.id]?.tasksDone == 1)
        #expect(byLabel[health.id]?.seconds == 2400)
        #expect(byLabel[nil]?.seconds == 600)
        #expect(byLabel.count == 3)
    }

    @Test func rangeOutsideTheDataIsEmpty() {
        #expect(StatsCalculator.totalsByLabel(sampleTotals(), in: .ymd("2025-01-01") ... .ymd("2025-12-31")).isEmpty)
    }

    @Test func dailySeriesHasEveryDayInTheRange() {
        let days = StatsCalculator.dailySeconds(sampleTotals(), in: .ymd("2026-10-25") ... .ymd("2026-10-28"))
        #expect(days.map(\.date) == [.ymd("2026-10-25"), .ymd("2026-10-26"), .ymd("2026-10-27"), .ymd("2026-10-28")])
        #expect(days[0].secondsByLabel.isEmpty)
        #expect(days[2].secondsByLabel == [work.id: 1800, health.id: 2400, nil: 600])
    }

    @Test func rowsKeepArchivedLabelsAndSortByTime() {
        let byLabel = StatsCalculator.totalsByLabel(sampleTotals(), in: .ymd("2026-10-26") ... .ymd("2026-11-01"))
        let rows = StatsCalculator.rows(byLabel, labels: [work, health])
        #expect(rows.map(\.kind) == [.label(work), .label(health), .unlabeled])
        #expect(rows.map(\.totals.seconds) == [5400, 2400, 600])
        guard case let .label(archived) = rows[1].kind else {
            Issue.record("expected a label")
            return
        }
        #expect(archived.isArchived)
        #expect(rows.map(\.labelID) == [work.id, health.id, nil])
    }

    @Test func rowsForDeletedLabelsAreMarkedUnknown() {
        let deleted = UUID()
        var totals = DailyTotals()
        totals[.ymd("2026-10-26"), deleted].seconds = 60
        let rows = StatsCalculator.rows(
            StatsCalculator.totalsByLabel(totals, in: .ymd("2026-10-26") ... .ymd("2026-10-26")),
            labels: [work]
        )
        #expect(rows.map(\.kind) == [.unknown(deleted)])
        #expect(rows.first?.labelID == deleted)
    }

    @Test func tiesSortByNameThenUnlabeledThenUnknown() {
        let unknown = UUID()
        let alpha = Label(name: "Alpha", colorHex: "#000000")
        let byLabel: [UUID?: LabelTotals] = [
            unknown: seconds(60), nil: seconds(60), work.id: seconds(60), alpha.id: seconds(60),
            health.id: LabelTotals(),
        ]
        let rows = StatsCalculator.rows(byLabel, labels: [work, alpha, health])
        #expect(rows.map(\.kind) == [.label(alpha), .label(work), .unlabeled, .unknown(unknown)])
    }

    func seconds(_ value: Int) -> LabelTotals {
        var totals = LabelTotals()
        totals.seconds = value
        return totals
    }
}

struct DurationTextTests {
    @Test(arguments: [
        (0, "0m"),
        (29, "0m"),
        (30, "1m"),
        (2700, "45m"),
        (3570, "1h 00m"),
        (3600, "1h 00m"),
        (11100, "3h 05m"),
        (-5, "0m"),
        (360_000, "100h 00m"),
    ])
    func formatsShortDurations(seconds: Int, expected: String) {
        #expect(DurationText.short(seconds: seconds) == expected)
    }
}
