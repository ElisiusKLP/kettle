import Foundation
@testable import KettleCore
import Testing

/// Keep brewing, overtime, sleep/wake and plan edits.
extension TimerEngineTests {
    // MARK: Keep brewing and overtime

    @Test func keepBrewingExtendsTheTaskAndShiftsLaterBlocks() throws {
        var engine = engine()
        engine.start()
        clock.advance(by: minutes(40))
        engine.keepBrewing(minutes: engine.settings.extendMinutes)
        #expect(engine.activeTask?.extendedMinutes == 10)
        #expect(engine.activeTask?.plannedMinutes == 45)
        #expect(engine.remainingSeconds(at: clock.now) == minutes(15))

        let blocks = PlanEngine.schedule(for: engine.plan, from: nine, now: clock.now)
        #expect(blocks[1].start == nine + minutes(55))

        clock.advance(by: minutes(15))
        let session = try #require(engine.done().first)
        #expect(session.extensionsMinutes == 10)
    }

    @Test func extensionsAreCountedPerSession() throws {
        var engine = engine()
        engine.start()
        engine.keepBrewing(minutes: 10)
        clock.advance(by: minutes(5))
        let first = try #require(engine.pause().first)
        engine.start()
        engine.keepBrewing(minutes: 5)
        clock.advance(by: minutes(5))
        let second = try #require(engine.pause().first)
        #expect(first.extensionsMinutes == 10)
        #expect(second.extensionsMinutes == 5)
        #expect(engine.activeTask?.extendedMinutes == 15)
    }

    @Test func keepBrewingOnlyAppliesWhileBrewing() {
        var engine = engine()
        engine.keepBrewing(minutes: 10)
        #expect(engine.plan.tasks.allSatisfy { $0.extendedMinutes == 0 })
        engine.start()
        clock.advance(by: 60)
        engine.pause()
        engine.keepBrewing(minutes: 10)
        engine.start()
        engine.keepBrewing(minutes: 0)
        engine.keepBrewing(minutes: -5)
        #expect(engine.activeTask?.extendedMinutes == 0)
    }

    @Test func atZeroTheKettleWhistlesAndOvertimeCounts() throws {
        var engine = engine()
        engine.start()
        clock.advance(by: minutes(45) - 1)
        #expect(engine.iconState(at: clock.now) == .brewing(.one))
        clock.advance(by: 1)
        #expect(engine.iconState(at: clock.now) == .whistling)
        clock.advance(by: 42)
        #expect(engine.remainingSeconds(at: clock.now) == -42)
        let session = try #require(engine.done().first)
        #expect(session.duration == minutes(45) + 42)
    }

    @Test func keepBrewingInOvertimeGivesAboutTheFullAmountFromNow() {
        var engine = engine()
        engine.start()
        clock.advance(by: minutes(45 + 30) + 20) // 30 min 20 s overdue
        engine.keepBrewing(minutes: 10)
        #expect(engine.activeTask?.extendedMinutes == 40)
        #expect(engine.remainingSeconds(at: clock.now) == minutes(10) - 20)
        // Steam is remaining / (planned + extensions): 9:40 of 85 minutes is the lowest step.
        #expect(engine.iconState(at: clock.now) == .brewing(.one))
    }

    @Test func whistleDateIsWhenTheBrewingBlockRunsOut() {
        var engine = engine()
        #expect(engine.whistleDate(at: nine) == nil)
        engine.start()
        clock.advance(by: minutes(5))
        #expect(engine.whistleDate(at: clock.now) == nine + minutes(45))
        clock.advance(by: minutes(40))
        #expect(engine.whistleDate(at: clock.now) == nil)
        engine.pause()
        #expect(engine.whistleDate(at: clock.now) == nil)
    }

    // MARK: Sleep and wake

    @Test func remainingTimeIsCorrectAfterSleep() {
        var engine = engine()
        engine.start()
        clock.advance(by: minutes(10))
        let beforeSleep = engine.iconState(at: clock.now)
        // The Mac sleeps for 20 minutes; nothing ticks. On wake everything is recomputed.
        clock.advance(by: minutes(20))
        #expect(beforeSleep == .brewing(.four))
        #expect(engine.remainingSeconds(at: clock.now) == minutes(15))
        #expect(engine.iconState(at: clock.now) == .brewing(.two))
    }

    @Test func sleepingPastTheEndWakesUpWhistling() throws {
        var engine = engine()
        engine.start()
        clock.advance(by: minutes(180))
        #expect(engine.iconState(at: clock.now) == .whistling)
        #expect(engine.remainingSeconds(at: clock.now) == minutes(-135))
        let session = try #require(engine.done().first)
        #expect(session.duration == minutes(180))
    }

    @Test func clockGoingBackwardsNeverRecordsNegativeTime() {
        var engine = engine()
        engine.start()
        clock.advance(by: -minutes(5))
        #expect(engine.pause().isEmpty)
        #expect(engine.activeTask?.brewedSeconds == 0)
        #expect(engine.remainingSeconds(at: clock.now) == minutes(45))
    }

    @Test func veryShortSessionsAreNotRecorded() {
        var engine = engine()
        engine.start()
        clock.advance(by: 0.4)
        #expect(engine.pause().isEmpty)
    }

    // MARK: Editing and repair

    @Test func removingTheBrewingTaskClosesItsSession() throws {
        var engine = engine()
        engine.start()
        clock.advance(by: minutes(7))
        let id = engine.plan.tasks[0].id
        let closed = engine.editPlan { PlanEngine.remove(taskID: id, from: &$0) }
        #expect(try #require(closed.first).duration == minutes(7))
        #expect(engine.activeTask == nil)
    }

    @Test func otherEditsKeepTheBrewingTask() {
        var engine = engine()
        engine.start()
        let closed = engine.editPlan { plan in
            PlanEngine.move(in: &plan, fromOffsets: [0], toOffset: 3)
            PlanEngine.adjust(taskID: plan.tasks[0].id, byMinutes: 5, in: &plan)
        }
        #expect(closed.isEmpty)
        #expect(engine.activeTask?.title == "Write")
        #expect(engine.activeIndex == 2)
    }

    @Test func loadingRepairsInconsistentPlans() {
        let plan = DayPlan(date: today, tasks: [
            PlanTask(title: "A", plannedMinutes: 5, status: .brewing), // no brewingSince
            PlanTask(title: "B", plannedMinutes: 5, status: .brewing, brewingSince: nine),
            PlanTask(title: "C", plannedMinutes: 5, status: .done, brewingSince: nine),
        ])
        let engine = TimerEngine(plan: plan, settings: AppSettings(), clock: clock, calendar: calendar)
        #expect(engine.plan.tasks.map(\.status) == [.paused, .pending, .done])
        #expect(engine.plan.tasks.allSatisfy { $0.brewingSince == nil })
    }

    @Test func aRelaunchResumesTheBrewingTaskFromItsTimestamps() {
        var engine = engine()
        engine.start()
        clock.advance(by: minutes(20))
        // The app quits and relaunches with the saved plan.
        let relaunched = TimerEngine(plan: engine.plan, settings: AppSettings(), clock: clock, calendar: calendar)
        #expect(relaunched.isBrewing)
        #expect(relaunched.remainingSeconds(at: clock.now) == minutes(25))
    }
}
