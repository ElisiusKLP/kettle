import AppKit
import KettleCore
import KettleIcon

/// The menubar kettle: the pre-rendered icons, the countdown, and the single timer that
/// drives them. It touches the status item only when what's shown changes, and doesn't tick
/// at all while nothing is brewing or the Mac (or its screens) are asleep. Left-click opens
/// the popover; right-click opens a small menu.
final class StatusItemController: NSObject {
    private let model: KettleModel
    private let statusItem: NSStatusItem
    private let images: [IconState: NSImage]
    private let clock = SystemClock()
    private let timer = TickTimer()
    private var ticker = MenubarTicker()
    private var power: PowerEvents?
    private var popover: PopoverController?
    private var settingsWindow: SettingsWindowController?
    private var notifier: WhistleNotifier?
    private let style: KettleIcon.Style
    /// Tilted whistling frames for the one-off wiggle, rendered the first time it plays.
    private lazy var wiggleFrames: [NSImage] = [0.14, -0.14, 0.09, -0.09, 0.04].map {
        KettleIcon.image(for: .whistling, style: style, rotation: $0)
    }

    init(model: KettleModel, style: KettleIcon.Style, dataFolder: URL) {
        self.model = model
        self.style = style
        images = KettleIcon.allImages(style: style)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.imagePosition = .imageLeft
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        settingsWindow = SettingsWindowController(model: model, dataFolder: dataFolder) { [weak self] in
            self?.settingsDidChange()
        }
        notifier = WhistleNotifier(model: model) { [weak self] in self?.modelDidChange() }
        popover = PopoverController(
            model: model,
            onChange: { [weak self] in self?.modelDidChange() },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )

        timer.onFire = { [weak self] in self?.tick() }
        power = PowerEvents(
            onSleep: { [weak self] in self?.sleep() },
            onWake: { [weak self] in self?.wake() }
        )
        modelDidChange()
    }

    /// After an action (popover, notification, settings): reschedule the whistle and redraw.
    func modelDidChange() {
        notifier?.update()
        refresh()
    }

    // MARK: Ticking

    private func tick() {
        if !model.engine.isBrewing {
            // An idle timer only fires at midnight.
            model.rollOverIfNeeded()
        }
        refresh()
    }

    /// Updates the menubar from the model and schedules the next tick.
    func refresh() {
        guard power?.isAsleep != true else { return }
        let now = clock.now
        let update = ticker.update(engine: model.engine, now: now, settings: model.settings)
        if let icon = update.icon {
            statusItem.button?.image = images[icon]
        }
        if let title = update.title {
            statusItem.button?.title = title
        }
        if update.startedWhistling {
            whistle()
        }

        if let next = MenubarTicker.nextTick(engine: model.engine, now: now, precision: model.settings.timerPrecision) {
            timer.schedule(after: next.delay, leeway: .milliseconds(Int(next.leeway * 1000)))
        } else {
            let midnight = LocalDate(now, in: .autoupdatingCurrent).adding(days: 1).date(in: .autoupdatingCurrent)
            timer.schedule(after: midnight.timeIntervalSince(now) + 1, leeway: .seconds(60))
        }
    }

    /// The format or precision may have changed, so redraw everything.
    private func settingsDidChange() {
        ticker.reset()
        modelDidChange()
    }

    /// The block just ran out: one short wiggle (none with Reduce Motion), and the whistle sound
    /// when notifications (which bring their own sound) are off.
    private func whistle() {
        if Whistle.playsSoundInApp(model.settings) {
            NSSound(named: "Glass")?.play()
        }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let frames = wiggleFrames + [images[.whistling]].compactMap { $0 }
        for (index, frame) in frames.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 * Double(index)) { [weak self] in
                // Stop if the state changed meanwhile (e.g. Done straight away).
                guard let self, ticker.icon == .whistling else { return }
                statusItem.button?.image = frame
            }
        }
    }

    @objc private func openSettings() {
        popover?.close()
        settingsWindow?.show()
    }

    private func sleep() {
        timer.cancel()
        model.flush()
    }

    private func wake() {
        // Remaining time comes from timestamps, so recomputing is all that's needed.
        tick()
        notifier?.update()
    }

    // MARK: Clicks

    @objc private func clicked() {
        guard let button = statusItem.button else { return }
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            popover?.close()
            showMenu()
        } else {
            popover?.toggle(relativeTo: button)
        }
    }

    /// Built when needed and detached again, so a left-click keeps opening the popover.
    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        let stats = menu.addItem(withTitle: "Stats…", action: nil, keyEquivalent: "")
        stats.isEnabled = false // build step 12
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Kettle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
}
