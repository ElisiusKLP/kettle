import Foundation
@testable import KettleCore
import Testing

struct CountdownFormatterTests {
    @Test(arguments: [
        (1421.0, "23:41"), (1420.2, "23:41"), (1.0, "00:01"), (0.3, "00:01"), (59.5, "01:00"), (600.0, "10:00"),
        (3600.0, "1:00:00"), (3725.0, "1:02:05"), (43200.0, "12:00:00"),
        (0.0, "+00:00"), (-0.9, "+00:00"), (-42.0, "+00:42"), (-42.7, "+00:42"), (-3605.0, "+1:00:05"),
        (1e12, "99:59:59"), (-1e12, "+99:59:59"), (.infinity, "99:59:59"), (.nan, "99:59:59"),
    ])
    func secondsPrecision(remaining: Double, expected: String) {
        #expect(CountdownFormatter.string(remaining: remaining, precision: .seconds) == expected)
    }

    @Test(arguments: [
        (1421.0, "24m"), (1380.0, "23m"), (1.0, "1m"), (3600.0, "1h 00m"), (3601.0, "1h 01m"), (5400.0, "1h 30m"),
        (0.0, "+0m"), (-59.0, "+0m"), (-60.0, "+1m"), (-3900.0, "+1h 05m"), (1e12, "99h 59m"),
    ])
    func minutesPrecision(remaining: Double, expected: String) {
        #expect(CountdownFormatter.string(remaining: remaining, precision: .minutes) == expected)
    }
}

struct MenubarTickerTests {
    let clock = FakeClock(.iso("2026-10-26T08:00:00Z"))

    func engine(_ minutes: Int = 45, title: String = "Write report", start: Bool = true) -> TimerEngine {
        var engine = TimerEngine(
            plan: DayPlan(date: .ymd("2026-10-26"), tasks: [PlanTask(title: title, plannedMinutes: minutes)]),
            settings: AppSettings(), clock: clock, calendar: .gregorian("UTC")
        )
        if start {
            engine.start()
        }
        return engine
    }

    @Test func firstUpdateReportsEverythingThenOnlyChanges() {
        var ticker = MenubarTicker()
        let engine = engine()
        let first = ticker.update(engine: engine, now: clock.now, settings: AppSettings())
        #expect(first == .init(icon: .brewing(.five), title: "45:00"))
        #expect(ticker.update(engine: engine, now: clock.now, settings: AppSettings()) == .init())
        clock.advance(by: 1)
        #expect(ticker.update(engine: engine, now: clock.now, settings: AppSettings()) == .init(title: "44:59"))
    }

    @Test func formatsFollowTheSetting() {
        var settings = AppSettings()
        let engine = engine()
        settings.menubarFormat = .iconOnly
        #expect(MenubarTicker.title(engine: engine, now: clock.now, settings: settings).isEmpty)
        settings.menubarFormat = .iconTitleAndTime
        #expect(MenubarTicker.title(engine: engine, now: clock.now, settings: settings) == "Write report 45:00")
        settings.timerPrecision = .minutes
        #expect(MenubarTicker.title(engine: engine, now: clock.now, settings: settings) == "Write report 45m")
    }

    @Test func idleShowsOnlyTheIcon() {
        var ticker = MenubarTicker()
        let update = ticker.update(engine: engine(start: false), now: clock.now, settings: AppSettings())
        #expect(update == .init(icon: .idle, title: ""))
    }

    @Test func resetReportsEverythingAgain() {
        var ticker = MenubarTicker()
        let engine = engine()
        _ = ticker.update(engine: engine, now: clock.now, settings: AppSettings())
        ticker.reset()
        #expect(ticker.update(engine: engine, now: clock.now, settings: AppSettings()).icon == .brewing(.five))
    }

    @Test func titleChangesOncePerSecondAndIconOncePerStep() {
        var ticker = MenubarTicker()
        let engine = engine(2)
        var titles = 0
        var icons = 0
        for _ in 0 ..< 1205 { // 2 minutes in 0.1 s steps, then just into overtime
            let update = ticker.update(engine: engine, now: clock.now, settings: AppSettings())
            titles += update.title == nil ? 0 : 1
            icons += update.icon == nil ? 0 : 1
            clock.advance(by: 0.1)
        }
        #expect(titles == 121) // 02:00 ... 00:01, +00:00
        #expect(icons == 6)
    }

    // MARK: Tick scheduling

    @Test func nothingTicksWhenIdleOrPaused() {
        var engine = engine(start: false)
        #expect(MenubarTicker.delayUntilNextChange(engine: engine, now: clock.now, precision: .seconds) == nil)
        engine.start()
        clock.advance(by: 10)
        engine.pause()
        #expect(MenubarTicker.delayUntilNextChange(engine: engine, now: clock.now, precision: .seconds) == nil)
    }

    @Test(arguments: [
        // (seconds into a 45-minute block, precision, expected delay)
        (0.0, TimerPrecision.seconds, 1.0), (0.3, .seconds, 0.7), (10.75, .seconds, 0.25),
        (0.0, .minutes, 60.0), (10.0, .minutes, 50.0), (59.5, .minutes, 0.5),
        // Overtime counts up from the whistle at 2700 s.
        (2700.0, .seconds, 1.0), (2700.4, .seconds, 0.6), (2730.0, .minutes, 30.0),
    ])
    func ticksAlignToTheCountdownBoundaries(elapsed: Double, precision: TimerPrecision, expected: Double) throws {
        let engine = engine()
        let now = clock.now + elapsed
        let delay = try #require(MenubarTicker.delayUntilNextChange(engine: engine, now: now, precision: precision))
        #expect(abs(delay - expected - 0.005) < 0.0001)
        // Just after the tick, the countdown shows a new value.
        let before = try CountdownFormatter.string(
            remaining: #require(engine.remainingSeconds(at: now)),
            precision: precision
        )
        let after = try CountdownFormatter.string(
            remaining: #require(engine.remainingSeconds(at: now + delay)),
            precision: precision
        )
        #expect(before != after)
    }

    @Test func atMostOneWakeUpPerSecondOrMinute() throws {
        for (precision, unit) in [(TimerPrecision.seconds, 1.0), (.minutes, 60.0)] {
            let engine = engine()
            var now = clock.now
            var wakeUps = 0
            while now < clock.now + 3000 {
                now += try #require(MenubarTicker.delayUntilNextChange(engine: engine, now: now, precision: precision))
                wakeUps += 1
            }
            #expect(Double(wakeUps) <= 3000 / unit + 1)
        }
    }
}
