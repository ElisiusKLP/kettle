import Foundation

/// The ordered time blocks for one day, stored in `plans/yyyy-MM-dd.json`.
public struct DayPlan: StoredDocument, Identifiable, Hashable {
    public static let kind = DocumentKind.plan

    public var id: LocalDate {
        date
    }

    public var date: LocalDate
    /// Execution order.
    public var tasks: [PlanTask]
    /// Optional anchor for the first block, e.g. 09:00.
    public var startTime: LocalTime?

    public init(date: LocalDate, tasks: [PlanTask] = [], startTime: LocalTime? = nil) {
        self.date = date
        self.tasks = tasks
        self.startTime = startTime
    }
}
