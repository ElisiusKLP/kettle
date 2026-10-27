import AppKit
import KettleCore
import KettleIcon

/// The menubar kettle: the pre-rendered icons, the countdown, and the single timer that
/// drives them. It touches the status item only when what's shown changes, and doesn't tick
/// at all while nothing is brewing or the Mac (or its screens) are asleep.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: KettleModel
    private let statusItem: NSStatusItem
    private let images: [IconState: NSImage]
    private let clock = SystemClock()
    private let timer = TickTimer()
    private var ticker = MenubarTicker()
    private var power: PowerEvents?

    init(model: KettleModel, style: KettleIcon.Style) {
        self.model = model
        images = KettleIcon.allImages(style: style)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.imagePosition = .imageLeft
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

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

    // MARK: Menu (temporary until the popover in build step 9)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let engine = model.engine
        if let task = engine.activeTask {
            let remaining = CountdownFormatter.string(
                remaining: task.remainingSeconds(at: clock.now),
                precision: .seconds
            )
            menu.addItem(
                withTitle: "\(task.status == .paused ? "Paused" : "Brewing"): \(task.title) \(remaining)",
                action: nil,
                keyEquivalent: ""
            )
        } else if PlanEngine.isComplete(engine.plan) {
            menu.addItem(withTitle: "All brewed for today.", action: nil, keyEquivalent: "")
        } else if engine.plan.tasks.isEmpty {
            menu.addItem(withTitle: "Nothing on the stove.", action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())

        let toggleTitle = engine.isBrewing ? "Pause" : engine.activeTask == nil ? "Start" : "Resume"
        add(
            toggleTitle,
            to: menu,
            enabled: engine.activeTask != nil || engine.plan.tasks.contains { $0.status == .pending }
        ) {
            $0.toggle()
        }
        add("Done", to: menu, enabled: engine.activeTask != nil) { $0.done() }
        add("Keep brewing +\(model.settings.extendMinutes)m", to: menu, enabled: engine.isBrewing) { $0.keepBrewing() }
        add("Skip", to: menu, enabled: engine.activeTask != nil) { $0.skip() }
        menu.addItem(.separator())
        add("Add 2-minute test task", to: menu, enabled: true) {
            $0.add(QuickAddEntry(title: "Steam test", minutes: 2, labelName: "qa"))
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Kettle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func add(_ title: String, to menu: NSMenu, enabled: Bool, action: @escaping (KettleModel) -> Void) {
        let item = MenuAction(title: title) { [weak self] in
            guard let self else { return }
            action(model)
            refresh()
        }
        item.isEnabled = enabled
        menu.addItem(item)
    }
}

/// A menu item that runs a closure.
private final class MenuAction: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("not used")
    }

    @objc private func run() {
        handler()
    }
}
