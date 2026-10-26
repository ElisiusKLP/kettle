import Foundation

/// One actual stretch of work, used for stats.
public struct Session: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var taskID: UUID
    public var labelID: UUID?
    public var start: Date
    public var end: Date
    /// Total minutes added via Keep brewing during this session.
    public var extensionsMinutes: Int

    public init(
        id: UUID = UUID(),
        taskID: UUID,
        labelID: UUID?,
        start: Date,
        end: Date,
        extensionsMinutes: Int = 0
    ) {
        self.id = id
        self.taskID = taskID
        self.labelID = labelID
        self.start = start
        self.end = end
        self.extensionsMinutes = extensionsMinutes
    }

    public var duration: TimeInterval {
        end.timeIntervalSince(start)
    }
}

/// The contents of `sessions/yyyy-MM.json`.
public struct SessionLog: StoredDocument, Hashable {
    public static let kind = DocumentKind.sessions

    public var sessions: [Session]

    public init(sessions: [Session] = []) {
        self.sessions = sessions
    }
}
