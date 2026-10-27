import Foundation
@testable import KettleCore
import Testing

struct TimerEngineTests {
    let calendar = Calendar.gregorian("Europe/Copenhagen")
    let today = LocalDate.ymd("2026-10-26")
    /// 09:00 in Copenhagen on `today`.
    let nine = Date.iso("2026-10-26T08:00:00Z")
    let clock: FakeClock
    let work = UUID()

    init() {
        clock = FakeClock(nine)
    }

    func engine(
        _ titlesAndMinutes: [(String, Int)] = [("Write", 45), ("Gym", 60), ("Emails", 20)],
        settings: AppSettings = AppSettings(),
        startTime: LocalTime? = nil
    ) -> TimerEngine {
        let tasks = titlesAndMinutes.map { PlanTask(title: $0.0, labelID: work, plannedMinutes: $0.1) }
        return TimerEngine(
            plan: DayPlan(date: today, tasks: tasks, startTime: startTime),
            settings: settings,
            clock: clock,
            calendar: calendar
        )
    }

    func minutes(_ value: Double) -> TimeInterval {
        value * 60
    }

    // MARK: Start

    @Test func startBrewsTheFirstPendingTask() {
        var engine = engine()
        let closed = engine.start()
        #expect(closed.isEmpty)
        #expect(engine.plan.tasks.map(\.status) == [.brewing, .pending, .pending])
        #expect(engine.activeTask?.brewingSince == nine)
        #expect(engine.isBrewing)
        #expect(engine.remainingSeconds(at: nine) == minutes(45))
    }

    @Test func firstStartSetsTheDaysStartTime() {
        var engine = engine()
        clock.advance(by: 125) // 09:02:05
        engine.start()
        #expect(engine.plan.startTime == LocalTime("09:02"))
    }

    @Test func startKeepsAnExistingStartTime() {
        var engine = engine(startTime: LocalTime("08:30"))
        engine.start()
        #expect(engine.plan.startTime == LocalTime("08:30"))
    }

    @Test func startOnAnotherDaysPlanLeavesItsStartTimeAlone() {
        var engine = TimerEngine(
            plan: DayPlan(date: today.adding(days: 1), tasks: [PlanTask(title: "A", plannedMinutes: 5)]),
            settings: AppSettings(),
            clock: clock,
            calendar: calendar
        )
        engine.start()
        #expect(engine.isBrewing)
        #expect(engine.plan.startTime == nil)
    }

    @Test func startSkipsFinishedTasks() {
        var engine = engine()
        engine.start()
        engine.done()
        engine.skip(taskID: engine.plan.tasks[1].id)
        engine.start()
        #expect(engine.activeTask?.title == "Emails")
    }

    @Test func startWithNothingPendingDoesNothing() {
        var engine = engine([("A", 5)])
        engine.skip(taskID: engine.plan.tasks[0].id)
        #expect(engine.start().isEmpty)
        #expect(engine.activeTask == nil)
        #expect(engine.iconState(at: nine) == .dayComplete)
    }

    @Test func startWhileBrewingDoesNothing() {
        var engine = engine()
        engine.start()
        clock.advance(by: 60)
        #expect(engine.start().isEmpty)
        #expect(engine.activeTask?.brewingSince == nine)
    }

    @Test func startingAnotherTaskClosesTheSessionAndReturnsTheActiveOneToPending() {
        var engine = engine()
        engine.start()
        clock.advance(by: minutes(10))
        let write = engine.plan.tasks[0].id
        let closed = engine.start(taskID: engine.plan.tasks[2].id)
        #expect(closed.count == 1)
        #expect(closed.first?.duration == minutes(10))
        // The started task moves up to be next in line.
        #expect(engine.plan.tasks.map(\.title) == ["Emails", "Write", "Gym"])
        #expect(engine.plan.tasks.map(\.status) == [.brewing, .pending, .pending])
        #expect(engine.plan.tasks[1].brewedSeconds == 600)
        // Coming back to the first task continues where it left off.
        engine.start(taskID: write)
        #expect(engine.activeTask?.id == write)
        #expect(engine.remainingSeconds(at: clock.now) == minutes(35))
    }

    @Test func startingAFinishedOrUnknownTaskDoesNothing() {
        var engine = engine()
        engine.start()
        engine.done()
        #expect(engine.start(taskID: engine.plan.tasks[0].id).isEmpty)
        #expect(engine.start(taskID: UUID()).isEmpty)
        #expect(engine.activeTask == nil)
    }

    // MARK: Pause and resume

    @Test func pauseClosesTheSession() throws {
        var engine = engine()
        engine.start()
        clock.advance(by: minutes(15))
        let session = try #require(engine.pause().first)
        #expect(session.start == nine)
        #expect(session.end == nine + minutes(15))
        #expect(session.taskID == engine.plan.tasks[0].id)
        #expect(session.labelID == work)
        #expect(session.extensionsMinutes == 0)
        #expect(engine.activeTask?.status == .paused)
        #expect(engine.activeTask?.brewingSince == nil)
        #expect(engine.activeTask?.brewedSeconds == 900)
    }

    @Test func pausedTimeDoesNotCount() {
        var engine = engine()
        engine.start()
        clock.advance(by: minutes(15))
        engine.pause()
        clock.advance(by: minutes(30))
        #expect(engine.remainingSeconds(at: clock.now) == minutes(30))
        engine.start() // resume
        #expect(engine.activeTask?.brewingSince == clock.now)
        clock.advance(by: minutes(5))
        #expect(engine.remainingSeconds(at: clock.now) == minutes(25))
    }

    @Test func pauseWhenNotBrewingDoesNothing() {
        var engine = engine()
        #expect(engine.pause().isEmpty)
        engine.start()
        clock.advance(by: 60)
        engine.pause()
        #expect(engine.pause().isEmpty)
    }

    @Test func toggleStartsPausesAndResumes() {
        var engine = engine()
        engine.toggle()
        #expect(engine.activeTask?.status == .brewing)
        clock.advance(by: 60)
        #expect(engine.toggle().count == 1)
        #expect(engine.activeTask?.status == .paused)
        engine.toggle()
        #expect(engine.activeTask?.status == .brewing)
        #expect(engine.activeTask?.title == "Write")
    }

    // MARK: Done and skip

    @Test func doneFinishesEarlyAndRecordsTheSession() throws {
        var engine = engine()
        engine.start()
        clock.advance(by: minutes(30))
        let session = try #require(engine.done().first)
        #expect(session.duration == minutes(30))
        #expect(engine.plan.tasks[0].status == .done)
        #expect(engine.plan.tasks[0].brewedSeconds == 1800)
        #expect(engine.activeTask == nil)
        #expect(engine.iconState(at: clock.now) == .idle)
    }

    @Test func doneAutoStartsTheNextTaskWhenEnabled() {
        var settings = AppSettings()
        settings.autoStartNext = true
        var engine = engine(settings: settings)
        engine.start()
        clock.advance(by: minutes(30))
        #expect(engine.done().count == 1)
        #expect(engine.activeTask?.title == "Gym")
        #expect(engine.activeTask?.brewingSince == clock.now)
    }

    @Test func doneWhilePausedRecordsNoNewSession() {
        var engine = engine()
        engine.start()
        clock.advance(by: minutes(5))
        engine.pause()
        clock.advance(by: minutes(5))
        #expect(engine.done().isEmpty)
        #expect(engine.plan.tasks[0].status == .done)
        #expect(engine.plan.tasks[0].brewedSeconds == 300)
    }

    @Test func doneWhenIdleDoesNothing() {
        var engine = engine()
        #expect(engine.done().isEmpty)
        #expect(engine.plan.tasks.allSatisfy { $0.status == .pending })
    }

    @Test func skipDiscardsTheOpenSession() {
        var engine = engine()
        engine.start()
        clock.advance(by: minutes(10))
        engine.skip()
        #expect(engine.plan.tasks[0].status == .skipped)
        #expect(engine.plan.tasks[0].brewedSeconds == 0)
        #expect(engine.plan.tasks[0].brewingSince == nil)
        #expect(engine.activeTask == nil)
    }

    @Test func skipAPendingTaskById() {
        var engine = engine()
        engine.start()
        engine.skip(taskID: engine.plan.tasks[2].id)
        #expect(engine.plan.tasks.map(\.status) == [.brewing, .pending, .skipped])
        engine.skip(taskID: UUID())
        engine.skip(taskID: engine.plan.tasks[2].id)
        #expect(engine.plan.tasks.map(\.status) == [.brewing, .pending, .skipped])
    }
}
