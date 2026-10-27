import Foundation
@testable import KettleCore
import Testing

struct PlanEngineTests {
    let calendar = Calendar.gregorian("Europe/Copenhagen")
    let today = LocalDate.ymd("2026-10-26")
    /// 09:00 in Copenhagen on `today`.
    let nine = Date.iso("2026-10-26T08:00:00Z")

    func plan(_ tasks: PlanTask...) -> DayPlan {
        DayPlan(date: today, tasks: tasks, startTime: LocalTime("09:00"))
    }

    func task(
        _ title: String,
        _ minutes: Int,
        _ status: PlanTask.Status = .pending,
        brewed: Int = 0,
        since: Date? = nil,
        extended: Int = 0
    ) -> PlanTask {
        PlanTask(
            title: title,
            plannedMinutes: minutes,
            status: status,
            extendedMinutes: extended,
            brewedSeconds: brewed,
            brewingSince: since
        )
    }

    /// Start and end of each block as minutes after 09:00.
    func offsets(_ blocks: [ScheduledBlock]) -> [[Int]] {
        blocks.map { [Int($0.start.timeIntervalSince(nine) / 60), Int($0.end.timeIntervalSince(nine) / 60)] }
    }

    // MARK: Anchor

    @Test func anchorIsTheStartTimeOnThePlansDay() {
        let tomorrow = DayPlan(date: today.adding(days: 1), startTime: LocalTime("08:30"))
        let anchor = PlanEngine.anchor(for: tomorrow, today: today, now: nine, calendar: calendar)
        #expect(anchor == .iso("2026-10-27T07:30:00Z"))
    }

    @Test func anchorIsNowForTodayWithoutAStartTime() {
        let plan = DayPlan(date: today)
        #expect(PlanEngine.anchor(for: plan, today: today, now: nine + 77, calendar: calendar) == nine + 77)
    }

    @Test func otherDaysWithoutAStartTimeHaveNoAnchor() {
        for date in [today.adding(days: 1), today.adding(days: -1)] {
            #expect(PlanEngine.anchor(for: DayPlan(date: date), today: today, now: nine, calendar: calendar) == nil)
        }
    }

    // MARK: Derived times

    @Test func blocksRunBackToBack() {
        let plan = plan(task("A", 45), task("B", 60), task("C", 20))
        #expect(offsets(PlanEngine.schedule(for: plan, from: nine, now: nil)) == [[0, 45], [45, 105], [105, 125]])
    }

    @Test func extensionsLengthenTheirBlock() {
        let plan = plan(task("A", 45, extended: 10), task("B", 30))
        #expect(offsets(PlanEngine.schedule(for: plan, from: nine, now: nil)) == [[0, 55], [55, 85]])
    }

    @Test func resizingShiftsEveryLaterBlock() {
        var plan = plan(task("A", 45), task("B", 60), task("C", 20))
        PlanEngine.resize(taskID: plan.tasks[0].id, to: 30, in: &plan)
        #expect(offsets(PlanEngine.schedule(for: plan, from: nine, now: nil)) == [[0, 30], [30, 90], [90, 110]])
    }

    @Test func reorderingShiftsTheBlocks() {
        var plan = plan(task("A", 45), task("B", 60), task("C", 20))
        PlanEngine.move(in: &plan, fromOffsets: [2], toOffset: 0)
        #expect(plan.tasks.map(\.title) == ["C", "A", "B"])
        #expect(offsets(PlanEngine.schedule(for: plan, from: nine, now: nil)) == [[0, 20], [20, 65], [65, 125]])
    }

    @Test func doneBlocksTakeTheirActualTimeAndSkippedTakeNone() {
        let plan = plan(task("A", 45, .done, brewed: 30 * 60), task("B", 60, .skipped), task("C", 20))
        #expect(offsets(PlanEngine.schedule(for: plan, from: nine, now: nil)) == [[0, 30], [30, 30], [30, 50]])
    }

    @Test func liveScheduleEndsTheBrewingBlockAtNowPlusRemaining() {
        // A started at 09:00 but was paused for 10 minutes; it has brewed 20 of 45 minutes by 09:30.
        let now = nine + 30 * 60
        let plan = plan(task("A", 45, .brewing, brewed: 10 * 60, since: now - 10 * 60), task("B", 30))
        #expect(offsets(PlanEngine.schedule(for: plan, from: nine, now: now)) == [[0, 55], [55, 85]])
    }

    @Test func liveScheduleCountsAPausedBlocksRemainingTimeFromNow() {
        let now = nine + 60 * 60
        let plan = plan(task("A", 45, .paused, brewed: 15 * 60), task("B", 30))
        #expect(offsets(PlanEngine.schedule(for: plan, from: nine, now: now)) == [[0, 90], [90, 120]])
    }

    @Test func inOvertimeTheBrewingBlockEndsNow() {
        let now = nine + 50 * 60
        let plan = plan(task("A", 45, .brewing, since: nine), task("B", 30))
        #expect(offsets(PlanEngine.schedule(for: plan, from: nine, now: now)) == [[0, 50], [50, 80]])
    }

    @Test func pendingBlocksNeverStartInThePast() {
        let now = nine + 120 * 60
        let plan = plan(task("A", 45, .done, brewed: 45 * 60), task("B", 30), task("C", 15))
        #expect(offsets(PlanEngine.schedule(for: plan, from: nine, now: now)) == [[0, 45], [120, 150], [150, 165]])
    }

    @Test func withoutNowABrewingBlockTakesAtLeastItsPlannedTime() {
        let plan = plan(task("A", 45, .paused, brewed: 50 * 60), task("B", 30, .brewing, brewed: 60))
        #expect(offsets(PlanEngine.schedule(for: plan, from: nine, now: nil)) == [[0, 50], [50, 80]])
    }

    @Test func emptyPlanHasNoBlocks() {
        #expect(PlanEngine.schedule(for: DayPlan(date: today), from: nine, now: nine).isEmpty)
    }

    @Test func completeWhenEveryTaskIsDoneOrSkipped() {
        #expect(!PlanEngine.isComplete(DayPlan(date: today)))
        #expect(PlanEngine.isComplete(plan(task("A", 5, .done), task("B", 5, .skipped))))
        #expect(!PlanEngine.isComplete(plan(task("A", 5, .done), task("B", 5, .paused))))
    }

    // MARK: Editing

    @Test func addAppendsAPendingTaskWithANewLabel() {
        var plan = plan(task("A", 10))
        var labels: [Label] = []
        let added = PlanEngine.add(
            QuickAddEntry(title: "Gym", minutes: 60, labelName: "health"),
            to: &plan,
            labels: &labels
        )
        #expect(plan.tasks.map(\.title) == ["A", "Gym"])
        #expect(added.status == .pending)
        #expect(added.plannedMinutes == 60)
        #expect(labels.map(\.name) == ["health"])
        #expect(labels.first?.colorHex == Label.palette[0])
        #expect(added.labelID == labels.first?.id)
    }

    @Test func addReusesAnExistingLabelIgnoringCase() {
        let work = Label(name: "Work", colorHex: "#000000")
        var plan = DayPlan(date: today)
        var labels = [work]
        let added = PlanEngine.add(
            QuickAddEntry(title: "Report", minutes: 45, labelName: "work"),
            to: &plan,
            labels: &labels
        )
        #expect(labels == [work])
        #expect(added.labelID == work.id)
    }

    @Test func addUnarchivesAnArchivedLabel() {
        let old = Label(name: "garden", colorHex: "#000000", isArchived: true)
        var plan = DayPlan(date: today)
        var labels = [old]
        PlanEngine.add(QuickAddEntry(title: "Weed", minutes: 20, labelName: "garden"), to: &plan, labels: &labels)
        #expect(labels.count == 1)
        #expect(labels[0].isArchived == false)
    }

    @Test func addWithoutALabelLeavesLabelsAlone() {
        var plan = DayPlan(date: today)
        var labels: [Label] = []
        let added = PlanEngine.add(
            QuickAddEntry(title: "Emails", minutes: 20, labelName: nil),
            to: &plan,
            labels: &labels
        )
        #expect(added.labelID == nil)
        #expect(labels.isEmpty)
    }

    @Test func newLabelsTakeTheFirstUnusedPaletteColour() {
        let labels = [Label(name: "a", colorHex: Label.palette[0].lowercased()), Label(name: "b", colorHex: "#123456")]
        #expect(Label.nextColor(after: labels) == Label.palette[1])
        let full = Label.palette.map { Label(name: $0, colorHex: $0) }
        #expect(Label.nextColor(after: full) == Label.palette[0])
    }

    @Test func removeDeletesOnlyThatTask() {
        var plan = plan(task("A", 10), task("B", 10))
        PlanEngine.remove(taskID: plan.tasks[0].id, from: &plan)
        #expect(plan.tasks.map(\.title) == ["B"])
    }

    @Test(arguments: [
        ([0], 2, "BACD"), ([3], 0, "DABC"), ([0, 2], 4, "BDAC"), ([1], 1, "ABCD"), ([1], 2, "ABCD"),
        ([1, 2], 0, "BCAD"), ([0], 99, "BCDA"), ([2], -5, "CABD"), ([7], 0, "ABCD"), ([], 0, "ABCD"),
    ])
    func moveMatchesSwiftUIOnMove(source: [Int], destination: Int, expected: String) {
        var plan = plan(task("A", 1), task("B", 1), task("C", 1), task("D", 1))
        PlanEngine.move(in: &plan, fromOffsets: IndexSet(source), toOffset: destination)
        #expect(plan.tasks.map(\.title).joined() == expected)
    }

    @Test func adjustStepsAndClamps() {
        var plan = plan(task("A", 10))
        let id = plan.tasks[0].id
        PlanEngine.adjust(taskID: id, byMinutes: AppSettings().resizeStepMinutes, in: &plan)
        #expect(plan.tasks[0].plannedMinutes == 15)
        PlanEngine.adjust(taskID: id, byMinutes: -100, in: &plan)
        #expect(plan.tasks[0].plannedMinutes == 1)
        PlanEngine.resize(taskID: id, to: 9999, in: &plan)
        #expect(plan.tasks[0].plannedMinutes == 720)
    }

    @Test func editingAnUnknownTaskDoesNothing() {
        var plan = plan(task("A", 10))
        let before = plan
        PlanEngine.adjust(taskID: UUID(), byMinutes: 5, in: &plan)
        PlanEngine.resize(taskID: UUID(), to: 5, in: &plan)
        PlanEngine.remove(taskID: UUID(), from: &plan)
        #expect(plan == before)
    }

    // MARK: Carry-over

    @Test func carryOverMovesUnfinishedTasksToTheEndOfToday() {
        var yesterday = DayPlan(date: today.adding(days: -1), tasks: [
            task("Done", 10, .done, brewed: 600), task("Pending", 20), task("Skipped", 5, .skipped),
            task("Paused", 30, .paused, brewed: 300), task("Brewing", 15, .brewing, since: nine),
        ])
        var todayPlan = plan(task("Today", 10))

        let moved = PlanEngine.carryOver(from: &yesterday, into: &todayPlan)

        #expect(moved == 2)
        #expect(yesterday.tasks.map(\.title) == ["Done", "Skipped", "Brewing"])
        #expect(todayPlan.tasks.map(\.title) == ["Today", "Pending", "Paused"])
        #expect(todayPlan.tasks.map(\.status) == [.pending, .pending, .pending])
        #expect(todayPlan.tasks[2].brewedSeconds == 300)
    }

    @Test func carryOverTwiceMovesNothingMore() {
        var yesterday = DayPlan(date: today.adding(days: -1), tasks: [task("Pending", 20)])
        var todayPlan = DayPlan(date: today)
        PlanEngine.carryOver(from: &yesterday, into: &todayPlan)
        #expect(PlanEngine.carryOver(from: &yesterday, into: &todayPlan) == 0)
        #expect(todayPlan.tasks.count == 1)
    }

    // MARK: Task timing helpers

    @Test func brewedAndRemainingTimeIncludeTheOpenSession() {
        let brewing = task("A", 45, .brewing, brewed: 600, since: nine)
        #expect(brewing.brewedSeconds(at: nine + 300) == 900)
        #expect(brewing.remainingSeconds(at: nine + 300) == 45 * 60 - 900)
        #expect(brewing.brewedSeconds(at: nine - 100) == 600) // clock went backwards
        let paused = task("B", 10, .paused, brewed: 700, since: nil)
        #expect(paused.remainingSeconds(at: nine + 9999) == -100)
    }
}
