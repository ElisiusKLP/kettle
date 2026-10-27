import Foundation

public enum StoreError: Error, Equatable {
    /// The file exists but couldn't be decoded or migrated. Kettle won't overwrite it.
    case unreadable(path: String, reason: String)
    /// A save targeted a file that previously failed to load.
    case writeBlocked(path: String)
}

/// Everything the app holds in memory at launch (SPEC section 7).
public struct StartupSnapshot: Equatable, Sendable {
    public var settings: AppSettings
    public var labels: [Label]
    public var today: DayPlan
}

/// Persistence for Kettle's data. Loads return defaults for files that don't exist yet.
/// Saves are debounced; `flush()` writes everything pending immediately.
public protocol Store: AnyObject {
    func loadSettings() throws -> AppSettings
    func saveSettings(_ settings: AppSettings)
    func loadLabels() throws -> [Label]
    func saveLabels(_ labels: [Label])
    func loadPlan(for date: LocalDate) throws -> DayPlan
    func savePlan(_ plan: DayPlan)
    /// Sessions in the month containing `date`. Only for export and cache rebuilds.
    func loadSessions(monthOf date: LocalDate) throws -> [Session]
    /// Appends to the month file of the session's start day.
    func appendSession(_ session: Session) throws
    /// Replaces the sessions file for the month containing `date` (used by import).
    func saveSessions(_ sessions: [Session], monthOf date: LocalDate)
    func loadDailyTotals() throws -> DailyTotals
    func saveDailyTotals(_ totals: DailyTotals)
    /// Days that have a plan file, oldest first. Only for export and cache rebuilds.
    func planDates() throws -> [LocalDate]
    /// The first day of every month that has a sessions file, oldest first.
    func sessionMonths() throws -> [LocalDate]
    func flush() throws
    /// Deletes Kettle's files in the data folder (and anything pending), nothing else.
    func deleteAll() throws
}

public extension Store {
    /// Loads only settings, labels and today's plan.
    func loadStartupSnapshot(today: LocalDate) throws -> StartupSnapshot {
        try StartupSnapshot(settings: loadSettings(), labels: loadLabels(), today: loadPlan(for: today))
    }
}
