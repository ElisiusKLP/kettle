import Foundation

/// The ranges the Stats window offers.
public enum StatsPeriod: Hashable, Sendable {
    case today
    case thisWeek
    case thisMonth
    case custom(ClosedRange<LocalDate>)

    public func range(today: LocalDate, weekStartsOn: Weekday) -> ClosedRange<LocalDate> {
        switch self {
        case .today:
            today ... today
        case .thisWeek:
            today.startOfWeek(startingOn: weekStartsOn) ... today.startOfWeek(startingOn: weekStartsOn).adding(days: 6)
        case .thisMonth:
            today.startOfMonth ... today.endOfMonth
        case let .custom(range):
            range
        }
    }
}

/// One row of the totals table, with the label's display details resolved.
public struct StatsRow: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case label(Label)
        /// Tasks without a label.
        case unlabeled
        /// A label ID that no longer exists in `labels.json`.
        case unknown(UUID)
    }

    public let kind: Kind
    public let totals: LabelTotals

    public var labelID: UUID? {
        switch kind {
        case let .label(label): label.id
        case .unlabeled: nil
        case let .unknown(id): id
        }
    }
}

/// One day's brewing time per label, for the stacked daily chart.
public struct DaySeconds: Equatable, Sendable {
    public let date: LocalDate
    public let secondsByLabel: [UUID?: Int]
}

/// Pure functions behind the Stats window.
public enum StatsCalculator {
    /// Splits a session at local midnights into whole seconds per day.
    public static func split(_ session: Session, calendar: Calendar) -> [(date: LocalDate, seconds: Int)] {
        guard session.end > session.start else { return [] }
        var parts: [(date: LocalDate, seconds: Int)] = []
        var cursor = session.start
        while cursor < session.end {
            let date = LocalDate(cursor, in: calendar)
            let nextMidnight = date.adding(days: 1).date(in: calendar)
            let partEnd = min(session.end, nextMidnight)
            parts.append((date, Int(partEnd.timeIntervalSince(cursor).rounded())))
            cursor = partEnd
        }
        return parts
    }

    /// Totals per label over `range`. Archived labels are included like any other.
    public static func totalsByLabel(_ totals: DailyTotals, in range: ClosedRange<LocalDate>) -> [UUID?: LabelTotals] {
        var result: [UUID?: LabelTotals] = [:]
        for dayNumber in range.lowerBound.dayNumber ... range.upperBound.dayNumber {
            guard let day = totals.days[LocalDate(dayNumber: dayNumber)] else { continue }
            for (label, labelTotals) in day {
                result[label, default: LabelTotals()] += labelTotals
            }
        }
        return result
    }

    /// Brewing seconds per label for every day in `range`, including empty days.
    public static func dailySeconds(_ totals: DailyTotals, in range: ClosedRange<LocalDate>) -> [DaySeconds] {
        (range.lowerBound.dayNumber ... range.upperBound.dayNumber).map { dayNumber in
            let date = LocalDate(dayNumber: dayNumber)
            let seconds = (totals.days[date] ?? [:]).compactMapValues { $0.seconds > 0 ? $0.seconds : nil }
            return DaySeconds(date: date, secondsByLabel: seconds)
        }
    }

    /// Table rows, most brewing time first (ties by name). Archived labels keep their name and colour.
    public static func rows(_ byLabel: [UUID?: LabelTotals], labels: [Label]) -> [StatsRow] {
        let labelsByID = Dictionary(labels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return byLabel.filter { !$0.value.isEmpty }.map { id, totals in
            let kind: StatsRow.Kind = if let id {
                labelsByID[id].map(StatsRow.Kind.label) ?? .unknown(id)
            } else {
                .unlabeled
            }
            return StatsRow(kind: kind, totals: totals)
        }
        .sorted { lhs, rhs in
            lhs.totals.seconds != rhs.totals.seconds
                ? lhs.totals.seconds > rhs.totals.seconds
                : sortKey(lhs.kind) < sortKey(rhs.kind)
        }
    }

    /// Ties sort labels by name, then "No label", then unknown labels.
    private static func sortKey(_ kind: StatsRow.Kind) -> (Int, String) {
        switch kind {
        case let .label(label): (0, label.name.lowercased())
        case .unlabeled: (1, "")
        case let .unknown(id): (2, id.uuidString)
        }
    }
}
