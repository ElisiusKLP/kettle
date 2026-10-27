import Foundation
@testable import KettleCore
import Testing

/// Fixed start times from the calendar: layout, anchors and drag and drop.
extension PlanEngineTests {
    /// `HH:mm` on `today`, or the next day for times after 24:00 (e.g. "24:30").
    func at(_ time: String) -> Date {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        return today.date(in: calendar) + TimeInterval((parts[0] * 60 + parts[1]) * 60)
    }

    func pinned(_ title: String, _ minutes: Int, at time: String) -> PlanTask {
        var task = task(title, minutes)
        task.fixedStart = at(time)
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

    @Test func otherDaysAnchorAtNineOrTheEarliestFixedStart() {
        let tomorrow = today.adding(days: 1)
        func anchor(_ tasks: PlanTask...) -> Date? {
            PlanEngine.anchor(for: DayPlan(date: tomorrow, tasks: tasks), today: today, now: nine, calendar: calendar)
        }
        // Tomorrow's 13:00 and 07:30 are today's 37:00 and 31:30.
        #expect(anchor(task("A", 30)) == nil)
        #expect(anchor(task("A", 30), pinned("B", 30, at: "37:00")) == at("33:00"))
        #expect(anchor(pinned("A", 30, at: "31:30")) == at("31:30"))
    }

    @Test func aFixedStartCanBeAfterMidnight() {
        let plan = plan(task("A", 30), pinned("B", 30, at: "24:30"))
        #expect(offsets(schedule(plan)) == [[0, 30], [930, 960]])
    }

    // MARK: Drag and drop

    func time(_ string: String) -> Date {
        at(string)
    }

    /// A calendar edit against the plan as it's shown now.
    func edit(_ plan: DayPlan, now: Date? = nil) -> CalendarEdit {
        CalendarEdit(schedule: schedule(plan, now: now), now: now)
    }

    func pin(_ id: UUID, at string: String, in plan: inout DayPlan) {
        edit(plan).move(id, to: time(string), in: &plan)
    }

    @Test func droppingKeepsTheOtherBlocksWhereTheyAre() {
        // A 09:00–09:30, B 09:30–10:00, C 10:00–10:30.
        var plan = plan(task("A", 30), task("B", 30), task("C", 30))
        let id = plan.tasks[0].id
        // On the lower half of C: A starts when C ends, and B and C don't move up into the gap.
        pin(id, at: "10:15", in: &plan)
        #expect(plan.tasks.map(\.title) == ["B", "C", "A"])
        #expect(plan.tasks.map(\.fixedStart) == [at("09:30"), at("10:00"), at("10:15")])
        #expect(offsets(schedule(plan)) == [[30, 60], [60, 90], [90, 120]])
    }

    @Test func droppingOnABlockPushesItAndEverythingItThenOverlapsDown() {
        // A 09:00–09:30, B 09:30–10:30, C 10:30–11:00, D 12:00–12:30.
        var plan = plan(task("A", 30), task("B", 60), task("C", 30), pinned("D", 30, at: "12:00"))
        let id = plan.tasks[0].id
        // On the upper half of B: A takes 09:45, B and C are pushed 45 minutes, D has room.
        pin(id, at: "09:45", in: &plan)
        #expect(plan.tasks.map(\.title) == ["A", "B", "C", "D"])
        #expect(offsets(schedule(plan)) == [[45, 75], [75, 135], [135, 165], [180, 210]])

        // Dragged back up, A leaves a gap: B and C stay pushed.
        pin(id, at: "09:00", in: &plan)
        #expect(offsets(schedule(plan)) == [[0, 30], [75, 135], [135, 165], [180, 210]])

        // On the lower half of B (10:15–11:15), A starts when B ends and pushes C and D.
        pin(id, at: "11:00", in: &plan)
        #expect(plan.tasks.map(\.title) == ["B", "A", "C", "D"])
        #expect(offsets(schedule(plan)) == [[75, 135], [135, 165], [165, 195], [195, 225]])
    }

    // MARK: Resizing by the edges

    @Test func draggingTheBottomEdgeChangesTheDuration() {
        var plan = plan(task("A", 30), task("B", 30))
        let id = plan.tasks[0].id
        edit(plan).resize(id, end: nine + 50 * 60, in: &plan)
        #expect(plan.tasks[0].plannedMinutes == 50)
        #expect(offsets(schedule(plan)) == [[0, 50], [50, 80]])
        // Shorter again (never below five minutes): B stays where it was pushed.
        edit(plan).resize(id, end: nine - 3600, in: &plan)
        #expect(plan.tasks[0].plannedMinutes == CalendarEdit.minimumMinutes)
        #expect(offsets(schedule(plan)) == [[0, 5], [50, 80]])
    }

    @Test func theActiveBlockCantBeShortenedIntoThePast() {
        // Brewing since 09:00 with 10 of 45 minutes done at 09:10.
        let now = nine + 10 * 60
        var plan = plan(task("A", 45, .brewing, since: nine))
        edit(plan, now: now).resize(plan.tasks[0].id, end: nine, in: &plan)
        #expect(plan.tasks[0].totalMinutes == 11)
    }

    @Test func draggingTheTopEdgeMovesTheStartAndKeepsTheEnd() {
        var plan = plan(task("A", 30), task("B", 30))
        let id = plan.tasks[1].id
        // B 09:30–10:00 now starts at 09:45.
        edit(plan).resize(id, start: time("09:45"), in: &plan)
        #expect(plan.tasks[1].fixedStart == at("09:45"))
        #expect(offsets(schedule(plan)) == [[0, 30], [45, 60]])
        // Back up to 09:40: longer again.
        edit(plan).resize(id, start: time("09:40"), in: &plan)
        #expect(offsets(schedule(plan)) == [[0, 30], [40, 60]])
        // Dragged past its end, it keeps five minutes.
        edit(plan).resize(id, start: time("11:00"), in: &plan)
        #expect(offsets(schedule(plan)) == [[0, 30], [55, 60]])
        // Active and finished tasks keep their start.
        var active = self.plan(task("A", 30, .paused, brewed: 60))
        let before = active
        edit(active).resize(active.tasks[0].id, start: time("08:00"), in: &active)
        #expect(active == before)
    }

    @Test func movingStaysAfterFinishedAndActiveTasks() {
        var plan = plan(task("A", 30, .done, brewed: 1800), task("B", 30, .paused), task("C", 30))
        pin(plan.tasks[2].id, at: "08:00", in: &plan)
        #expect(plan.tasks.map(\.title) == ["A", "B", "C"])
        #expect(plan.tasks[2].fixedStart == at("08:00"))
    }

    @Test func onlyPendingTasksCanBeMoved() {
        var plan = plan(task("A", 30, .done, brewed: 1800), task("B", 30, .paused))
        let before = plan
        for task in before.tasks {
            pin(task.id, at: "12:00", in: &plan)
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

/// Random plans and drags, checked against the rules the calendar promises.
extension PlanEngineTests {
    @Test func randomDragsNeverOverlapOrPullOtherBlocksUp() {
        var seed: UInt64 = 0x4B45_5454_4C45
        func random(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        let statuses: [PlanTask.Status] = [.done, .skipped, .pending, .pending, .pending]
        for _ in 0 ..< 500 {
            var tasks = (0 ..< 2 + random(6)).map { index in
                task("T\(index)", 1 + random(90), statuses[random(statuses.count)], brewed: random(3600))
            }
            if random(3) == 0 {
                tasks[random(tasks.count)].fixedStart = nine + TimeInterval(random(600) * 60)
            }
            var plan = plan()
            plan.tasks = tasks
            let before = schedule(plan)
            let pending = plan.tasks.filter { $0.status == .pending }
            guard !pending.isEmpty else { continue }
            let dragged = pending[random(pending.count)]
            let time = nine + TimeInterval((random(160) * 5 - 60) * 60)
            let edit = edit(plan)
            switch random(3) {
            case 0: edit.move(dragged.id, to: time, in: &plan)
            case 1: edit.resize(dragged.id, start: time, in: &plan)
            default: edit.resize(dragged.id, end: time, in: &plan)
            }
            let after = schedule(plan)
            for (first, second) in zip(after, after.dropFirst()) {
                #expect(first.end <= second.start, "blocks overlap")
            }
            let starts = Dictionary(uniqueKeysWithValues: before.map { ($0.taskID, $0.start) })
            for block in after where block.taskID != dragged.id {
                let wasPending = pending.contains { $0.id == block.taskID }
                if wasPending, let start = starts[block.taskID] {
                    #expect(block.start >= start, "a block moved up")
                }
            }
            if let moved = after.first(where: { $0.taskID == dragged.id }), plan.tasks.contains(where: {
                $0.id == dragged.id && $0.fixedStart == time
            }) {
                #expect(moved.start >= time, "the dragged block starts before its drop")
            }
        }
    }
}
