import Foundation

/// How much steam the menubar kettle shows, in six discrete steps (SPEC section 6.2).
public enum SteamLevel: Int, Comparable, CaseIterable, Sendable {
    /// Done, idle or out of time.
    case none = 0
    /// Up to 20% left: one faint, short wisp.
    case one
    /// Over 20% left: two short wisps, the second faint.
    case two
    /// Over 40% left: two wisps.
    case three
    /// Over 60% left: three wisps, the outer one shorter and fainter.
    case four
    /// Over 80% left: three tall wisps.
    case five

    /// Maps the fraction of the block still left to a step. Boundaries belong to the lower
    /// step, so exactly 80% left is `.four` and 0% is `.none`.
    public init(remaining: TimeInterval, planned: TimeInterval) {
        guard planned > 0, remaining > 0 else {
            self = .none
            return
        }
        let fraction = remaining / planned
        self = if fraction > 0.8 {
            .five
        } else if fraction > 0.6 {
            .four
        } else if fraction > 0.4 {
            .three
        } else if fraction > 0.2 {
            .two
        } else {
            .one
        }
    }

    public static func < (lhs: SteamLevel, rhs: SteamLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What the menubar kettle shows (SPEC section 6.3). The icon is swapped only when this changes.
public enum IconState: Hashable, Sendable {
    /// Nothing brewing: kettle outline, no steam.
    case idle
    /// Brewing with steam at the current step (never `.none`; zero left is `.whistling`).
    case brewing(SteamLevel)
    /// Paused: kettle at 50% alpha, steam frozen at its step.
    case paused(SteamLevel)
    /// Out of time: full burst of steam and whistle lines.
    case whistling
    /// Every task done or skipped.
    case dayComplete

    /// Every state the icon can be in, for pre-rendering at launch.
    public static let allCases: [IconState] = [.idle]
        + SteamLevel.allCases.filter { $0 != .none }.map(IconState.brewing)
        + SteamLevel.allCases.map(IconState.paused)
        + [.whistling, .dayComplete]
}
