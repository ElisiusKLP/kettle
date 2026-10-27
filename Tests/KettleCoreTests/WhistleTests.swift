import Foundation
@testable import KettleCore
import Testing

struct WhistleTests {
    let clock = FakeClock(.iso("2026-10-26T08:00:00Z"))

    func engine(start: Bool = true) -> TimerEngine {
        var engine = TimerEngine(
            plan: DayPlan(date: .ymd("2026-10-26"), tasks: [PlanTask(title: "Write report", plannedMinutes: 45)]),
            settings: AppSettings(), clock: clock, calendar: .gregorian("UTC")
        )
        if start {
            engine.start()
        }
        return engine
    }

    @Test func requestFiresWhenTheBlockRunsOut() throws {
        clock.advance(by: 600)
        let engine = engine()
        clock.advance(by: 300)
        let request = try #require(Whistle.request(engine: engine, now: clock.now, settings: AppSettings()))
        #expect(request.fireDate == clock.now + 40 * 60) // started 5 minutes ago
        #expect(request.title == "Whistle!")
        #expect(request.body == "\u{201C}Write report\u{201D} is done.")
        #expect(request.playsSound)
        #expect(request.taskID == engine.activeTask?.id)
    }

    @Test func keepBrewingMovesTheRequest() throws {
        var engine = engine()
        let before = try #require(Whistle.request(engine: engine, now: clock.now, settings: AppSettings()))
        engine.keepBrewing(minutes: 10)
        let after = try #require(Whistle.request(engine: engine, now: clock.now, settings: AppSettings()))
        #expect(after.fireDate.timeIntervalSince(before.fireDate) == 600)
    }

    @Test func noRequestWhenOffIdlePausedOrAlreadyOverdue() {
        var settings = AppSettings()
        settings.notifyOnFinish = false
        #expect(Whistle.request(engine: engine(), now: clock.now, settings: settings) == nil)
        #expect(Whistle.request(engine: engine(start: false), now: clock.now, settings: AppSettings()) == nil)
        var paused = engine()
        clock.advance(by: 60)
        paused.pause()
        #expect(Whistle.request(engine: paused, now: clock.now, settings: AppSettings()) == nil)
        let overdue = engine()
        clock.advance(by: 46 * 60)
        #expect(Whistle.request(engine: overdue, now: clock.now, settings: AppSettings()) == nil)
    }

    @Test func soundFollowsTheSettings() throws {
        var settings = AppSettings()
        settings.whistleSound = false
        let request = try #require(Whistle.request(engine: engine(), now: clock.now, settings: settings))
        #expect(!request.playsSound)
        #expect(!Whistle.playsSoundInApp(settings, notificationsCanPlaySound: false))
        settings.whistleSound = true
        #expect(!Whistle.playsSoundInApp(settings, notificationsCanPlaySound: true))
        // Notifications not allowed, or their sound turned off in System Settings.
        #expect(Whistle.playsSoundInApp(settings, notificationsCanPlaySound: false))
        settings.notifyOnFinish = false
        #expect(Whistle.playsSoundInApp(settings, notificationsCanPlaySound: true))
    }

    @Test func doneIsOfferedOnlyInOvertimeMode() throws {
        var settings = AppSettings()
        #expect(try !#require(Whistle.request(engine: engine(), now: clock.now, settings: settings)).offersDone)
        settings.overtime = true
        #expect(try #require(Whistle.request(engine: engine(), now: clock.now, settings: settings)).offersDone)
    }

    @Test func actionTitlesUseTheExtendAmounts() {
        var settings = AppSettings()
        settings.extendMinutes = 15
        settings.secondaryExtendMinutes = 3
        let titles = Whistle.keepBrewingTitles(settings)
        #expect(titles.main == "Keep brewing +15m")
        #expect(titles.secondary == "+3m")
    }

    // MARK: Wiggle trigger

    @Test func startedWhistlingOnlyOnTheTickThatRunsOut() throws {
        var ticker = MenubarTicker()
        let engine = engine()
        var starts = 0
        for _ in 0 ..< 50 * 60 {
            if ticker.update(engine: engine, now: clock.now, settings: AppSettings()).startedWhistling {
                starts += 1
                #expect(try #require(engine.remainingSeconds(at: clock.now)) <= 0)
            }
            clock.advance(by: 1)
        }
        #expect(starts == 1)
    }

    @Test func noWiggleWhenAlreadyOverdueAtLaunch() {
        var ticker = MenubarTicker()
        let engine = engine()
        clock.advance(by: 50 * 60)
        let update = ticker.update(engine: engine, now: clock.now, settings: AppSettings())
        #expect(update.icon == .whistling)
        #expect(!update.startedWhistling)
    }
}
