import Foundation

/// One label's totals for one day.
public struct LabelTotals: Codable, Hashable, Sendable {
    // From sessions, added as each one closes.

    /// Actual brewing time on this day (sessions are split at midnight).
    public var seconds = 0
    /// Sessions that started on this day.
    public var sessions = 0

    // From the day's plan, recomputed whenever it's saved.

    /// Tasks marked done.
    public var tasksDone = 0
    /// The original estimates of the done tasks.
    public var plannedMinutes = 0
    /// Time actually brewed on the done tasks, to compare with `plannedMinutes`.
    public var doneSeconds = 0
    /// Done tasks that were extended with Keep brewing.
    public var tasksExtended = 0
    public var extendedMinutes = 0

    public init() {}

    public var isEmpty: Bool {
        self == LabelTotals()
    }

    public static func += (lhs: inout LabelTotals, rhs: LabelTotals) {
        lhs.seconds += rhs.seconds
        lhs.sessions += rhs.sessions
        lhs.addPlanFigures(rhs)
    }

    mutating func addPlanFigures(_ other: LabelTotals) {
        tasksDone += other.tasksDone
        plannedMinutes += other.plannedMinutes
        doneSeconds += other.doneSeconds
        tasksExtended += other.tasksExtended
        extendedMinutes += other.extendedMinutes
    }

    mutating func clearPlanFigures() {
        tasksDone = 0
        plannedMinutes = 0
        doneSeconds = 0
        tasksExtended = 0
        extendedMinutes = 0
    }
}

/// The contents of `stats/daily-totals.json`: per-day, per-label totals, so stats never need
/// the raw session history. Tasks without a label are under the `nil` label.
public struct DailyTotals: StoredDocument, Hashable {
    public static let kind = DocumentKind.dailyTotals
    /// The JSON key used for tasks without a label.
    static let unlabeledKey = "none"

    public var days: [LocalDate: [UUID?: LabelTotals]]

    public init(days: [LocalDate: [UUID?: LabelTotals]] = [:]) {
        self.days = days
    }

    /// The totals for one day and label, creating an empty entry if needed.
    subscript(date: LocalDate, label: UUID?) -> LabelTotals {
        get { days[date]?[label] ?? LabelTotals() }
        set { days[date, default: [:]][label] = newValue }
    }

    /// Drops empty entries and days.
    mutating func prune(_ date: LocalDate) {
        days[date] = days[date]?.filter { !$0.value.isEmpty }
        if days[date]?.isEmpty == true {
            days[date] = nil
        }
    }

    // Stored as {"days": {"yyyy-MM-dd": {"<label UUID or none>": {...}}}}.

    private enum CodingKeys: String, CodingKey {
        case days
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode([String: [String: LabelTotals]].self, forKey: .days)
        var days: [LocalDate: [UUID?: LabelTotals]] = [:]
        for (dateKey, labels) in raw {
            guard let date = LocalDate(dateKey) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .days, in: container, debugDescription: "Invalid date \(dateKey)"
                )
            }
            for (labelKey, totals) in labels {
                if labelKey == Self.unlabeledKey {
                    days[date, default: [:]][nil] = totals
                } else if let id = UUID(uuidString: labelKey) {
                    days[date, default: [:]][id] = totals
                } else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .days, in: container, debugDescription: "Invalid label \(labelKey)"
                    )
                }
            }
        }
        self.days = days
    }

    public func encode(to encoder: Encoder) throws {
        var raw: [String: [String: LabelTotals]] = [:]
        for (date, labels) in days {
            raw[date.description] = Dictionary(uniqueKeysWithValues: labels.map { label, totals in
                (label?.uuidString ?? Self.unlabeledKey, totals)
            })
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(raw, forKey: .days)
    }
}
