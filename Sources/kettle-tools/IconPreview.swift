import AppKit
import KettleCore
import KettleIcon

/// Renders every icon state on light and dark menubar backgrounds, at 1× and 2×, plus
/// enlarged pixel views, into one PNG for visual review.
enum IconPreview {
    static let light = NSColor(srgbRed: 0.95, green: 0.95, blue: 0.95, alpha: 1)
    static let dark = NSColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1)

    /// How one column shows an icon.
    struct Column {
        let title: String
        let width: CGFloat
        let background: NSColor
        /// Simulates macOS tinting the template image; nil draws the dev style as is.
        let tint: NSColor?
        /// Pixels per point.
        let scale: CGFloat
        /// Nearest-neighbour enlargement, so single pixels can be inspected.
        var zoom: CGFloat = 1
    }

    static let columns = [
        Column(title: "Light 1×", width: 64, background: light, tint: .black, scale: 1),
        Column(title: "Light 2×", width: 64, background: light, tint: .black, scale: 2),
        Column(title: "Dark 1×", width: 64, background: dark, tint: .white, scale: 1),
        Column(title: "Dark 2×", width: 64, background: dark, tint: .white, scale: 2),
        Column(title: "Dev 2×", width: 64, background: light, tint: nil, scale: 2),
        Column(title: "Light 2× zoomed", width: 168, background: light, tint: .black, scale: 2, zoom: 4),
        Column(title: "Dark 2× zoomed", width: 168, background: dark, tint: .white, scale: 2, zoom: 4),
    ]

    static let labelWidth: CGFloat = 150
    static let headerHeight: CGFloat = 70
    static let rowHeight: CGFloat = 164

    static func render(to url: URL) throws {
        let states = IconState.allCases
        let width = labelWidth + columns.reduce(0) { $0 + $1.width } + 16
        let height = headerHeight + rowHeight * CGFloat(states.count) + 16

        guard let sheet = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { throw ToolError("could not create the preview bitmap") }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
        NSGraphicsContext.current?.imageInterpolation = .none
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        text("Kettle menubar icon — every state", at: NSPoint(x: 16, y: height - 30), size: 16, bold: true)
        var x = labelWidth
        for column in columns {
            text(column.title, at: NSPoint(x: x + 4, y: height - headerHeight + 8), size: 11)
            x += column.width
        }
        for (row, state) in states.enumerated() {
            drawRow(state, top: height - headerHeight - rowHeight * CGFloat(row))
        }
        NSGraphicsContext.current?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let png = sheet.representation(using: .png, properties: [:]) else {
            throw ToolError("could not encode the preview PNG")
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
    }

    static func drawRow(_ state: IconState, top: CGFloat) {
        text(name(of: state), at: NSPoint(x: 16, y: top - rowHeight / 2 - 6), size: 12)
        var x = labelWidth
        for column in columns {
            drawCell(state, column, in: NSRect(
                x: x,
                y: top - rowHeight + 4,
                width: column.width - 4,
                height: rowHeight - 8
            ))
            x += column.width
        }
    }

    /// One icon centred on a menubar-coloured cell.
    static func drawCell(_ state: IconState, _ column: Column, in rect: NSRect) {
        column.background.setFill()
        rect.fill()
        let icon = KettleIcon.image(for: state, style: column.tint == nil ? .dev : .template)
        let shown = column.tint.map { tinted(icon, $0) } ?? icon
        guard let bitmap = KettleIcon.bitmap(of: shown, scale: column.scale) else { return }
        let side = KettleIcon.size.width * column.scale * column.zoom
        let target = NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        bitmap.draw(
            in: target,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSNumber(value: NSImageInterpolation.none.rawValue)]
        )
    }

    static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    static func text(_ string: String, at point: NSPoint, size: CGFloat, bold: Bool = false) {
        let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: NSColor.black]).draw(at: point)
    }

    static func name(of state: IconState) -> String {
        switch state {
        case .idle: "Idle"
        case let .brewing(level): "Brewing, step \(level.rawValue)"
        case let .paused(level): "Paused, step \(level.rawValue)"
        case .whistling: "Whistling"
        case .dayComplete: "Day complete"
        }
    }
}

struct ToolError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
