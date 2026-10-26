import Foundation

/// Keeps `stats/daily-totals.json` up to date incrementally, and can rebuild it from scratch.
///
/// - Session time is *added* when a session closes (`record(_ sessions:)`).
/// - Planned vs. actual figures are *recomputed* for a day whenever its plan is saved
///   (`record(_ plan:)`), so editing or relabelling a task never double-counts.
public final class DailyTotalsCache {
    private let store: Store
    private let calendar: Calendar

    public init(store: Store, calendar: Calendar) {
        self.store = store
        self.calendar = calendar
    }

    public func load() throws -> DailyTotals {
        try store.loadDailyTotals()
    }

    public func record(_ sessions: [Session]) throws {
        guard !sessions.isEmpty else { return }
        var totals = try store.loadDailyTotals()
        for session in sessions {
            Self.add(session, to: &totals, calendar: calendar)
        }
        store.saveDailyTotals(totals)
    }

    public func record(_ plan: DayPlan) throws {
        var totals = try store.loadDailyTotals()
        let before = totals
        Self.apply(plan, to: &totals)
        if totals != before {
            store.saveDailyTotals(totals)
        }
    }

    /// Recomputes everything from every sessions file and plan file, and saves the result.
    @discardableResult
    public func rebuild() throws -> DailyTotals {
        var sessions: [Session] = []
        for month in try store.sessionMonths() {
            sessions += try store.loadSessions(monthOf: month)
        }
        var plans: [DayPlan] = []
        for date in try store.planDates() {
            try plans.append(store.loadPlan(for: date))
        }
        let totals = Self.build(sessions: sessions, plans: plans, calendar: calendar)
        store.saveDailyTotals(totals)
        return totals
    }

    // MARK: Pure updates

    public static func build(sessions: [Session], plans: [DayPlan], calendar: Calendar) -> DailyTotals {
        var totals = DailyTotals()
        for session in sessions {
            add(session, to: &totals, calendar: calendar)
        }
        for plan in plans {
            apply(plan, to: &totals)
        }
        return totals
    }

    public static func add(_ session: Session, to totals: inout DailyTotals, calendar: Calendar) {
        let parts = StatsCalculator.split(session, calendar: calendar)
        for (index, part) in parts.enumerated() {
            totals[part.date, session.labelID].seconds += part.seconds
            if index == 0 {
                totals[part.date, session.labelID].sessions += 1
            }
            totals.prune(part.date)
        }
    }

    /// Replaces the plan-derived figures for the plan's day.
    public static func apply(_ plan: DayPlan, to totals: inout DailyTotals) {
        let date = plan.date
        for label in Array(totals.days[date, default: [:]].keys) {
            totals[date, label].clearPlanFigures()
        }
        for task in plan.tasks where task.status == .done {
            var figures = LabelTotals()
            figures.tasksDone = 1
            figures.plannedMinutes = task.plannedMinutes
            figures.doneSeconds = task.brewedSeconds
            figures.tasksExtended = task.extendedMinutes > 0 ? 1 : 0
            figures.extendedMinutes = task.extendedMinutes
            totals[date, task.labelID].addPlanFigures(figures)
        }
        totals.prune(date)
    }
}
