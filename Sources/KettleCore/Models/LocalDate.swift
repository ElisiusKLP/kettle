import Foundation

/// A calendar day with no time zone, stored as `yyyy-MM-dd`.
///
/// Day arithmetic is plain integer math on the proleptic Gregorian calendar, so it never
/// allocates and is unaffected by daylight saving time.
public struct LocalDate: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (1 ... 9999).contains(year), (1 ... 12).contains(month),
              (1 ... Self.daysInMonth(year: year, month: month)).contains(day)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `yyyy-MM-dd`.
    public init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The day `date` falls on in `calendar`'s time zone.
    public init(_ date: Date, in calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(dayNumber: Self.dayNumber(
            year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1
        ))
    }

    /// Days since 1970-01-01.
    public init(dayNumber: Int) {
        // Howard Hinnant's civil_from_days.
        let z = dayNumber + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
    }

    /// Days since 1970-01-01.
    public var dayNumber: Int {
        Self.dayNumber(year: year, month: month, day: day)
    }

    public func adding(days: Int) -> LocalDate {
        LocalDate(dayNumber: dayNumber + days)
    }

    /// `Calendar` weekday numbering: Sunday is 1, Saturday is 7.
    public var weekday: Int {
        // 1970-01-01 was a Thursday (5).
        ((dayNumber + 4) % 7 + 7) % 7 + 1
    }

    /// The first day of the week containing this date.
    public func startOfWeek(startingOn first: Weekday) -> LocalDate {
        adding(days: -((weekday - first.calendarWeekday + 7) % 7))
    }

    public var startOfMonth: LocalDate {
        LocalDate(dayNumber: dayNumber - (day - 1))
    }

    public var endOfMonth: LocalDate {
        adding(days: Self.daysInMonth(year: year, month: month) - day)
    }

    /// `yyyy-MM`, used to name monthly session files.
    public var monthKey: String {
        String(format: "%04d-%02d", year, month)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// The moment `time` occurs on this day in `calendar`'s time zone.
    public func date(at time: LocalTime = .midnight, in calendar: Calendar) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: time.hour, minute: time.minute)
        guard let date = calendar.date(from: components) else {
            preconditionFailure("\(self) \(time) is not representable in \(calendar.identifier)")
        }
        return date
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let date = LocalDate(string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected yyyy-MM-dd, got \(string)"
            )
        }
        self = date
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    /// Howard Hinnant's days_from_civil.
    private static func dayNumber(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let shiftedMonth = (month + 9) % 12
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}
