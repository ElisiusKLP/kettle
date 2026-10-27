import Foundation
@testable import KettleCore
import Testing

/// Fixed start times from the calendar: layout, anchors and drag and drop.
extension PlanEngineTests {
    func pinned(_ title: String, _ minutes: Int, at time: String) -> PlanTask {
        var task = task(title, minutes)
        task.fixedStart = LocalTime(time)
        return task
    }

    func schedule(_ plan: DayPlan, now: Date? = nil) -> [ScheduledBlock] {
        PlanEngine.schedule(for: plan, from: nine, now: now, calendar: calendar)
    }

    // MARK: Layout

    @Test func aFixedStartLeavesAGapBeforeIt() {
        let plan = plan(task("A", 30), pinned("B", 30, at: "10:00"), task("C", 15))
        #expect(offsets(schedule(plan)) == [[0, 30], [60, 90], [90, 105]])
    }

    @Test func aBlockThatRunsLongPushesAFixedStartLater() {
        let plan = plan(task("A", 90), pinned("B", 30, at: "10:00"))
        #expect(offsets(schedule(plan)) == [[0, 90], [90, 120]])
    }

    @Test func otherDaysAnchorAtNineOrTheEarliestFixedStart() throws {
        let tomorrow = today.adding(days: 1)
        func anchor(_ tasks: PlanTask...) -> Date? {
            PlanEngine.anchor(for: DayPlan(date: tomorrow, tasks: tasks), today: today, now: nine, calendar: calendar)
        }
        #expect(anchor(task("A", 30)) == nil)
        #expect(try anchor(task("A", 30), pinned("B", 30, at: "13:00")) == tomorrow.date(
            at: #require(LocalTime("09:00")),
            in: calendar
        ))
        #expect(try anchor(pinned("A", 30, at: "07:30")) == tomorrow.date(
            at: #require(LocalTime("07:30")),
            in: calendar
        ))
    }

    // MARK: Drag and drop

    @Test func pinningMovesTheTaskIntoTimeOrder() throws {
        var plan = plan(task("A", 30), task("B", 30), task("C", 30))
        let id = plan.tasks[0].id
        try PlanEngine.pin(
            taskID: id,
            at: #require(LocalTime("10:15")),
            in: &plan,
            schedule: schedule(plan),
            calendar: calendar
        )
        #expect(plan.tasks.map(\.title) == ["B", "C", "A"])
        #expect(plan.tasks[2].fixedStart == LocalTime("10:15"))
        #expect(offsets(schedule(plan)) == [[0, 30], [30, 60], [75, 105]])

        try PlanEngine.pin(
            taskID: id,
            at: #require(LocalTime("09:45")),
            in: &plan,
            schedule: schedule(plan),
            calendar: calendar
        )
        // B 09:00, C 09:30: A goes after both, at 09:45, and C keeps following B.
        #expect(plan.tasks.map(\.title) == ["B", "C", "A"])
        try PlanEngine.pin(
            taskID: id,
            at: #require(LocalTime("09:15")),
            in: &plan,
            schedule: schedule(plan),
            calendar: calendar
        )
        #expect(plan.tasks.map(\.title) == ["B", "A", "C"])
        #expect(offsets(schedule(plan)) == [[0, 30], [30, 60], [60, 90]])
    }

    @Test func pinningStaysAfterFinishedAndActiveTasks() throws {
        var plan = plan(task("A", 30, .done, brewed: 1800), task("B", 30, .paused), task("C", 30))
        let id = plan.tasks[2].id
        try PlanEngine.pin(
            taskID: id,
            at: #require(LocalTime("08:00")),
            in: &plan,
            schedule: schedule(plan),
            calendar: calendar
        )
        #expect(plan.tasks.map(\.title) == ["A", "B", "C"])
        #expect(plan.tasks[2].fixedStart == LocalTime("08:00"))
    }

    @Test func onlyPendingTasksCanBePinned() throws {
        var plan = plan(task("A", 30, .done, brewed: 1800), task("B", 30, .paused))
        let before = plan
        for task in before.tasks {
            try PlanEngine.pin(
                taskID: task.id,
                at: #require(LocalTime("12:00")),
                in: &plan,
                schedule: [],
                calendar: calendar
            )
        }
        #expect(plan == before)
    }

    @Test func unpinningAndListReorderingLetATaskFollowAgain() {
        var plan = plan(task("A", 30), pinned("B", 30, at: "11:00"), pinned("C", 30, at: "12:00"))
        PlanEngine.unpin(taskID: plan.tasks[1].id, in: &plan)
        #expect(plan.tasks[1].fixedStart == nil)
        PlanEngine.move(in: &plan, fromOffsets: [2], toOffset: 0)
        #expect(plan.tasks.map(\.title) == ["C", "A", "B"])
        #expect(plan.tasks.allSatisfy { $0.fixedStart == nil })
    }

    @Test func carryOverDropsYesterdaysTimes() {
        var yesterday = DayPlan(date: today.adding(days: -1), tasks: [pinned("A", 30, at: "15:00")])
        var todayPlan = DayPlan(date: today)
        PlanEngine.carryOver(from: &yesterday, into: &todayPlan)
        #expect(todayPlan.tasks.first?.fixedStart == nil)
    }
}
