import AppKit
import KettleCore
import SwiftUI

/// Creates the popover and its SwiftUI content when it opens, and releases both when it closes
/// (SPEC section 8, rule 2), so nothing SwiftUI lives while Kettle sits in the menubar.
final class PopoverController: NSObject, NSPopoverDelegate {
    private let model: KettleModel
    private let onChange: () -> Void
    private let onOpenSettings: () -> Void
    private let onOpenStats: () -> Void
    private var popover: NSPopover?
    private var state: PopoverState?

    init(
        model: KettleModel,
        onChange: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenStats: @escaping () -> Void
    ) {
        self.model = model
        self.onChange = onChange
        self.onOpenSettings = onOpenSettings
        self.onOpenStats = onOpenStats
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
        self.state = state
        let host = FirstClickHostingView(
            rootView: PopoverView(state: state, openSettings: onOpenSettings, openStats: onOpenStats)
        )
        // Size the popover up front: if it only learns its size from SwiftUI after opening, AppKit
        // positions it for a tiny size and it then grows off the edge of the screen.
        host.sizingOptions = []
        let content = NSViewController()
        content.view = host
        popover.contentViewController = content
        popover.contentSize = PopoverView.size
        self.popover = popover
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func close() {
        popover?.performClose(nil)
    }

    /// Shows the model's current state, e.g. after the timer finished a task while open.
    func reload() {
        state?.reload()
    }

    func popoverDidClose(_: Notification) {
        popover?.contentViewController = nil
        popover = nil
        state = nil
    }
}

/// Clicks and drags work on the first try, even when the popover isn't the key window yet.
/// Otherwise AppKit spends the first click making it key, and a drag that starts with it is lost.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }
}
