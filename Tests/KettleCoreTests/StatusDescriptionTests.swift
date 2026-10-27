import Foundation
@testable import KettleCore
import Testing

struct StatusDescriptionTests {
    let clock = FakeClock(.iso("2026-10-26T08:00:00Z"))

    func engine(_ tasks: [PlanTask]) -> TimerEngine {
        TimerEngine(
            plan: DayPlan(date: .ymd("2026-10-26"), tasks: tasks),
            settings: AppSettings(),
            clock: clock,
            calendar: .gregorian("UTC")
        )
    }

    @Test func describesTheTimeLeftNotTheSteam() {
        var engine = engine([PlanTask(title: "Write report", plannedMinutes: 45)])
        #expect(StatusDescription.text(engine: engine, now: clock.now) == "Kettle, nothing brewing")
        engine.start()
        clock.advance(by: 22 * 60 - 1)
        #expect(StatusDescription
            .text(engine: engine, now: clock.now) == "Kettle, Write report, brewing, 24 minutes left")
        clock.advance(by: 1)
        #expect(StatusDescription.minutes(engine: engine, now: clock.now) == 23)
        engine.pause()
        #expect(StatusDescription
            .text(engine: engine, now: clock.now) == "Kettle, Write report, paused, 23 minutes left")
    }

    @Test func overtimeAndDayComplete() {
        var engine = engine([PlanTask(title: "Tea", plannedMinutes: 5)])
        engine.start()
        clock.advance(by: 5 * 60)
        #expect(StatusDescription.text(engine: engine, now: clock.now) == "Kettle, Tea, brewing, time's up")
        clock.advance(by: 125)
        #expect(StatusDescription.minutes(engine: engine, now: clock.now) == -2)
        #expect(StatusDescription.text(engine: engine, now: clock.now) == "Kettle, Tea, brewing, 2 minutes over time")
        engine.done()
        #expect(StatusDescription.text(engine: engine, now: clock.now) == "Kettle, all brewed for today")
    }

    @Test(arguments: [
        (1, "1 minute left"),
        (5, "5 minutes left"),
        (0, "time's up"),
        (-1, "1 minute over time"),
        (-7, "7 minutes over time")
    ])
    func spokenMinutes(minutes: Int, expected: String) {
        #expect(StatusDescription.spoken(minutes: minutes) == expected)
    }

    @Test(arguments: [
        (1421.0, "23 minutes 41 seconds left"),
        (60.0, "1 minute left"),
        (1.0, "1 second left"),
        (0.4, "1 second left"),
        (0.0, "0 seconds over time"),
        (-42.5, "42 seconds over time"),
        (-61.0, "1 minute 1 second over time")
    ])
    func spokenCountdown(remaining: Double, expected: String) {
        #expect(StatusDescription.spoken(remaining: remaining) == expected)
    }
}
