import Foundation
@testable import KettleCore
import Testing

/// Finishing at zero (the default), reopening a finished task, and marking tasks done.
extension TimerEngineTests {
    func overtime() -> AppSettings {
        var settings = AppSettings()
        settings.overtime = true
        return settings
    }

    // MARK: Finishing when time's up

    @Test func timeUpFinishesTheTaskAtExactlyItsPlannedTime() throws {
        var engine = engine()
        engine.start()
        clock.advance(by: minutes(45) - 1)
        #expect(engine.finishIfTimeUp() as TimerEngine.TimeUp? == nil)
        clock.advance(by: 3)
        let timeUpResult = engine.finishIfTimeUp()
        let timeUp = try #require(timeUpResult)
        #expect(timeUp.isLive)
        #expect(timeUp.taskID == engine.plan.tasks[0].id)
        #expect(try #require(timeUp.sessions.first).end == nine + minutes(45))
        #expect(engine.plan.tasks[0].status == .done)
        #expect(engine.plan.tasks[0].brewedSeconds == 45 * 60)
        #expect(engine.lastFinishedID == timeUp.taskID)
        #expect(engine.activeTask == nil)
        #expect(engine.finishIfTimeUp() as TimerEngine.TimeUp? == nil)
    }

    @Test func timeUpWithOvertimeKeepsBrewing() {
        var engine = engine(settings: overtime())
        engine.start()
        clock.advance(by: minutes(50))
        #expect(engine.finishIfTimeUp() as TimerEngine.TimeUp? == nil)
        #expect(engine.isBrewing)
        #expect(engine.iconState(at: clock.now) == .whistling)
    }

    @Test func timeUpIgnoresPausedTasks() {
        var engine = engine()
        engine.start()
        clock.advance(by: minutes(10))
        engine.pause()
        clock.advance(by: minutes(60))
        #expect(engine.finishIfTimeUp() as TimerEngine.TimeUp? == nil)
        #expect(engine.activeTask?.status == .paused)
    }

    @Test func timeUpAutoStartsTheNextTaskOnlyWhenLive() throws {
        var settings = AppSettings()
        settings.autoStartNext = true
        var live = engine(settings: settings)
        live.start()
        clock.advance(by: minutes(45) + 5)
        let timeUpResult = live.finishIfTimeUp()
        let timeUp = try #require(timeUpResult)
        #expect(timeUp.isLive)
        #expect(live.activeTask?.title == "Gym")

        var late = engine(settings: settings)
        late.start()
        clock.advance(by: minutes(45) + TimerEngine.liveFinishWindow + 1)
        let quietResult = late.finishIfTimeUp()
        let quiet = try #require(quietResult)
        #expect(!quiet.isLive)
        #expect(late.activeTask == nil)
        #expect(late.plan.tasks[0].brewedSeconds == 45 * 60)
    }

    // MARK: Keep brewing a finished task

    @Test func keepBrewingReopensTheTaskThatJustFinished() throws {
        var engine = engine()
        engine.start()
        clock.advance(by: minutes(46))
        let timeUpResult = engine.finishIfTimeUp()
        let timeUp = try #require(timeUpResult)
        #expect(engine.keepBrewingTarget == timeUp.taskID)

        clock.advance(by: minutes(3))
        let closed = engine.keepBrewing(minutes: 10)
        #expect(closed.isEmpty)
        #expect(engine.activeTask?.id == timeUp.taskID)
        #expect(engine.isBrewing)
        #expect(engine.remainingSeconds(at: clock.now) == minutes(10))
        #expect(engine.activeTask?.extendedMinutes == 10)
        #expect(engine.reopenableID == nil)
    }

    @Test func keepBrewingAFinishedTaskReturnsTheNextOneToPending() throws {
        var settings = AppSettings()
        settings.autoStartNext = true
        var engine = engine(settings: settings)
        engine.start()
        clock.advance(by: minutes(45))
        let timeUpResult = engine.finishIfTimeUp()
        let timeUp = try #require(timeUpResult)
        #expect(engine.activeTask?.title == "Gym")
        // Plain Keep brewing applies to the brewing task...
        #expect(engine.keepBrewingTarget == engine.activeTask?.id)
        // ...but the finished task's notification can still reopen it.
        #expect(engine.canKeepBrewing(timeUp.taskID))
        clock.advance(by: minutes(2))
        let closed = engine.keepBrewing(minutes: 5, taskID: timeUp.taskID)
        #expect(closed.map(\.duration) == [minutes(2)])
        #expect(engine.activeTask?.id == timeUp.taskID)
        #expect(engine.plan.tasks.map(\.status) == [.brewing, .pending, .pending])
        #expect(engine.plan.tasks[1].brewedSeconds == 120)
    }

    @Test func doneAlsoLetsKeepBrewingReopen() {
        var engine = engine()
        engine.start()
        clock.advance(by: minutes(30))
        engine.done()
        #expect(engine.keepBrewingTarget == engine.plan.tasks[0].id)
        engine.keepBrewing(minutes: 10)
        // The 15 minutes still left, plus 10.
        #expect(engine.remainingSeconds(at: clock.now) == minutes(25))
    }

    @Test func nothingToReopenWhenAnotherTaskIsActiveOrItWasRemoved() {
        var engine = engine()
        engine.start()
        engine.done()
        let finished = engine.plan.tasks[0].id
        engine.start()
        engine.pause()
        #expect(engine.keepBrewingTarget == nil)
        #expect(engine.reopenableID == finished)
        engine.editPlan { PlanEngine.remove(taskID: finished, from: &$0) }
        #expect(engine.reopenableID == nil)
        #expect(!engine.canKeepBrewing(finished))
        let reopened = engine.keepBrewing(minutes: 10, taskID: finished)
        #expect(reopened.isEmpty)
    }

    // MARK: Done for a pending task

    @Test func doneWithAPendingTaskMarksItDoneWithoutBrewing() {
        var engine = engine()
        engine.start()
        let emails = engine.plan.tasks[2].id
        let closed = engine.done(taskID: emails)
        #expect(closed.isEmpty)
        #expect(engine.plan.tasks.map(\.status) == [.brewing, .pending, .done])
        #expect(engine.reopenableID == nil)
        // The active task's own ID behaves like plain Done.
        engine.done(taskID: engine.plan.tasks[0].id)
        #expect(engine.plan.tasks[0].status == .done)
    }
}
