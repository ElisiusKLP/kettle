import Foundation

/// Decides what the menubar shows on each tick, and reports only what changed, so the app
/// touches `NSStatusItem` at most once per visible change (SPEC section 8, rule 4).
///
/// `update` doesn't allocate in the default `.iconAndTime` format; `.iconTitleAndTime` builds
/// one short string per change.
public struct MenubarTicker {
    public struct Update: Equatable {
        /// The new icon, or nil if unchanged.
        public var icon: IconState?
        /// The new title, or nil if unchanged.
        public var title: String?
    }

    public private(set) var icon: IconState?
    public private(set) var title: String?

    public init() {}

    public mutating func update(engine: TimerEngine, now: Date, settings: AppSettings) -> Update {
        let newIcon = engine.iconState(at: now)
        let newTitle = Self.title(engine: engine, now: now, settings: settings)
        var update = Update()
        if newIcon != icon {
            icon = newIcon
            update.icon = newIcon
        }
        if newTitle != title {
            title = newTitle
            update.title = newTitle
        }
        return update
    }

    /// Forgets what was shown, so the next update reports everything (e.g. after a settings change).
    public mutating func reset() {
        icon = nil
        title = nil
    }

    static func title(engine: TimerEngine, now: Date, settings: AppSettings) -> String {
        guard let task = engine.activeTask, settings.menubarFormat != .iconOnly else { return "" }
        let countdown = CountdownFormatter.string(
            remaining: task.remainingSeconds(at: now),
            precision: settings.timerPrecision
        )
        return settings.menubarFormat == .iconTitleAndTime ? task.title + " " + countdown : countdown
    }

    /// When to wake up next, and how late the wake-up may be.
    public struct NextTick: Equatable {
        public let delay: TimeInterval
        public let leeway: TimeInterval
    }

    /// Leeway for ticks that show seconds, and for ticks that only show minutes.
    public static let fineLeeway: TimeInterval = 0.2
    public static let coarseLeeway: TimeInterval = 5

    /// The next tick, or nil when nothing is brewing (no ticking at all). Ticks land just after
    /// the countdown's own second or minute boundaries, so each one changes the title. The tick
    /// that switches a smart countdown to seconds gets the fine leeway, so the last minute
    /// starts on time.
    public static func nextTick(engine: TimerEngine, now: Date, precision: TimerPrecision) -> NextTick? {
        guard engine.isBrewing, let remaining = engine.remainingSeconds(at: now) else { return nil }
        let unit: TimeInterval = precision.showsSeconds(remaining: remaining) ? 1 : 60
        // Counting down, the display changes when `remaining` crosses a multiple of `unit`;
        // in overtime, when the overdue time does.
        let position = (remaining > 0 ? remaining : -remaining) / unit
        let fraction = position - position.rounded(.down)
        let steps = remaining > 0 ? (fraction > 0 ? fraction : 1) : 1 - fraction
        // Land just after the boundary so rounding shows the new value.
        let delay = steps * unit + 0.005
        let fine = unit == 1 || precision.showsSeconds(remaining: remaining - delay)
        return NextTick(delay: delay, leeway: fine ? fineLeeway : coarseLeeway)
    }
}
