import AppKit

/// Tells the app when to stop and resume ticking: while the Mac sleeps, and while its screens
/// are off (nobody can see the menubar).
final class PowerEvents {
    private(set) var isAsleep = false

    private var systemAsleep = false
    private var screensAsleep = false
    private var observers: [NSObjectProtocol] = []
    private let onSleep: () -> Void
    private let onWake: () -> Void

    init(onSleep: @escaping () -> Void, onWake: @escaping () -> Void) {
        self.onSleep = onSleep
        self.onWake = onWake
        observe(NSWorkspace.willSleepNotification) { $0.systemAsleep = true }
        observe(NSWorkspace.didWakeNotification) { $0.systemAsleep = false }
        observe(NSWorkspace.screensDidSleepNotification) { $0.screensAsleep = true }
        observe(NSWorkspace.screensDidWakeNotification) { $0.screensAsleep = false }
    }

    deinit {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    private func observe(_ name: Notification.Name, _ change: @escaping (PowerEvents) -> Void) {
        let center = NSWorkspace.shared.notificationCenter
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            change(self)
            update()
        }
        observers.append(observer)
    }

    private func update() {
        let wasAsleep = isAsleep
        isAsleep = systemAsleep || screensAsleep
        if isAsleep, !wasAsleep {
            Log.app.debug("Sleeping: ticking stopped")
            onSleep()
        } else if !isAsleep, wasAsleep {
            Log.app.debug("Awake: recomputing from timestamps")
            onWake()
        }
    }
}
