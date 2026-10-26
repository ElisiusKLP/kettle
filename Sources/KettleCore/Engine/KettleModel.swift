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

    /// Adds a task to the timer's plan from a parsed quick-add entry.
    @discardableResult
    public func add(_ entry: QuickAddEntry) -> PlanTask {
        var newLabels = labels
        var added = PlanTask(title: entry.title, plannedMinutes: entry.minutes) // replaced by the edit below
        perform { engine in
            engine.editPlan { plan in
                added = PlanEngine.add(entry, to: &plan, labels: &newLabels)
            }
        }
        if newLabels != labels {
            labels = newLabels
            store.saveLabels(labels)
        }
        return added
    }

    /// Applies any `PlanEngine` edit to the timer's plan.
    public func editPlan(_ edit: (inout DayPlan) -> Void) {
        perform { $0.editPlan(edit) }
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
