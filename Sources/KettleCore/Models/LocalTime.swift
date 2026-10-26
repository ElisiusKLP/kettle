import Foundation

/// A wall-clock time of day with minute precision, stored as `HH:mm`.
public struct LocalTime: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let hour: Int
    public let minute: Int

    public static let midnight = LocalTime(validHour: 0, minute: 0)

    public init?(hour: Int, minute: Int) {
        guard (0 ... 23).contains(hour), (0 ... 59).contains(minute) else { return nil }
        self.init(validHour: hour, minute: minute)
    }

    /// Parses `HH:mm`.
    public init?(_ string: String) {
        let parts = string.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1])
        else { return nil }
        self.init(hour: hour, minute: minute)
    }

    private init(validHour hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public var minutesSinceMidnight: Int {
        hour * 60 + minute
    }

    public var description: String {
        String(format: "%02d:%02d", hour, minute)
    }

    public static func < (lhs: LocalTime, rhs: LocalTime) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let time = LocalTime(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected HH:mm, got \(string)")
        }
        self = time
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
