import AppKit
import KettleCore
import SwiftUI

/// Creates the popover and its SwiftUI content when it opens, and releases both when it closes
/// (SPEC section 8, rule 2), so nothing SwiftUI lives while Kettle sits in the menubar.
final class PopoverController: NSObject, NSPopoverDelegate {
    private let model: KettleModel
    private let onChange: () -> Void
    private let onOpenSettings: () -> Void
    private var popover: NSPopover?

    init(model: KettleModel, onChange: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.model = model
        self.onChange = onChange
        self.onOpenSettings = onOpenSettings
    }

    var isShown: Bool {
        popover?.isShown == true
    }

    func toggle(relativeTo button: NSView) {
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        let state = PopoverState(model: model, onChange: onChange)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(state: state, openSettings: onOpenSettings)
        )
        self.popover = popover
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func close() {
        popover?.performClose(nil)
    }

    func popoverDidClose(_: Notification) {
        popover?.contentViewController = nil
        popover = nil
    }
}
