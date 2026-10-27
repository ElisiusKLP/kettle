import Foundation

/// Short durations for stats: `45m`, `3h 05m`, `0m`.
public enum DurationText {
    public static func short(seconds: Int) -> String {
        let minutes = Int((Double(max(seconds, 0)) / 60).rounded())
        guard minutes >= 60 else { return "\(minutes)m" }
        return String(format: "%dh %02dm", minutes / 60, minutes % 60)
    }
}
