import AppKit
import KettleCore
import SwiftUI

/// Creates the Stats window (and with it everything Swift Charts) on demand, and lets go of it
/// when it closes (SPEC section 8, rule 2).
final class StatsWindowController: NSObject, NSWindowDelegate {
    private let model: KettleModel
    private var window: NSWindow?

    init(model: KettleModel) {
        self.model = model
    }

    func show() {
        NSApp.activate()
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window =
            NSWindow(contentViewController: NSHostingController(rootView: StatsView(state: StatsState(model: model))))
        window.title = Bundle.main.bundleIdentifier == Kettle.bundleID ? "Kettle Stats" : "Kettle Dev Stats"
        window.styleMask = [.titled, .closable, .miniaturizable]
        // Released by dropping our only reference in windowWillClose.
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.window?.contentViewController = nil
            self?.window = nil
        }
    }
}
