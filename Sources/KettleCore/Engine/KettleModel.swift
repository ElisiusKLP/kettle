import Foundation

/// The app's state and actions: today's timer, labels and settings, kept in sync with the
/// store and the stats cache. The app target only wires this to AppKit and SwiftUI.
///
/// Not thread-safe: use it from the main thread.
public final class KettleModel {
    public private(set) var engine: TimerEngine
    public private(set) var labels: [Label]
    public private(set) var settings: AppSettings
    /// Receives errors from saving, so the app can log them.
    public var onError: ((Error) -> Void)?

    private let store: Store
    private let cache: DailyTotalsCache
    private let clock: Clock
    private let calendar: Calendar

    /// Loads settings, labels and today's plan, and nothing else (SPEC section 7).
    public init(store: Store, clock: Clock, calendar: Calendar) throws {
        let snapshot = try store.loadStartupSnapshot(today: LocalDate(clock.now, in: calendar))
        self.store = store
        self.clock = clock
        self.calendar = calendar
        cache = DailyTotalsCache(store: store, calendar: calendar)
        labels = snapshot.labels
        settings = snapshot.settings
        engine = TimerEngine(plan: snapshot.today, settings: snapshot.settings, clock: clock, calendar: calendar)
    }

    public var today: LocalDate {
        LocalDate(clock.now, in: calendar)
    }

    // MARK: Timer actions

    public func toggle() {
        perform { $0.toggle() }
    }

    public func start(taskID: UUID? = nil) {
        perform { $0.start(taskID: taskID) }
    }

    public func pause() {
        perform { $0.pause() }
    }

    public func done() {
        perform { $0.done() }
        rollOverIfNeeded()
    }

    public func skip(taskID: UUID? = nil) {
        perform { engine in
            engine.skip(taskID: taskID)
            return []
        }
        rollOverIfNeeded()
    }

    /// Keep brewing by the main (`extendMinutes`) or secondary (`secondaryExtendMinutes`) amount.
    public func keepBrewing(secondary: Bool = false) {
        let minutes = secondary ? settings.secondaryExtendMinutes : settings.extendMinutes
        perform { engine in
            engine.keepBrewing(minutes: minutes)
            return []
        }
    }

    // MARK: Planning

    /// Adds a pending task from a parsed quick-add entry to `date`'s plan (the timer's plan if
    /// nil), creating its label if needed.
    @discardableResult
    public func add(_ entry: QuickAddEntry, to date: LocalDate? = nil) -> PlanTask? {
        var newLabels = labels
        var added: PlanTask?
        editPlan(for: date ?? engine.plan.date) { plan in
            added = PlanEngine.add(entry, to: &plan, labels: &newLabels)
        }
        if added != nil, newLabels != labels {
            labels = newLabels
            store.saveLabels(labels)
        }
        return added
    }

    /// Applies any `PlanEngine` edit to the timer's plan.
    public func editPlan(_ edit: (inout DayPlan) -> Void) {
        perform { $0.editPlan(edit) }
    }

    /// The plan for `date`: the timer's own plan if it's that day, otherwise read from disk and
    /// not kept, so only today's plan stays in memory (SPEC section 7).
    public func plan(for date: LocalDate) throws -> DayPlan {
        date == engine.plan.date ? engine.plan : try store.loadPlan(for: date)
    }

    /// Applies a `PlanEngine` edit to any day's plan. Another day's plan is loaded, edited,
    /// saved and dropped again.
    public func editPlan(for date: LocalDate, _ edit: (inout DayPlan) -> Void) {
        guard date != engine.plan.date else {
            editPlan(edit)
            return
        }
        do {
            var plan = try store.loadPlan(for: date)
            let before = plan
            edit(&plan)
            guard plan != before else { return }
            store.savePlan(plan)
            try cache.record(plan)
        } catch {
            onError?(error)
        }
    }

    /// "Carry over unfinished": moves yesterday's pending and paused tasks to the end of
    /// today's plan. Only when the timer is on today.
    /// - Returns: the number of tasks moved.
    @discardableResult
    public func carryOverUnfinished() -> Int {
        let today = today
        guard engine.plan.date == today else { return 0 }
        do {
            var yesterday = try store.loadPlan(for: today.adding(days: -1))
            var moved = 0
            editPlan { plan in
                moved = PlanEngine.carryOver(from: &yesterday, into: &plan)
            }
            if moved > 0 {
                store.savePlan(yesterday)
                try cache.record(yesterday)
            }
            return moved
        } catch {
            onError?(error)
            return 0
        }
    }

    public func updateSettings(_ newSettings: AppSettings) {
        guard newSettings != settings else { return }
        settings = newSettings
        engine.settings = newSettings
        store.saveSettings(newSettings)
    }

    // MARK: Days

    /// Switches the timer to today's plan once the day has changed and nothing is brewing or
    /// paused. A block that runs past midnight keeps its own day until it's finished.
    /// - Returns: true if it switched.
    @discardableResult
    public func rollOverIfNeeded() -> Bool {
        let today = today
        guard engine.plan.date != today, engine.activeTask == nil else { return false }
        do {
            let plan = try store.loadPlan(for: today)
            engine = TimerEngine(plan: plan, settings: settings, clock: clock, calendar: calendar)
            return true
        } catch {
            onError?(error)
            return false
        }
    }

    /// Writes everything pending (on quit and before sleep).
    public func flush() {
        do {
            try store.flush()
        } catch {
            onError?(error)
        }
    }

    // MARK: Private

    /// Runs a timer action, then saves the plan and records closed sessions and stats.
    private func perform(_ action: (inout TimerEngine) -> [Session]) {
        let before = engine.plan
        let sessions = action(&engine)
        guard engine.plan != before || !sessions.isEmpty else { return }
        do {
            for session in sessions {
                try store.appendSession(session)
            }
            try cache.record(sessions)
            store.savePlan(engine.plan)
            try cache.record(engine.plan)
        } catch {
            onError?(error)
        }
    }
}
