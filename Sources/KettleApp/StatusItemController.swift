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

    init(model: KettleModel, style: KettleIcon.Style) {
        self.model = model
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
        popover = PopoverController(model: model) { [weak self] in self?.refresh() }

        timer.onFire = { [weak self] in self?.tick() }
        power = PowerEvents(
            onSleep: { [weak self] in self?.sleep() },
            onWake: { [weak self] in self?.wake() }
        )
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

        if let next = MenubarTicker.nextTick(engine: model.engine, now: now, precision: model.settings.timerPrecision) {
            timer.schedule(after: next.delay, leeway: .milliseconds(Int(next.leeway * 1000)))
        } else {
            let midnight = LocalDate(now, in: .autoupdatingCurrent).adding(days: 1).date(in: .autoupdatingCurrent)
            timer.schedule(after: midnight.timeIntervalSince(now) + 1, leeway: .seconds(60))
        }
    }

    private func sleep() {
        timer.cancel()
        model.flush()
    }

    private func wake() {
        // Remaining time comes from timestamps, so recomputing is all that's needed.
        tick()
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
        let settings = menu.addItem(withTitle: "Settings…", action: nil, keyEquivalent: ",")
        settings.isEnabled = false // build step 10
        let stats = menu.addItem(withTitle: "Stats…", action: nil, keyEquivalent: "")
        stats.isEnabled = false // build step 12
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Kettle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
}
