import AppKit
import KettleCore
import KettleIcon

/// The full-colour app icon (SPEC section 6.5): the menubar kettle's paths on a cream rounded
/// square, with a copper kettle and white steam. Renders every iconset size from the vector
/// paths and builds `Resources/AppIcon.icns` with `iconutil`.
enum AppIcon {
    static let cream = CGColor(srgbRed: 0.98, green: 0.95, blue: 0.89, alpha: 1)
    static let creamEdge = CGColor(srgbRed: 0.91, green: 0.85, blue: 0.75, alpha: 1)
    static let copper = CGColor(srgbRed: 0.78, green: 0.45, blue: 0.23, alpha: 1)
    static let copperDark = CGColor(srgbRed: 0.55, green: 0.29, blue: 0.13, alpha: 1)
    static let steamShadow = CGColor(srgbRed: 0.55, green: 0.29, blue: 0.13, alpha: 0.45)

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
        // A soft shadow keeps the white steam visible on cream.
        context.setShadow(offset: CGSize(width: 0, height: -0.12), blur: 0.35, color: steamShadow)
        KettleDrawing.draw(
            .brewing(.five),
            in: context,
            bodyColor: copperDark,
            steamColor: CGColor(gray: 1, alpha: 1),
            bodyFill: copper
        )
        context.restoreGState()
    }
}
