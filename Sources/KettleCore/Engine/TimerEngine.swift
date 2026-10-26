import Foundation

/// Owns the single brewing task of a day plan.
///
/// At most one task is *active* (brewing or paused) at a time. Remaining time is always
/// derived from timestamps (`brewingSince`) and the time already brewed, never by counting
/// down, so it stays correct across sleep and wake. Methods that close a session return it,
/// so the caller can store it and update the stats cache.
public struct TimerEngine {
    /// Sessions shorter than this (e.g. an accidental start and pause) aren't recorded.
    public static let minimumSessionSeconds: TimeInterval = 1

    public private(set) var plan: DayPlan
    public var settings: AppSettings

    private let clock: Clock
    private let calendar: Calendar

    public init(plan: DayPlan, settings: AppSettings, clock: Clock, calendar: Calendar) {
        self.plan = plan
        self.settings = settings
        self.clock = clock
        self.calendar = calendar
        normalize()
    }

    // MARK: State

    /// Index of the brewing or paused task.
    public var activeIndex: Int? {
        plan.tasks.firstIndex { $0.status == .brewing || $0.status == .paused }
    }

    public var activeTask: PlanTask? {
        activeIndex.map { plan.tasks[$0] }
    }

    public var isBrewing: Bool {
        activeTask?.status == .brewing
    }

    /// Seconds left in the active block at `now`; negative in overtime, nil when idle.
    public func remainingSeconds(at now: Date) -> TimeInterval? {
        activeTask?.remainingSeconds(at: now)
    }

    /// When the brewing block runs out (the whistle), if it hasn't already.
    public func whistleDate(at now: Date) -> Date? {
        guard let task = activeTask, task.status == .brewing else { return nil }
        let remaining = task.remainingSeconds(at: now)
        return remaining > 0 ? now + remaining : nil
    }

    /// What the menubar kettle should show at `now`. Doesn't allocate, so it's safe to call on every tick.
    public func iconState(at now: Date) -> IconState {
        guard let task = activeTask else {
            return PlanEngine.isComplete(plan) ? .dayComplete : .idle
        }
        let remaining = task.remainingSeconds(at: now)
        let level = SteamLevel(remaining: remaining, planned: TimeInterval(task.totalMinutes * 60))
        if task.status == .paused {
            return .paused(level)
        }
        return remaining > 0 ? .brewing(level) : .whistling
    }

    // MARK: Actions

    /// Space: pauses the brewing task, resumes the paused one, or starts the first pending one.
    @discardableResult
    public mutating func toggle() -> [Session] {
        if isBrewing {
            return pause()
        }
        return start()
    }

    /// Starts brewing `taskID`, or if nil, resumes the paused task or starts the first pending one.
    /// Starting a different task returns the active one to pending, keeping its brewed time.
    /// The first start on a day without a start time sets it to now.
    @discardableResult
    public mutating func start(taskID: UUID? = nil) -> [Session] {
        let target: Int? = if let taskID {
            plan.tasks.firstIndex { $0.id == taskID && !$0.isFinished }
        } else {
            activeIndex ?? plan.tasks.firstIndex { $0.status == .pending }
        }
        guard let target, plan.tasks[target].status != .brewing else { return [] }

        let now = clock.now
        var closed: [Session] = []
        if let active = activeIndex, active != target {
            closed += closeSession(at: active, now: now)
            plan.tasks[active].status = .pending
        }
        plan.tasks[target].status = .brewing
        plan.tasks[target].brewingSince = now
        plan.tasks[target].sessionExtensionMinutes = 0

        if plan.startTime == nil, plan.date == LocalDate(now, in: calendar) {
            let components = calendar.dateComponents([.hour, .minute], from: now)
            plan.startTime = LocalTime(hour: components.hour ?? 0, minute: components.minute ?? 0)
        }
        return closed
    }

    @discardableResult
    public mutating func pause() -> [Session] {
        guard let active = activeIndex, plan.tasks[active].status == .brewing else { return [] }
        let closed = closeSession(at: active, now: clock.now)
        plan.tasks[active].status = .paused
        return closed
    }

    /// Finishes the active task, then starts the next pending one if `autoStartNext` is on.
    @discardableResult
    public mutating func done() -> [Session] {
        guard let active = activeIndex else { return [] }
        var closed = closeSession(at: active, now: clock.now)
        plan.tasks[active].status = .done
        if settings.autoStartNext {
            closed += start()
        }
        return closed
    }

    /// Marks `taskID` (or the active task) skipped. Time in the open session isn't counted.
    public mutating func skip(taskID: UUID? = nil) {
        let index: Int? = if let taskID {
            plan.tasks.firstIndex { $0.id == taskID }
        } else {
            activeIndex
        }
        guard let index, !plan.tasks[index].isFinished else { return }
        plan.tasks[index].status = .skipped
        plan.tasks[index].brewingSince = nil
        plan.tasks[index].sessionExtensionMinutes = 0
    }

    /// Keep brewing: adds `minutes` to the brewing task, which shifts every later block. In
    /// overtime it first covers the whole minutes already overdue, so the block always runs
    /// for about `minutes` more from now.
    public mutating func keepBrewing(minutes: Int) {
        guard minutes > 0, let active = activeIndex, plan.tasks[active].status == .brewing else { return }
        let remaining = plan.tasks[active].remainingSeconds(at: clock.now)
        let overdueMinutes = remaining < 0 ? Int(-remaining / 60) : 0
        plan.tasks[active].extendedMinutes += minutes + overdueMinutes
        plan.tasks[active].sessionExtensionMinutes += minutes + overdueMinutes
    }

    /// Applies an edit from the popover (add, remove, reorder, resize). If the edit removes
    /// the brewing task, its open session is closed and returned.
    @discardableResult
    public mutating func editPlan(_ edit: (inout DayPlan) -> Void) -> [Session] {
        let before = activeTask
        edit(&plan)
        var closed: [Session] = []
        if let before, before.status == .brewing, !plan.tasks.contains(where: { $0.id == before.id }) {
            closed = session(for: before, now: clock.now).map { [$0] } ?? []
        }
        normalize()
        return closed
    }

    // MARK: Private

    /// Closes the open session of the task at `index` (if brewing) and adds it to the brewed time.
    private mutating func closeSession(at index: Int, now: Date) -> [Session] {
        let task = plan.tasks[index]
        guard task.status == .brewing, let since = task.brewingSince else { return [] }
        plan.tasks[index].brewedSeconds += max(0, Int(now.timeIntervalSince(since).rounded()))
        plan.tasks[index].brewingSince = nil
        plan.tasks[index].sessionExtensionMinutes = 0
        return session(for: task, now: now).map { [$0] } ?? []
    }

    private func session(for task: PlanTask, now: Date) -> Session? {
        guard let since = task.brewingSince, now.timeIntervalSince(since) >= Self.minimumSessionSeconds else {
            return nil
        }
        return Session(
            taskID: task.id,
            labelID: task.labelID,
            start: since,
            end: now,
            extensionsMinutes: task.sessionExtensionMinutes
        )
    }

    /// Repairs hand-edited or inconsistent plans: a brewing task without a start time is
    /// paused, and only the first active task stays active (later ones return to pending).
    private mutating func normalize() {
        var seenActive = false
        for index in plan.tasks.indices {
            if plan.tasks[index].status == .brewing, plan.tasks[index].brewingSince == nil {
                plan.tasks[index].status = .paused
            }
            if plan.tasks[index].status != .brewing {
                plan.tasks[index].brewingSince = nil
            }
            guard plan.tasks[index].status == .brewing || plan.tasks[index].status == .paused else { continue }
            if seenActive {
                plan.tasks[index].status = .pending
                plan.tasks[index].brewingSince = nil
            }
            seenActive = true
        }
    }
}
