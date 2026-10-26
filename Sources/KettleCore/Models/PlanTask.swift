import Foundation

/// One time block in a day plan. Named `PlanTask` to avoid clashing with Swift's `Task`.
public struct PlanTask: Codable, Identifiable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable {
        case pending, brewing, paused, done, skipped
    }

    public static let plannedMinutesRange = 1 ... 720

    public let id: UUID
    public var title: String
    public var labelID: UUID?
    /// The original estimate, clamped to `plannedMinutesRange`. Keep brewing doesn't change it.
    public var plannedMinutes: Int {
        didSet { plannedMinutes = Self.clamp(plannedMinutes) }
    }

    public var notes: String?
    public var status: Status
    /// Minutes added with Keep brewing. The block lasts `plannedMinutes + extendedMinutes`.
    public var extendedMinutes: Int
    /// Brewing time from closed sessions (before the latest pause).
    public var brewedSeconds: Int
    /// Start of the open session while `status == .brewing`, otherwise nil.
    public var brewingSince: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        labelID: UUID? = nil,
        plannedMinutes: Int,
        notes: String? = nil,
        status: Status = .pending,
        extendedMinutes: Int = 0,
        brewedSeconds: Int = 0,
        brewingSince: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.labelID = labelID
        self.plannedMinutes = Self.clamp(plannedMinutes)
        self.notes = notes
        self.status = status
        self.extendedMinutes = extendedMinutes
        self.brewedSeconds = brewedSeconds
        self.brewingSince = brewingSince
    }

    /// Planned length of the block including extensions.
    public var totalMinutes: Int {
        plannedMinutes + extendedMinutes
    }

    /// Brewing time so far, including the open session if brewing.
    public func brewedSeconds(at now: Date) -> TimeInterval {
        guard status == .brewing, let brewingSince else { return TimeInterval(brewedSeconds) }
        return TimeInterval(brewedSeconds) + max(0, now.timeIntervalSince(brewingSince))
    }

    /// Seconds left in the block at `now`. Negative in overtime.
    public func remainingSeconds(at now: Date) -> TimeInterval {
        TimeInterval(totalMinutes * 60) - brewedSeconds(at: now)
    }

    public var isFinished: Bool {
        status == .done || status == .skipped
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, labelID, plannedMinutes, notes, status, extendedMinutes, brewedSeconds, brewingSince
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            title: container.decode(String.self, forKey: .title),
            labelID: container.decodeIfPresent(UUID.self, forKey: .labelID),
            plannedMinutes: container.decode(Int.self, forKey: .plannedMinutes),
            notes: container.decodeIfPresent(String.self, forKey: .notes),
            status: container.decodeIfPresent(Status.self, forKey: .status) ?? .pending,
            extendedMinutes: container.decodeIfPresent(Int.self, forKey: .extendedMinutes) ?? 0,
            brewedSeconds: container.decodeIfPresent(Int.self, forKey: .brewedSeconds) ?? 0,
            brewingSince: container.decodeIfPresent(Date.self, forKey: .brewingSince)
        )
    }

    private static func clamp(_ minutes: Int) -> Int {
        min(max(minutes, plannedMinutesRange.lowerBound), plannedMinutesRange.upperBound)
    }
}
