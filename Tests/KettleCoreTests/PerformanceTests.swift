import Foundation
@testable import KettleCore
import Testing

struct PerformanceTests {
    /// The best of several runs, so one slow scheduling hiccup doesn't fail the test.
    func fastest(runs: Int = 10, _ work: () -> Void) -> Duration {
        let clock = ContinuousClock()
        return (0 ..< runs).map { _ in clock.measure(work) }.min()!
    }

    @Test func aggregatingAYearOfDailyTotalsTakesUnder20ms() {
        let labels = (0 ..< 6).map { _ in UUID() as UUID? } + [nil]
        let end = LocalDate.ymd("2026-10-26")
        let start = end.adding(days: -364)
        var totals = DailyTotals()
        for offset in 0 ..< 365 {
            for (index, label) in labels.enumerated() {
                var day = LabelTotals()
                day.seconds = 600 * (index + 1)
                day.sessions = 2
                day.tasksDone = 1
                day.plannedMinutes = 30
                day.doneSeconds = 1900
                totals.days[start.adding(days: offset), default: [:]][label] = day
            }
        }

        var result: [UUID?: LabelTotals] = [:]
        var series: [DaySeconds] = []
        let elapsed = fastest {
            result = StatsCalculator.totalsByLabel(totals, in: start ... end)
            series = StatsCalculator.dailySeconds(totals, in: start ... end)
        }

        #expect(result.count == labels.count)
        #expect(result[nil]?.seconds == 365 * 600 * labels.count)
        #expect(series.count == 365)
        #expect(elapsed < .milliseconds(20), "took \(elapsed)")
    }
}

extension PerformanceTests {
    static func brewingEngine(clock: FakeClock) -> TimerEngine {
        var engine = TimerEngine(
            plan: DayPlan(date: .ymd("2026-10-26"), tasks: [
                PlanTask(
                    title: "Write report",
                    labelID: UUID(),
                    plannedMinutes: 45,
                    notes: "A note long enough to live on the heap"
                ),
                PlanTask(title: "Emails", plannedMinutes: 20),
            ]),
            settings: AppSettings(), clock: clock, calendar: .gregorian("UTC")
        )
        engine.start()
        return engine
    }

    /// What the app does on each timer fire, once a second for 50 minutes: through every steam
    /// step and into overtime.
    /// - Returns: how many ticks changed the menubar.
    static func tick(
        _ engine: TimerEngine,
        _ ticker: inout MenubarTicker,
        clock: FakeClock,
        settings: AppSettings
    ) -> Int {
        var changes = 0
        for _ in 0 ..< 3000 {
            clock.advance(by: 1)
            let update = ticker.update(engine: engine, now: clock.now, settings: settings)
            if update.title != nil || update.icon != nil {
                changes += 1
            }
            _ = MenubarTicker.delayUntilNextChange(engine: engine, now: clock.now, precision: settings.timerPrecision)
        }
        return changes
    }

    /// Unoptimised builds allocate inside unspecialised generic calls (such as
    /// `firstIndex(where:)`), so this only means something for optimised code. Run it with
    /// `make test-release` (part of `make memcheck` and CI).
    static let isOptimized: Bool = {
        #if DEBUG
            false
        #else
            true
        #endif
    }()

    @Test(
        .enabled(if: AllocationCounter.isAvailable),
        .enabled(if: isOptimized, "allocation counts are only meaningful in optimised builds: make test-release")
    )
    func steadyStateTickingDoesNotAllocate() {
        let settings = AppSettings()
        // Run every code path once first, so one-time lazy initialisation isn't counted.
        let warmUpClock = FakeClock(.iso("2026-10-26T08:00:00Z"))
        var warmUpTicker = MenubarTicker()
        _ = Self.tick(Self.brewingEngine(clock: warmUpClock), &warmUpTicker, clock: warmUpClock, settings: settings)

        let clock = FakeClock(.iso("2026-10-26T08:00:00Z"))
        let engine = Self.brewingEngine(clock: clock)
        var ticker = MenubarTicker()
        _ = ticker.update(engine: engine, now: clock.now, settings: settings) // first display
        var changes = 0
        let allocations = AllocationCounter.count {
            changes = Self.tick(engine, &ticker, clock: clock, settings: settings)
        }
        #expect(changes == 3000)
        #expect(allocations == 0)
    }

    @Test(.enabled(if: AllocationCounter.isAvailable))
    func allocationCounterSeesAllocations() {
        var array: [Int] = []
        let allocations = AllocationCounter.count {
            array = Array(repeating: 1, count: Int.random(in: 100 ... 200))
        }
        #expect(array.count >= 100)
        #expect(allocations >= 1)
    }
}
