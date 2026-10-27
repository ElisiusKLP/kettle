import Foundation

/// Drag and drop in the calendar: moving a block to a time, resizing it, and setting its times
/// in the editor.
///
/// Every edit keeps the other pending blocks where they're shown (`freeze`). The edited block
/// lands where it's put, and the blocks it then overlaps are pushed down, one after the other.
/// Nothing jumps up into a gap the edit leaves.
///
/// Pending blocks can be changed freely. A paused block can be moved and resized at its end.
/// A brewing block is locked (Keep brewing extends it), and finished blocks are history.
public struct CalendarEdit {
    /// Edits can't make a block shorter than this.
    public static let minimumMinutes = 5

    /// The plan's blocks as shown before the edit.
    public let schedule: [ScheduledBlock]
    /// Now, for today's plan; nil for other days.
    public let now: Date?

    public init(schedule: [ScheduledBlock], now: Date?) {
        self.schedule = schedule
        self.now = now
    }

    /// Whether the task's block can be moved (and its start changed).
    public static func canMove(_ task: PlanTask) -> Bool {
        task.status == .pending || task.status == .paused
    }

    /// Whether the task's length can be changed.
    public static func canResize(_ task: PlanTask) -> Bool {
        canMove(task)
    }

    /// Gives each pending task its current start as its fixed start.
    public func freeze(_ plan: inout DayPlan) {
        for index in plan.tasks.indices where plan.tasks[index].status == .pending {
            if let start = block(plan.tasks[index].id)?.start {
                plan.tasks[index].fixedStart = start
            }
        }
    }

    /// Moves the block to start at `start`. It goes just before the first pending block it
    /// would overlap or that ends later, which is pushed down. Finished and brewing blocks
    /// can't be pushed, so if it overlaps one, it starts when that one ends.
    ///
    /// For a paused block, `start` is when it resumes, so it's never before now, and the block
    /// then lasts exactly the time it has left.
    public func move(_ taskID: UUID, to start: Date, in plan: inout DayPlan) {
        guard let index = plan.tasks.firstIndex(where: { $0.id == taskID && Self.canMove($0) }) else { return }
        freeze(&plan)
        var task = plan.tasks.remove(at: index)
        var start = start
        if task.status == .paused, let now {
            start = max(start, now)
        }
        task.fixedStart = start
        let later = plan.tasks.firstIndex { other in
            other.status == .pending && (block(other.id).map { start < $0.end } ?? true)
        }
        plan.tasks.insert(task, at: later ?? plan.tasks.count)
    }

    /// The bottom edge: the block ends at `end` instead (to the whole minute). Longer, it
    /// pushes the blocks it now overlaps down; shorter, it leaves a gap.
    public func resize(_ taskID: UUID, end: Date, in plan: inout DayPlan) {
        guard let task = plan.tasks.first(where: { $0.id == taskID && Self.canResize($0) }),
              let block = block(taskID)
        else { return }
        let delta = Int((end.timeIntervalSince(block.end) / 60).rounded())
        freeze(&plan)
        setLength(taskID, to: task.totalMinutes + delta, in: &plan)
    }

    /// A pending block's top edge: it starts at `start` and keeps its end. It stays in its
    /// place in the day, so it can't start before the block above it ends (or before now).
    public func resize(_ taskID: UUID, start: Date, in plan: inout DayPlan) {
        guard let index = plan.tasks.firstIndex(where: { $0.id == taskID && $0.status == .pending }),
              let block = block(taskID)
        else { return }
        var start = min(start, block.end - TimeInterval(Self.minimumMinutes * 60))
        if let above = plan.tasks[..<index].compactMap({ self.block($0.id)?.end }).max() {
            start = max(start, above)
        }
        if let now {
            start = max(start, now)
        }
        freeze(&plan)
        plan.tasks[index].fixedStart = start
        setLength(taskID, to: Int((block.end.timeIntervalSince(start) / 60).rounded()), in: &plan)
    }

    /// The editor: the block starts at `start` and lasts `minutes` (including extensions). For
    /// a paused task, `start` is when it resumes and `minutes` the time it has left.
    public func set(_ taskID: UUID, start: Date, minutes: Int, in plan: inout DayPlan) {
        guard let task = plan.tasks.first(where: { $0.id == taskID && Self.canMove($0) }),
              let block = block(taskID)
        else { return }
        if abs(start.timeIntervalSince(Self.editorStart(task, block, now: now))) >= 60 {
            move(taskID, to: start, in: &plan)
        } else {
            freeze(&plan)
        }
        if task.status == .paused {
            setLength(taskID, to: (task.brewedSeconds + minutes * 60 + 59) / 60, in: &plan)
        } else {
            setLength(taskID, to: minutes, in: &plan)
        }
    }

    /// Where the editor's From starts: the block's start, or for a paused block, when it would
    /// resume (now, if its block started earlier).
    public static func editorStart(_ task: PlanTask, _ block: ScheduledBlock, now: Date?) -> Date {
        guard task.status == .paused, let now else { return block.start }
        return max(block.start, now)
    }

    /// Sets the block's length, keeping its extensions, at least `minimumMinutes` and, for a
    /// paused task, at least a minute more than it has brewed, so it can't finish on resume.
    private func setLength(_ taskID: UUID, to minutes: Int, in plan: inout DayPlan) {
        guard let task = plan.tasks.first(where: { $0.id == taskID }) else { return }
        let brewedMinutes = (task.brewedSeconds + 59) / 60
        let minimum = max(Self.minimumMinutes, task.status == .pending ? 0 : brewedMinutes + 1)
        PlanEngine.resize(taskID: taskID, to: max(minimum, minutes) - task.extendedMinutes, in: &plan)
    }

    private func block(_ taskID: UUID) -> ScheduledBlock? {
        schedule.first { $0.taskID == taskID }
    }
}
