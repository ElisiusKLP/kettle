import Foundation

/// What VoiceOver says about the menubar kettle: the task and the time left, never the steam.
public enum StatusDescription {
    /// Whole minutes the description mentions: left (rounded up), or over time (negative), nil
    /// when nothing is active. The app rebuilds the description only when this changes.
    public static func minutes(engine: TimerEngine, now: Date) -> Int? {
        guard let remaining = engine.remainingSeconds(at: now) else { return nil }
        return remaining > 0 ? Int((remaining / 60).rounded(.up)) : -Int((-remaining / 60).rounded(.down))
    }

    public static func text(engine: TimerEngine, now: Date) -> String {
        guard let task = engine.activeTask, let minutes = minutes(engine: engine, now: now) else {
            return PlanEngine.isComplete(engine.plan) ? "Kettle, all brewed for today" : "Kettle, nothing brewing"
        }
        let state = task.status == .paused ? "paused" : "brewing"
        return "Kettle, \(task.title), \(state), \(spoken(minutes: minutes))"
    }

    /// "23 minutes left", "1 minute left", "time's up", "5 minutes over time".
    public static func spoken(minutes: Int) -> String {
        switch minutes {
        case 1: "1 minute left"
        case 2...: "\(minutes) minutes left"
        case 0: "time's up"
        case -1: "1 minute over time"
        default: "\(-minutes) minutes over time"
        }
    }

    /// A countdown read aloud, e.g. "23 minutes 41 seconds left" or "42 seconds over time".
    public static func spoken(remaining: TimeInterval) -> String {
        let over = remaining <= 0
        let total = Int((over ? -remaining : remaining).rounded(over ? .down : .up))
        let minutes = total / 60
        let seconds = total % 60
        var parts: [String] = []
        if minutes > 0 {
            parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes")
        }
        if seconds > 0 || minutes == 0 {
            parts.append(seconds == 1 ? "1 second" : "\(seconds) seconds")
        }
        return parts.joined(separator: " ") + (over ? " over time" : " left")
    }
}
