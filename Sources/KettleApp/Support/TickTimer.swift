import Foundation

/// The app's one timer: a single one-shot `DispatchSourceTimer` on the main queue, re-armed
/// for each tick. Its clock stops while the Mac sleeps, so wake-up handling recomputes
/// everything from timestamps instead.
final class TickTimer {
    var onFire: (() -> Void)?

    private let source: DispatchSourceTimer

    init() {
        source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .distantFuture)
        source.setEventHandler { [weak self] in self?.onFire?() }
        source.activate()
    }

    deinit {
        source.cancel()
    }

    func schedule(after delay: TimeInterval, leeway: DispatchTimeInterval) {
        source.schedule(deadline: .now() + max(0, delay), repeating: .never, leeway: leeway)
    }

    func cancel() {
        source.schedule(deadline: .distantFuture)
    }
}
