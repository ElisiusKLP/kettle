import AppKit
import KettleCore

/// The menubar kettle as `NSImage`s, drawn in code (no bitmap assets).
public enum KettleIcon {
    public enum Style: Sendable {
        /// Black with alpha only, so macOS tints it for light and dark menubars.
        case template
        /// Non-template orange, so Kettle Dev is easy to tell apart.
        case dev
    }

    public static let size = NSSize(width: KettleDrawing.canvasSize, height: KettleDrawing.canvasSize)
    public static let devColor = CGColor(srgbRed: 0.95, green: 0.52, blue: 0.13, alpha: 1)

    /// An 18 × 18 pt image of `state`. `rotation` (radians) is for the whistle wiggle frames.
    public static func image(for state: IconState, style: Style = .template, rotation: CGFloat = 0) -> NSImage {
        let color = style == .template ? CGColor(gray: 0, alpha: 1) : devColor
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: rect.width / KettleDrawing.canvasSize, y: rect.height / KettleDrawing.canvasSize)
            KettleDrawing.draw(state, in: context, bodyColor: color, steamColor: color, rotation: rotation)
            return true
        }
        image.isTemplate = style == .template
        return image
    }

    /// Every state, for pre-rendering once at launch (SPEC section 6.4).
    public static func allImages(style: Style) -> [IconState: NSImage] {
        Dictionary(uniqueKeysWithValues: IconState.allCases.map { ($0, image(for: $0, style: style)) })
    }

    /// Rasterizes `image` at `scale` pixels per point (for previews and tests).
    public static func bitmap(of image: NSImage, scale: CGFloat) -> NSBitmapImageRep? {
        let pixels = Int((image.size.width * scale).rounded())
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.current?.flushGraphics()
        return rep
    }
}
