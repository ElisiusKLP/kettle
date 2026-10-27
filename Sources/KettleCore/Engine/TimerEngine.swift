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
    /// How soon after the block runs out Kettle must notice for it to count as live: the
    /// kettle then whistles and the next task may auto-start. Noticed later (asleep, quit),
    /// the task finishes quietly.
    public static let liveFinishWindow: TimeInterval = 60

    /// What `finishIfTimeUp` did.
    public struct TimeUp: Equatable {
        public let taskID: UUID
        /// The finished task's session, plus any closed by auto-starting the next task.
        public let sessions: [Session]
        /// True when it ran out within `liveFinishWindow` of now.
        public let isLive: Bool
    }

    public private(set) var plan: DayPlan
    public var settings: AppSettings
    /// The task most recently finished with Done or by running out. Not stored: it only lets
    /// Keep brewing reopen a task that just finished.
    public private(set) var lastFinishedID: UUID?

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

    /// The last finished task, while it's still done, so Keep brewing can reopen it.
    public var reopenableID: UUID? {
        guard let lastFinishedID, plan.tasks.contains(where: { $0.id == lastFinishedID && $0.status == .done })
        else { return nil }
        return lastFinishedID
    }

    /// The task plain Keep brewing applies to: the brewing one or, when nothing is brewing or
    /// paused, the task that just finished.
    public var keepBrewingTarget: UUID? {
        if let task = activeTask {
            return task.status == .brewing ? task.id : nil
        }
        return reopenableID
    }

    /// Whether Keep brewing can apply to `taskID` (e.g. from its notification or context menu).
    public func canKeepBrewing(_ taskID: UUID) -> Bool {
        taskID == keepBrewingTarget || taskID == reopenableID
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
    ///
    /// A task that starts or resumes moves up to be next in line (ahead of the pending tasks).
    /// A pending task's `fixedStart` becomes now, so derived times follow what really happened.
    /// Resuming a paused task keeps its start, so the pause stretches its block, unless it was
    /// moved to later in the calendar: then it starts now.
    @discardableResult
    public mutating func start(taskID: UUID? = nil) -> [Session] {
        let target: Int? = if let taskID {
            plan.tasks.firstIndex { $0.id == taskID && !$0.isFinished }
        } else {
            activeIndex ?? plan.tasks.firstIndex { $0.status == .pending }
        }
        guard var target, plan.tasks[target].status != .brewing else { return [] }

        let now = clock.now
        let isToday = plan.date == LocalDate(now, in: calendar)
        var closed: [Session] = []
        if let active = activeIndex, active != target {
            closed += closeSession(at: active, now: now)
            plan.tasks[active].status = .pending
            plan.tasks[active].fixedStart = nil
        }
        if let first = plan.tasks.indices.first(where: { $0 != target && plan.tasks[$0].status == .pending }),
           first < target
        {
            plan.tasks.insert(plan.tasks.remove(at: target), at: first)
            target = first
        }
        if plan.tasks[target].status == .pending || (plan.tasks[target].fixedStart ?? now) > now {
            plan.tasks[target].fixedStart = now
        }
        plan.tasks[target].status = .brewing
        plan.tasks[target].brewingSince = now
        plan.tasks[target].sessionExtensionMinutes = 0

        if plan.startTime == nil, isToday {
            plan.startTime = LocalTime(now, in: calendar)
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
    /// With the ID of a pending task, marks that task done without brewing it.
    @discardableResult
    public mutating func done(taskID: UUID? = nil) -> [Session] {
        if let taskID, taskID != activeTask?.id {
            guard let index = plan.tasks.firstIndex(where: { $0.id == taskID && $0.status == .pending }) else {
                return []
            }
            plan.tasks[index].status = .done
            return []
        }
        guard let active = activeIndex else { return [] }
        var closed = closeSession(at: active, now: clock.now)
        plan.tasks[active].status = .done
        lastFinishedID = plan.tasks[active].id
        if settings.autoStartNext {
            closed += start()
        }
        return closed
    }

    /// When the brewing block has run out and `overtime` is off, finishes it as of the moment
    /// it ran out, so it counts exactly its planned time. If that was just now, the next task
    /// starts when `autoStartNext` is on.
    public mutating func finishIfTimeUp() -> TimeUp? {
        guard !settings.overtime, let active = activeIndex, plan.tasks[active].status == .brewing else { return nil }
        let now = clock.now
        let remaining = plan.tasks[active].remainingSeconds(at: now)
        guard remaining <= 0 else { return nil }
        let taskID = plan.tasks[active].id
        var closed = closeSession(at: active, now: now + remaining)
        plan.tasks[active].status = .done
        lastFinishedID = taskID
        let isLive = -remaining <= Self.liveFinishWindow
        if isLive, settings.autoStartNext {
            closed += start()
        }
        return TimeUp(taskID: taskID, sessions: closed, isLive: isLive)
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
    ///
    /// `taskID` defaults to `keepBrewingTarget`. A task that just finished is reopened and
    /// brews again (returning any other active task to pending), so it gets `minutes` more
    /// from now.
    @discardableResult
    public mutating func keepBrewing(minutes: Int, taskID: UUID? = nil) -> [Session] {
        guard minutes > 0, let taskID = taskID ?? keepBrewingTarget, canKeepBrewing(taskID) else { return [] }
        var closed: [Session] = []
        if taskID == reopenableID, let index = plan.tasks.firstIndex(where: { $0.id == taskID }) {
            if let active = activeIndex {
                closed += closeSession(at: active, now: clock.now)
                plan.tasks[active].status = .pending
                plan.tasks[active].fixedStart = nil
            }
            // Paused, so starting it resumes the block where it was.
            plan.tasks[index].status = .paused
            lastFinishedID = nil
            closed += start(taskID: taskID)
        }
        guard let active = activeIndex, plan.tasks[active].status == .brewing else { return closed }
        let remaining = plan.tasks[active].remainingSeconds(at: clock.now)
        let overdueMinutes = remaining < 0 ? Int(-remaining / 60) : 0
        plan.tasks[active].extendedMinutes += minutes + overdueMinutes
        plan.tasks[active].sessionExtensionMinutes += minutes + overdueMinutes
        return closed
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
