import Foundation

/// Drag and drop in the calendar: moving a block to a time, and resizing it by its edges.
///
/// Every edit keeps the other pending blocks where they're shown (`freeze`), so they can be
/// pushed down by a block that now overlaps them, one after the other, but never jump up into
/// a gap the edit leaves.
public struct CalendarEdit {
    /// Edges can't make a block shorter than this.
    public static let minimumMinutes = 5

    /// The plan's blocks as shown before the edit.
    public let schedule: [ScheduledBlock]
    /// Now, for today's plan; nil for other days.
    public let now: Date?

    public init(schedule: [ScheduledBlock], now: Date?) {
        self.schedule = schedule
        self.now = now
    }

    /// Gives each pending task its current start as its fixed start.
    public func freeze(_ plan: inout DayPlan) {
        for index in plan.tasks.indices where plan.tasks[index].status == .pending {
            if let start = block(plan.tasks[index].id)?.start {
                plan.tasks[index].fixedStart = start
            }
        }
    }

    /// Fixes a pending task to start at `start`, and moves it among the pending tasks so the
    /// order follows the times. It stays after every task that isn't pending (finished or
    /// active). Dropped on the upper half of another pending block, it takes that time and
    /// pushes the block down; on the lower half, it starts when that block ends.
    public func move(_ taskID: UUID, to start: Date, in plan: inout DayPlan) {
        guard let index = plan.tasks.firstIndex(where: { $0.id == taskID && $0.status == .pending }) else { return }
        freeze(&plan)
        var task = plan.tasks.remove(at: index)
        task.fixedStart = start
        let afterFixed = (plan.tasks.lastIndex { $0.status != .pending }).map { $0 + 1 } ?? 0
        let later = plan.tasks.indices.first { position in
            guard position >= afterFixed else { return false }
            guard let block = block(plan.tasks[position].id) else { return true }
            return start < block.start + block.end.timeIntervalSince(block.start) / 2
        }
        plan.tasks.insert(task, at: later ?? plan.tasks.count)
    }

    /// The bottom edge: the block ends at `end` instead, so its planned minutes change by the
    /// difference (whole minutes). Longer, it pushes the blocks it now overlaps down; shorter,
    /// it leaves a gap. It keeps at least `minimumMinutes`, and an active block at least a
    /// minute from now, so a drag can't finish it by accident.
    public func resize(_ taskID: UUID, end: Date, in plan: inout DayPlan) {
        guard let task = plan.tasks.first(where: { $0.id == taskID && !$0.isFinished }),
              let block = block(taskID)
        else { return }
        var earliest = block.start + TimeInterval(Self.minimumMinutes * 60)
        if let now, task.status != .pending {
            earliest = max(earliest, now + 60)
        }
        let delta = Int((max(end, earliest).timeIntervalSince(block.end) / 60).rounded())
        freeze(&plan)
        PlanEngine.adjust(taskID: taskID, byMinutes: delta, in: &plan)
    }

    /// A pending block's top edge: it's moved to start at `start` (see `move`) and keeps its
    /// end, so it gets longer or shorter. It keeps at least `minimumMinutes`.
    public func resize(_ taskID: UUID, start: Date, in plan: inout DayPlan) {
        guard let task = plan.tasks.first(where: { $0.id == taskID && $0.status == .pending }),
              let block = block(taskID)
        else { return }
        let start = min(start, block.end - TimeInterval(Self.minimumMinutes * 60))
        let total = Int((block.end.timeIntervalSince(start) / 60).rounded())
        move(taskID, to: start, in: &plan)
        PlanEngine.resize(taskID: taskID, to: max(1, total - task.extendedMinutes), in: &plan)
    }

    private func block(_ taskID: UUID) -> ScheduledBlock? {
        schedule.first { $0.taskID == taskID }
    }
}
