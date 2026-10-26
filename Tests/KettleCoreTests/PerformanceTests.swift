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
