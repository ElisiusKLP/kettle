import Foundation

public enum MenubarFormat: String, Codable, Sendable, CaseIterable {
    case iconOnly, iconAndTime, iconTitleAndTime
}

public enum TimerPrecision: String, Codable, Sendable, CaseIterable {
    /// Minutes, switching to seconds for the final minute and the first minute of overtime.
    /// Nearly as light as `.minutes`, with a live countdown to the whistle.
    case smart
    /// Seconds all the time. Redrawing the menubar every second costs about 0.4% CPU.
    case seconds
    /// Minutes all the time: the lowest energy use.
    case minutes

    /// Whether the countdown shows seconds with `remaining` seconds left (negative in overtime).
    public func showsSeconds(remaining: TimeInterval) -> Bool {
        switch self {
        case .seconds: true
        case .minutes: false
        case .smart: remaining > 0 ? remaining <= 60 : -remaining < 60
        }
    }
}

public enum Weekday: String, Codable, Sendable, CaseIterable {
    case sunday, monday, tuesday, wednesday, thursday, friday, saturday

    /// `Calendar` numbering: Sunday is 1.
    public var calendarWeekday: Int {
        Self.allCases.firstIndex(of: self)! + 1
    }
}

/// The contents of `settings.json`. Missing or invalid keys fall back to their defaults,
/// so a hand-edited or older file never fails to load.
public struct AppSettings: StoredDocument, Hashable {
    public static let kind = DocumentKind.settings

    /// The "Keep brewing" amount.
    public var extendMinutes = 10
    public var secondaryExtendMinutes = 5
    /// Minutes added or removed by a task's duration stepper.
    public var resizeStepMinutes = 5
    public var autoStartNext = false
    public var menubarFormat = MenubarFormat.iconAndTime
    public var timerPrecision = TimerPrecision.smart
    public var whistleSound = true
    public var notifyOnFinish = true
    public var launchAtLogin = false
    public var weekStartsOn = Weekday.monday

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case extendMinutes, secondaryExtendMinutes, resizeStepMinutes, autoStartNext, menubarFormat, timerPrecision
        case whistleSound, notifyOnFinish, launchAtLogin, weekStartsOn
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, default fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        let defaults = AppSettings()
        extendMinutes = value(.extendMinutes, default: defaults.extendMinutes)
        secondaryExtendMinutes = value(.secondaryExtendMinutes, default: defaults.secondaryExtendMinutes)
        resizeStepMinutes = max(1, value(.resizeStepMinutes, default: defaults.resizeStepMinutes))
        autoStartNext = value(.autoStartNext, default: defaults.autoStartNext)
        menubarFormat = value(.menubarFormat, default: defaults.menubarFormat)
        timerPrecision = value(.timerPrecision, default: defaults.timerPrecision)
        whistleSound = value(.whistleSound, default: defaults.whistleSound)
        notifyOnFinish = value(.notifyOnFinish, default: defaults.notifyOnFinish)
        launchAtLogin = value(.launchAtLogin, default: defaults.launchAtLogin)
        weekStartsOn = value(.weekStartsOn, default: defaults.weekStartsOn)
    }
}
