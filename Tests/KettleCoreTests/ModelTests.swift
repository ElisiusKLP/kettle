import Foundation
@testable import KettleCore
import Testing

struct LocalDateTests {
    @Test(arguments: ["2026-10-26", "2024-02-29", "0001-01-01", "9999-12-31"])
    func parsesAndPrintsValidDates(string: String) throws {
        let date = try #require(LocalDate(string))
        #expect(date.description == string)
    }

    @Test(arguments: [
        "2026-02-29",
        "2026-13-01",
        "2026-00-10",
        "2026-04-31",
        "2026-1-05",
        "26-01-05",
        "2026/01/05",
        "abcd-ef-gh",
        "",
        "2026-01-05-01",
        "1900-02-29",
    ])
    func rejectsInvalidDates(string: String) {
        #expect(LocalDate(string) == nil)
    }

    @Test func dayNumberStartsAtUnixEpoch() {
        #expect(LocalDate.ymd("1970-01-01").dayNumber == 0)
        #expect(LocalDate(dayNumber: 0) == .ymd("1970-01-01"))
        #expect(LocalDate.ymd("1969-12-31").dayNumber == -1)
    }

    @Test func dayNumberRoundTripsAcrossCenturies() {
        for number in stride(from: -800_000, through: 2_900_000, by: 997) {
            #expect(LocalDate(dayNumber: number).dayNumber == number)
        }
    }

    @Test func addsDaysAcrossMonthYearAndLeapBoundaries() {
        #expect(LocalDate.ymd("2026-10-31").adding(days: 1) == .ymd("2026-11-01"))
        #expect(LocalDate.ymd("2026-12-31").adding(days: 1) == .ymd("2027-01-01"))
        #expect(LocalDate.ymd("2024-02-28").adding(days: 1) == .ymd("2024-02-29"))
        #expect(LocalDate.ymd("2026-03-01").adding(days: -1) == .ymd("2026-02-28"))
        #expect(LocalDate.ymd("2026-10-26").adding(days: 365) == .ymd("2027-10-26"))
    }

    @Test func comparesChronologically() {
        #expect(LocalDate.ymd("2026-10-26") < .ymd("2026-10-27"))
        #expect(LocalDate.ymd("2026-09-30") < .ymd("2026-10-01"))
        #expect(LocalDate.ymd("2025-12-31") < .ymd("2026-01-01"))
    }

    @Test func dayOfADateDependsOnTheTimeZone() {
        let instant = Date.iso("2026-10-26T23:30:00Z")
        #expect(LocalDate(instant, in: .gregorian("UTC")) == .ymd("2026-10-26"))
        #expect(LocalDate(instant, in: .gregorian("Europe/Copenhagen")) == .ymd("2026-10-27"))
        #expect(LocalDate(instant, in: .gregorian("America/Los_Angeles")) == .ymd("2026-10-26"))
    }

    @Test func combinesWithATimeInTheCalendarsTimeZone() throws {
        let calendar = Calendar.gregorian("Europe/Copenhagen")
        let nine = try #require(LocalTime(hour: 9, minute: 0))
        #expect(LocalDate.ymd("2026-10-26").date(at: nine, in: calendar) == .iso("2026-10-26T08:00:00Z"))
        #expect(LocalDate.ymd("2026-07-01").date(in: calendar) == .iso("2026-06-30T22:00:00Z"))
    }

    @Test func monthKeyNamesTheSessionFile() {
        #expect(LocalDate.ymd("2026-03-09").monthKey == "2026-03")
    }

    @Test func codesAsAPlainString() throws {
        let data = try JSONEncoder().encode([LocalDate.ymd("2026-10-26")])
        #expect(String(bytes: data, encoding: .utf8) == #"["2026-10-26"]"#)
        #expect(try JSONDecoder().decode([LocalDate].self, from: data) == [.ymd("2026-10-26")])
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([LocalDate].self, from: Data(#"["2026-02-30"]"#.utf8))
        }
    }
}

struct LocalTimeTests {
    @Test func parsesAndPrints() throws {
        let time = try #require(LocalTime("09:05"))
        #expect(time.hour == 9)
        #expect(time.minute == 5)
        #expect(time.minutesSinceMidnight == 545)
        #expect(time.description == "09:05")
        #expect(LocalTime.midnight.description == "00:00")
    }

    @Test(arguments: ["24:00", "12:60", "9:05", "09:5", "0905", "", "-1:00", "ab:cd"])
    func rejectsInvalidTimes(string: String) {
        #expect(LocalTime(string) == nil)
    }

    @Test func comparesByTimeOfDay() throws {
        #expect(try #require(LocalTime("08:59")) < #require(LocalTime("09:00")))
    }

    @Test func codesAsAPlainString() throws {
        let data = try JSONEncoder().encode([#require(LocalTime("23:59"))])
        #expect(String(bytes: data, encoding: .utf8) == #"["23:59"]"#)
        #expect(try JSONDecoder().decode([LocalTime].self, from: data) == [#require(LocalTime("23:59"))])
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([LocalTime].self, from: Data(#"["25:00"]"#.utf8))
        }
    }
}

struct PlanTaskTests {
    @Test func clampsPlannedMinutesToRange() {
        #expect(PlanTask(title: "a", plannedMinutes: 0).plannedMinutes == 1)
        #expect(PlanTask(title: "a", plannedMinutes: 1000).plannedMinutes == 720)
        var task = PlanTask(title: "a", plannedMinutes: 30)
        task.plannedMinutes = -5
        #expect(task.plannedMinutes == 1)
        task.plannedMinutes = 721
        #expect(task.plannedMinutes == 720)
    }

    @Test func totalMinutesIncludesExtensions() {
        let task = PlanTask(title: "a", plannedMinutes: 45, extendedMinutes: 10)
        #expect(task.totalMinutes == 55)
    }

    @Test func decodingFillsDefaultsAndClamps() throws {
        let json = #"{"id":"5D2B7C11-0F3A-4B6E-8E21-3C9A0B1E2B01","title":"Old","plannedMinutes":5000}"#
        let task = try KettleJSON.makeDecoder().decode(PlanTask.self, from: Data(json.utf8))
        #expect(task.plannedMinutes == 720)
        #expect(task.status == .pending)
        #expect(task.extendedMinutes == 0)
        #expect(task.brewedSeconds == 0)
        #expect(task.brewingSince == nil)
        #expect(task.labelID == nil)
    }
}

struct AppSettingsTests {
    @Test func defaultsMatchTheSpec() {
        let settings = AppSettings()
        #expect(settings.extendMinutes == 10)
        #expect(settings.secondaryExtendMinutes == 5)
        #expect(settings.resizeStepMinutes == 5)
        #expect(!settings.autoStartNext)
        #expect(settings.menubarFormat == .iconAndTime)
        #expect(settings.timerPrecision == .seconds)
        #expect(settings.whistleSound)
        #expect(settings.notifyOnFinish)
        #expect(!settings.launchAtLogin)
        #expect(settings.weekStartsOn == .monday)
        #expect(!settings.overtime)
        #expect(settings.planLayout == .calendar)
        #expect(settings.calendarIntervalMinutes == 60)
    }

    @Test func calendarIntervalMustBeOneOfTheChoices() throws {
        let json = #"{"calendarIntervalMinutes":20,"planLayout":"list"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.calendarIntervalMinutes == 60)
        #expect(settings.planLayout == .list)
    }

    @Test func missingAndInvalidKeysFallBackToDefaults() throws {
        let json = #"{"extendMinutes":15,"menubarFormat":"sparkles","autoStartNext":"yes"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        var expected = AppSettings()
        expected.extendMinutes = 15
        #expect(settings == expected)
    }

    @Test func resizeStepIsAtLeastOneMinute() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"resizeStepMinutes":0}"#.utf8))
        #expect(settings.resizeStepMinutes == 1)
    }

    @Test func weekdayUsesCalendarNumbering() {
        #expect(Weekday.sunday.calendarWeekday == 1)
        #expect(Weekday.monday.calendarWeekday == 2)
        #expect(Weekday.saturday.calendarWeekday == 7)
    }
}

struct SessionTests {
    @Test func durationIsEndMinusStart() {
        let session = Session(
            taskID: UUID(), labelID: nil, start: .iso("2026-10-26T08:00:00Z"), end: .iso("2026-10-26T08:25:30Z")
        )
        #expect(session.duration == 25 * 60 + 30)
    }
}

struct ClockTests {
    @Test func systemClockReadsTheCurrentTime() {
        let before = Date()
        let now = SystemClock().now
        #expect(now >= before)
        #expect(now.timeIntervalSince(before) < 1)
    }

    @Test func fakeClockAdvancesOnlyWhenTold() {
        let clock = FakeClock()
        let start = clock.now
        clock.advance(by: 90)
        #expect(clock.now.timeIntervalSince(start) == 90)
    }
}

struct DayPlanTests {
    @Test func isIdentifiedByItsDate() {
        let plan = DayPlan(date: .ymd("2026-10-26"))
        #expect(plan.id == .ymd("2026-10-26"))
        #expect(plan.tasks.isEmpty)
        #expect(plan.startTime == nil)
    }
}
