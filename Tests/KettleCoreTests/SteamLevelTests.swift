import Foundation
@testable import KettleCore
import Testing

struct SteamLevelTests {
    @Test(arguments: [
        (100.0, SteamLevel.five), (80.01, .five), (80.0, .four), (60.01, .four), (60.0, .three),
        (40.01, .three), (40.0, .two), (20.01, .two), (20.0, .one), (0.01, .one), (0.0, .none),
        (-5.0, .none), (150.0, .five),
    ])
    func stepBoundaries(percentLeft: Double, expected: SteamLevel) {
        #expect(SteamLevel(remaining: percentLeft * 36, planned: 3600) == expected)
    }

    @Test func zeroLengthBlockHasNoSteam() {
        #expect(SteamLevel(remaining: 10, planned: 0) == .none)
    }

    @Test func levelsAreOrdered() {
        #expect(SteamLevel.allCases == SteamLevel.allCases.sorted())
        #expect(SteamLevel.none < .five)
    }

    @Test func iconStatesCoverEveryCase() {
        let states = IconState.allCases
        #expect(states.count == 14)
        #expect(Set(states).count == states.count)
        #expect(!states.contains(.brewing(.none)))
    }

    // MARK: States from the timer

    let calendar = Calendar.gregorian("UTC")
    let start = Date.iso("2026-10-26T09:00:00Z")

    func engine(_ minutes: Int = 45, clock: FakeClock) -> TimerEngine {
        TimerEngine(
            plan: DayPlan(date: .ymd("2026-10-26"), tasks: [PlanTask(title: "Tea", plannedMinutes: minutes)]),
            settings: AppSettings(),
            clock: clock,
            calendar: calendar
        )
    }

    @Test func idleBeforeStarting() {
        let clock = FakeClock(start)
        #expect(engine(clock: clock).iconState(at: start) == .idle)
    }

    @Test func pausedFreezesTheStep() {
        let clock = FakeClock(start)
        var engine = engine(clock: clock)
        engine.start()
        clock.advance(by: 20 * 60) // 25 of 45 minutes left: 55%
        engine.pause()
        #expect(engine.iconState(at: clock.now) == .paused(.three))
        clock.advance(by: 3 * 3600)
        #expect(engine.iconState(at: clock.now) == .paused(.three))
    }

    @Test func pausedInOvertimeShowsNoSteam() {
        let clock = FakeClock(start)
        var engine = engine(clock: clock)
        engine.start()
        clock.advance(by: 50 * 60)
        engine.pause()
        #expect(engine.iconState(at: clock.now) == .paused(.none))
    }

    @Test func overtimeWhistles() {
        let clock = FakeClock(start)
        var engine = engine(clock: clock)
        engine.start()
        clock.advance(by: 45 * 60)
        #expect(engine.iconState(at: clock.now) == .whistling)
        clock.advance(by: 3600)
        #expect(engine.iconState(at: clock.now) == .whistling)
    }

    @Test func dayCompleteWhenEverythingIsDone() {
        let clock = FakeClock(start)
        var engine = engine(clock: clock)
        engine.start()
        clock.advance(by: 60)
        engine.done()
        #expect(engine.iconState(at: clock.now) == .dayComplete)
    }

    /// Ticks once a second through a whole block and into overtime, counting icon swaps.
    @Test(arguments: [1, 2, 7, 45, 90, 720])
    func oneBlockCausesAtMostSixImageChanges(minutes: Int) {
        let clock = FakeClock(start)
        var engine = engine(minutes, clock: clock)
        var shown = engine.iconState(at: clock.now)
        engine.start()
        var changes = 0
        for _ in 0 ... (minutes * 60 + 120) {
            let state = engine.iconState(at: clock.now)
            if state != shown {
                changes += 1
                shown = state
            }
            clock.advance(by: 1)
        }
        #expect(changes <= 6)
        #expect(shown == .whistling)
    }

    @Test func stepsChangeEveryFifthOfTheBlock() {
        let clock = FakeClock(start)
        var engine = engine(2, clock: clock)
        engine.start()
        var seen: [IconState] = []
        for _ in 0 ... 120 {
            let state = engine.iconState(at: clock.now)
            if seen.last != state {
                seen.append(state)
            }
            clock.advance(by: 1)
        }
        #expect(seen == [
            .brewing(.five),
            .brewing(.four),
            .brewing(.three),
            .brewing(.two),
            .brewing(.one),
            .whistling,
        ])
    }
}
