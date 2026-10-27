import Foundation

/// The time's-up notification, worked out ahead of time so it can be scheduled with the system
/// and fire even while Kettle isn't ticking (asleep, screens off).
public struct WhistleRequest: Equatable, Sendable {
    public let taskID: UUID
    public let fireDate: Date
    public let title: String
    public let body: String
    public let playsSound: Bool
    /// In overtime mode the task keeps brewing, so the notification offers Done. Otherwise the
    /// task has already finished and only Keep brewing applies.
    public let offersDone: Bool
}

public enum Whistle {
    /// The notification to schedule now, or nil: notifications are off, nothing is brewing, or
    /// the block has already run out (no notifications after the fact, e.g. on launch).
    public static func request(engine: TimerEngine, now: Date, settings: AppSettings) -> WhistleRequest? {
        guard settings.notifyOnFinish, let task = engine.activeTask, let fireDate = engine.whistleDate(at: now) else {
            return nil
        }
        return WhistleRequest(
            taskID: task.id,
            fireDate: fireDate,
            title: "Whistle!",
            body: "\u{201C}\(task.title)\u{201D} is done.",
            playsSound: settings.whistleSound,
            offersDone: settings.overtime
        )
    }

    /// Titles of the notification's Keep brewing actions, e.g. "Keep brewing +10m" and "+5m".
    public static func keepBrewingTitles(_ settings: AppSettings) -> (main: String, secondary: String) {
        ("Keep brewing +\(settings.extendMinutes)m", "+\(settings.secondaryExtendMinutes)m")
    }

    /// With notifications off, Kettle plays the whistle itself when the block runs out.
    public static func playsSoundInApp(_ settings: AppSettings) -> Bool {
        settings.whistleSound && !settings.notifyOnFinish
    }
}
