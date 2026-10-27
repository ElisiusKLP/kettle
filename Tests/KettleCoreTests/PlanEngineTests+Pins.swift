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

    func time(_ string: String) throws -> LocalTime {
        try #require(LocalTime(string))
    }

    @Test func droppingOnTheUpperHalfOfABlockPushesItDown() throws {
        // A 09:00–09:30, B 09:30–10:30, C 10:30–11:00.
        var plan = plan(task("A", 30), task("B", 60), task("C", 30))
        let id = plan.tasks[2].id
        try PlanEngine.pin(taskID: id, at: time("09:45"), in: &plan, schedule: schedule(plan), calendar: calendar)
        #expect(plan.tasks.map(\.title) == ["A", "C", "B"])
        #expect(offsets(schedule(plan)) == [[0, 30], [45, 75], [75, 135]])

        // On the lower half of B (now 10:15–11:15), C goes after it.
        try PlanEngine.pin(taskID: id, at: time("11:00"), in: &plan, schedule: schedule(plan), calendar: calendar)
        #expect(plan.tasks.map(\.title) == ["A", "B", "C"])
        #expect(offsets(schedule(plan)) == [[0, 30], [30, 90], [120, 150]])
    }

    // MARK: Resizing by the edges

    @Test func draggingTheBottomEdgeChangesTheDuration() {
        var plan = plan(task("A", 30), task("B", 30))
        let id = plan.tasks[0].id
        PlanEngine.resize(taskID: id, end: nine + 50 * 60, in: &plan, schedule: schedule(plan), now: nil)
        #expect(plan.tasks[0].plannedMinutes == 50)
        #expect(offsets(schedule(plan)) == [[0, 50], [50, 80]])
        // Never shorter than a minute.
        PlanEngine.resize(taskID: id, end: nine - 3600, in: &plan, schedule: schedule(plan), now: nil)
        #expect(plan.tasks[0].plannedMinutes == 1)
    }

    @Test func theActiveBlockCantBeShortenedIntoThePast() {
        // Brewing since 09:00 with 10 of 45 minutes done at 09:10.
        let now = nine + 10 * 60
        var plan = plan(task("A", 45, .brewing, since: nine))
        PlanEngine.resize(
            taskID: plan.tasks[0].id, end: nine, in: &plan, schedule: schedule(plan, now: now), now: now
        )
        #expect(plan.tasks[0].totalMinutes == 11)
    }

    @Test func draggingTheTopEdgeMovesTheStartAndKeepsTheEnd() throws {
        var plan = plan(task("A", 30), task("B", 30))
        let id = plan.tasks[1].id
        // B 09:30–10:00 now starts at 09:45.
        try PlanEngine.resize(taskID: id, start: time("09:45"), in: &plan, schedule: schedule(plan), calendar: calendar)
        #expect(plan.tasks[1].fixedStart == LocalTime("09:45"))
        #expect(offsets(schedule(plan)) == [[0, 30], [45, 60]])
        // Back up to 09:40: longer again.
        try PlanEngine.resize(taskID: id, start: time("09:40"), in: &plan, schedule: schedule(plan), calendar: calendar)
        #expect(offsets(schedule(plan)) == [[0, 30], [40, 60]])
        // Active and finished tasks keep their start.
        var active = self.plan(task("A", 30, .paused, brewed: 60))
        let before = active
        try PlanEngine.resize(
            taskID: active.tasks[0].id, start: time("08:00"), in: &active, schedule: schedule(active),
            calendar: calendar
        )
        #expect(active == before)
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
