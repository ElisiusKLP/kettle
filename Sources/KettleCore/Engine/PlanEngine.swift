import Foundation

/// A task's derived start and end time. Never stored.
public struct ScheduledBlock: Equatable, Sendable {
    public let taskID: UUID
    public let start: Date
    public let end: Date
}

/// Pure operations on a day plan: derived times, editing, reordering and carry-over.
public enum PlanEngine {
    /// Where a day without a start time begins in the calendar, and on other days than today
    /// once a block has been dragged to a time.
    public static let defaultDayStart = LocalTime(hour: 9, minute: 0)!

    // MARK: Derived times

    /// When the plan's first block starts: its `startTime` on its day, otherwise now if the
    /// plan is today's. On other days it's nil (no times are shown) unless a block has a fixed
    /// start, in which case blocks start at `defaultDayStart` or that block, if earlier.
    public static func anchor(for plan: DayPlan, today: LocalDate, now: Date, calendar: Calendar) -> Date? {
        if let startTime = plan.startTime {
            return plan.date.date(at: startTime, in: calendar)
        }
        if plan.date == today {
            return now
        }
        guard let earliest = plan.tasks.compactMap(\.fixedStart).min() else { return nil }
        return plan.date.date(at: min(earliest, defaultDayStart), in: calendar)
    }

    /// Lays the blocks out back to back from `anchor`. A block with a fixed start starts no
    /// earlier than that time, which can leave a gap before it.
    ///
    /// Done blocks take the time actually brewed, skipped blocks take none, and every other
    /// block takes its planned minutes plus extensions. Pass `now` for today's plan to make the
    /// schedule live: the brewing or paused block then ends at `now` plus its remaining time
    /// (so a pause pushes its end, and everything after it, later), and pending blocks never
    /// start in the past. Pass nil for other days.
    public static func schedule(
        for plan: DayPlan,
        from anchor: Date,
        now: Date?,
        calendar: Calendar
    ) -> [ScheduledBlock] {
        var cursor = anchor
        var blocks: [ScheduledBlock] = []
        blocks.reserveCapacity(plan.tasks.count)

        for task in plan.tasks {
            let planned = TimeInterval(task.totalMinutes * 60)
            var start = cursor
            if let fixedStart = task.fixedStart {
                start = max(start, plan.date.date(at: fixedStart, in: calendar))
            }
            let end: Date
            switch task.status {
            case .done:
                end = start + TimeInterval(task.brewedSeconds)
            case .skipped:
                end = start
            case .brewing, .paused:
                if let now {
                    end = max(start, now + max(0, task.remainingSeconds(at: now)))
                } else {
                    end = start + max(planned, TimeInterval(task.brewedSeconds))
                }
            case .pending:
                if let now {
                    start = max(start, now)
                }
                end = start + planned
            }
            blocks.append(ScheduledBlock(taskID: task.id, start: start, end: end))
            cursor = end
        }
        return blocks
    }

    /// Tasks that "Carry over unfinished" would move: pending and paused ones.
    public static func unfinishedCount(_ plan: DayPlan) -> Int {
        plan.tasks.count { $0.status == .pending || $0.status == .paused }
    }

    /// True when the plan has tasks and every one is done or skipped: "All brewed for today."
    public static func isComplete(_ plan: DayPlan) -> Bool {
        !plan.tasks.isEmpty && plan.tasks.allSatisfy(\.isFinished)
    }

    // MARK: Editing

    /// Appends a pending task for `entry`, resolving (or creating) its label.
    @discardableResult
    public static func add(_ entry: QuickAddEntry, to plan: inout DayPlan, labels: inout [Label]) -> PlanTask {
        let labelID = entry.labelName.map { resolveLabel(named: $0, in: &labels).id }
        let task = PlanTask(title: entry.title, labelID: labelID, plannedMinutes: entry.minutes)
        plan.tasks.append(task)
        return task
    }

    /// The label called `name` (ignoring case). An archived match is unarchived, since the user
    /// is using it again. If there's no match, a new label with the next palette colour is added.
    public static func resolveLabel(named name: String, in labels: inout [Label]) -> Label {
        if let index = labels.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            labels[index].isArchived = false
            return labels[index]
        }
        let label = Label(name: name, colorHex: Label.nextColor(after: labels))
        labels.append(label)
        return label
    }

    public static func remove(taskID: UUID, from plan: inout DayPlan) {
        plan.tasks.removeAll { $0.id == taskID }
    }

    /// Moves the tasks at `source` to before the task at `destination`, using the same
    /// semantics as SwiftUI's `onMove`. Invalid offsets are ignored. Moved pending tasks lose
    /// their fixed start, so they follow the task before them in the new order.
    public static func move(in plan: inout DayPlan, fromOffsets source: IndexSet, toOffset destination: Int) {
        let source = source.filteredIndexSet { plan.tasks.indices.contains($0) }
        guard !source.isEmpty else { return }
        let destination = min(max(destination, 0), plan.tasks.count)
        let moving = source.map { index in
            var task = plan.tasks[index]
            if task.status == .pending {
                task.fixedStart = nil
            }
            return task
        }
        var remaining = plan.tasks.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        remaining.insert(contentsOf: moving, at: destination - source.count(in: 0 ..< destination))
        plan.tasks = remaining
    }

    /// Sets the task's planned minutes, clamped to 1...720.
    public static func resize(taskID: UUID, to minutes: Int, in plan: inout DayPlan) {
        guard let index = plan.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        plan.tasks[index].plannedMinutes = minutes
    }

    /// Changes the task's planned minutes by `delta`, clamped to 1...720.
    public static func adjust(taskID: UUID, byMinutes delta: Int, in plan: inout DayPlan) {
        guard let task = plan.tasks.first(where: { $0.id == taskID }) else { return }
        resize(taskID: taskID, to: task.plannedMinutes + delta, in: &plan)
    }

    /// Lets the task follow the one before it again.
    public static func unpin(taskID: UUID, in plan: inout DayPlan) {
        guard let index = plan.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        plan.tasks[index].fixedStart = nil
    }

    // MARK: Carry-over

    /// Moves unfinished tasks (pending and paused) from `yesterday` to the end of `today`.
    /// Paused tasks become pending and keep their brewed time. A task still brewing stays put,
    /// because the timer owns it.
    /// - Returns: the number of tasks moved.
    @discardableResult
    public static func carryOver(from yesterday: inout DayPlan, into today: inout DayPlan) -> Int {
        let unfinished = yesterday.tasks.filter { $0.status == .pending || $0.status == .paused }
        guard !unfinished.isEmpty else { return 0 }
        let movedIDs = Set(unfinished.map(\.id))
        yesterday.tasks.removeAll { movedIDs.contains($0.id) }
        today.tasks += unfinished.map { task in
            var task = task
            task.status = .pending
            task.brewingSince = nil
            task.fixedStart = nil
            return task
        }
        return unfinished.count
    }
}
