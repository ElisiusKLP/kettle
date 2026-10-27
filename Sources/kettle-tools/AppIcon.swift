import AppKit
import KettleCore
import KettleIcon

/// The full-colour app icon (SPEC section 6.5): the menubar kettle's paths on a cream rounded
/// square, with a brushed-steel kettle and black steam. Renders every iconset size from the vector
/// paths and builds `Resources/AppIcon.icns` with `iconutil`.
enum AppIcon {
    static let cream = CGColor(srgbRed: 0.98, green: 0.95, blue: 0.89, alpha: 1)
    static let creamEdge = CGColor(srgbRed: 0.91, green: 0.85, blue: 0.75, alpha: 1)
    static let steelOutline = CGColor(srgbRed: 0.29, green: 0.31, blue: 0.34, alpha: 1)
    /// Left to right across the pot: darker edges and a bright band, like a polished cylinder.
    static let steelGradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [
            CGColor(srgbRed: 0.55, green: 0.58, blue: 0.62, alpha: 1),
            CGColor(srgbRed: 0.93, green: 0.94, blue: 0.95, alpha: 1),
            CGColor(srgbRed: 0.74, green: 0.77, blue: 0.80, alpha: 1),
            CGColor(srgbRed: 0.47, green: 0.50, blue: 0.54, alpha: 1),
        ] as CFArray,
        locations: [0, 0.32, 0.62, 1]
    )!
    static let steam = CGColor(srgbRed: 0.66, green: 0.68, blue: 0.71, alpha: 1)

    static func build(output: URL, previewPNG: URL?) throws {
        let iconset = FileManager.default.temporaryDirectory
            .appendingPathComponent("kettle-\(UUID().uuidString).iconset", isDirectory: true)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: iconset) }

        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let suffix = scale == 2 ? "@2x" : ""
                try png(pixels: points * scale)
                    .write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
            }
        }
        if let previewPNG {
            try FileManager.default.createDirectory(
                at: previewPNG.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try png(pixels: 1024).write(to: previewPNG)
        }

        let iconutil = Process()
        iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
        try iconutil.run()
        iconutil.waitUntilExit()
        guard iconutil.terminationStatus == 0 else { throw ToolError("iconutil failed") }
    }

    static func png(pixels: Int) throws -> Data {
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ToolError("could not create a \(pixels) px context") }
        draw(in: context, size: CGFloat(pixels))
        guard let image = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw ToolError("could not encode a \(pixels) px PNG") }
        return data
    }

    /// Follows the macOS icon grid: an 824/1024 rounded square with a 185/1024 corner radius.
    static func draw(in context: CGContext, size: CGFloat) {
        let unit = size / 1024
        let tile = CGRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
        let tilePath = CGPath(roundedRect: tile, cornerWidth: 185 * unit, cornerHeight: 185 * unit, transform: nil)
        context.setShadow(
            offset: CGSize(width: 0, height: -10 * unit),
            blur: 24 * unit,
            color: CGColor(gray: 0, alpha: 0.25)
        )
        context.addPath(tilePath)
        context.setFillColor(cream)
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.addPath(tilePath)
        context.setStrokeColor(creamEdge)
        context.setLineWidth(4 * unit)
        context.strokePath()

        // The 18-unit kettle drawing, centred on the tile at 34 px per unit.
        let scale = 34 * unit
        context.saveGState()
        context.translateBy(x: tile.midX - 9.6 * scale, y: tile.midY - 9.2 * scale)
        context.scaleBy(x: scale, y: scale)
        // Fill the pot with the steel gradient, then draw the outline and steam on top.
        let body = KettleDrawing.bodyPath()
        context.saveGState()
        context.addPath(body)
        context.clip()
        let bounds = body.boundingBox
        context.drawLinearGradient(
            steelGradient,
            start: CGPoint(x: bounds.minX, y: bounds.midY),
            end: CGPoint(x: bounds.maxX, y: bounds.midY),
            options: []
        )
        context.restoreGState()
        KettleDrawing.draw(.brewing(.five), in: context, bodyColor: steelOutline, steamColor: steam)
        context.restoreGState()
    }
}
