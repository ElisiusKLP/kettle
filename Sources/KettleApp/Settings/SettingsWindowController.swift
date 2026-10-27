import AppKit
import KettleCore
import SwiftUI

/// Creates the Settings window on demand and lets go of it when it closes, so its SwiftUI views
/// don't stay in memory (SPEC section 8, rule 2).
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: KettleModel
    private let dataFolder: URL
    private let onChange: () -> Void
    private var window: NSWindow?

    init(model: KettleModel, dataFolder: URL, onChange: @escaping () -> Void) {
        self.model = model
        self.dataFolder = dataFolder
        self.onChange = onChange
    }

    func show() {
        NSApp.activate()
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let state = SettingsState(model: model, dataFolder: dataFolder, onChange: onChange)
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(state: state)))
        window.title = Bundle.main.bundleIdentifier == Kettle.bundleID ? "Kettle Settings" : "Kettle Dev Settings"
        window.styleMask = [.titled, .closable]
        // Released by dropping our only reference in windowWillClose.
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_: Notification) {
        // Let AppKit finish closing before the window and its views go away.
        DispatchQueue.main.async { [weak self] in
            self?.window?.contentViewController = nil
            self?.window = nil
        }
    }
}
