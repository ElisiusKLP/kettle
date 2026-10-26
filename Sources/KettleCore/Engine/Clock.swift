import Foundation

/// The source of "now" for everything in KettleCore. Tests inject a fake one.
public protocol Clock {
    var now: Date { get }
}

public struct SystemClock: Clock {
    public init() {}

    public var now: Date {
        Date()
    }
}
