import AppKit
import SwiftUI

/// Shows the up-down resize cursor over its area, using AppKit cursor rects, which AppKit
/// keeps in place through redraws and scrolling. (Setting the cursor from SwiftUI hover events
/// only lasts until the next redraw.) It ignores clicks, so gestures underneath still get them.
struct ResizeCursorArea: NSViewRepresentable {
    func makeNSView(context _: Context) -> CursorRectView {
        CursorRectView()
    }

    func updateNSView(_ view: CursorRectView, context _: Context) {
        view.window?.invalidateCursorRects(for: view)
    }

    final class CursorRectView: NSView {
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeUpDown)
        }

        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }
    }
}
