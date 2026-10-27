import Foundation
@testable import KettleCore
import Testing

struct TimerControlsTests {
    let clock = FakeClock(.iso("2026-10-26T08:00:00Z"))

    func engine() -> TimerEngine {
        TimerEngine(
            plan: DayPlan(date: .ymd("2026-10-26"), tasks: [
                PlanTask(title: "A", plannedMinutes: 10),
                PlanTask(title: "B", plannedMinutes: 10),
            ]),
            settings: AppSettings(), clock: clock, calendar: .gregorian("UTC")
        )
    }

    @Test func followTheTimer() {
        var engine = engine()
        var controls = TimerControls(engine: engine)
        #expect(controls.toggle == .start)
        #expect(!controls.hasActiveTask)
        #expect(controls.keepBrewingTaskID == nil)

        engine.start()
        controls = TimerControls(engine: engine)
        #expect(controls.toggle == .pause)
        #expect(controls.hasActiveTask)
        #expect(controls.keepBrewingTaskID == engine.plan.tasks[0].id)

        clock.advance(by: 60)
        engine.pause()
        controls = TimerControls(engine: engine)
        #expect(controls.toggle == .resume)
        #expect(controls.keepBrewingTaskID == nil)

        engine.done()
        controls = TimerControls(engine: engine)
        #expect(controls.toggle == .start)
        #expect(controls.keepBrewingTaskID == engine.plan.tasks[0].id)

        engine.start()
        engine.done()
        controls = TimerControls(engine: engine)
        #expect(controls.toggle == nil)
        #expect(controls.keepBrewingTaskID == engine.plan.tasks[1].id)
    }

    @Test func taskMenusOfferWhatApplies() {
        var engine = engine()
        engine.start()
        let tasks = engine.plan.tasks
        func actions(_ index: Int, isTimerDay: Bool = true) -> [TimerControls.TaskAction] {
            TimerControls.actions(
                for: engine.plan.tasks[index], isTimerDay: isTimerDay, reopenableID: engine.reopenableID
            )
        }
        #expect(actions(0) == [.pause, .done, .keepBrewing, .skip])
        #expect(actions(1) == [.start, .done, .skip])
        #expect(actions(1, isTimerDay: false) == [.skip])

        engine.pause()
        #expect(actions(0) == [.resume, .done, .skip])

        engine.done()
        #expect(actions(0) == [.keepBrewing])
        #expect(actions(0, isTimerDay: false).isEmpty)
        engine.skip(taskID: tasks[1].id)
        #expect(actions(1).isEmpty)
    }
}
