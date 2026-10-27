import Foundation

/// Which timer actions apply right now, shared by the popover's buttons, its task menus and
/// the menubar menu so they always agree.
public struct TimerControls: Equatable {
    public enum Toggle: Hashable {
        case start, pause, resume
    }

    public enum TaskAction: Hashable {
        case start, pause, resume, done, keepBrewing, skip
    }

    /// Start, Pause or Resume; nil when there's nothing to start.
    public let toggle: Toggle?
    /// Done and Skip apply to the active (brewing or paused) task.
    public let hasActiveTask: Bool
    /// The task Keep brewing applies to (see `TimerEngine.keepBrewingTarget`).
    public let keepBrewingTaskID: UUID?

    /// For the timer's plan, with `TimerEngine.reopenableID`.
    public init(plan: DayPlan, reopenableID: UUID?) {
        let active = plan.tasks.first { $0.status == .brewing || $0.status == .paused }
        switch active?.status {
        case .brewing: toggle = .pause
        case .paused: toggle = .resume
        default: toggle = plan.tasks.contains { $0.status == .pending } ? .start : nil
        }
        hasActiveTask = active != nil
        if let active {
            keepBrewingTaskID = active.status == .brewing ? active.id : nil
        } else {
            keepBrewingTaskID = reopenableID
        }
    }

    public init(engine: TimerEngine) {
        self.init(plan: engine.plan, reopenableID: engine.reopenableID)
    }

    /// The timer actions for one task's context menu, in menu order. On other days than the
    /// timer's, only Skip applies.
    public static func actions(for task: PlanTask, isTimerDay: Bool, reopenableID: UUID?) -> [TaskAction] {
        guard isTimerDay else { return task.isFinished ? [] : [.skip] }
        switch task.status {
        case .brewing: return [.pause, .done, .keepBrewing, .skip]
        case .paused: return [.resume, .done, .skip]
        case .pending: return [.start, .done, .skip]
        case .done: return task.id == reopenableID ? [.keepBrewing] : []
        case .skipped: return []
        }
    }
}
