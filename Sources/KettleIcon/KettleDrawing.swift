import CoreGraphics
import KettleCore

/// The kettle and its steam as CoreGraphics paths in an 18 × 18 unit space (y up, origin at
/// the bottom left). The menubar icon draws it at 1 unit = 1 pt; the app icon scales it up.
public enum KettleDrawing {
    public static let canvasSize: CGFloat = 18

    static let outlineWidth: CGFloat = 1.5
    static let steamWidth: CGFloat = 1.2
    static let detailWidth: CGFloat = 1.2

    /// Rotation pivot for the whistle wiggle: the middle of the kettle's base.
    static let pivot = CGPoint(x: 6.8, y: 1.75)

    /// Draws `state`. `rotation` is in radians and only used for the whistle wiggle.
    public static func draw(
        _ state: IconState,
        in context: CGContext,
        bodyColor: CGColor,
        steamColor: CGColor,
        rotation: CGFloat = 0
    ) {
        context.saveGState()
        defer { context.restoreGState() }

        if rotation != 0 {
            context.translateBy(x: pivot.x, y: pivot.y)
            context.rotate(by: rotation)
            context.translateBy(x: -pivot.x, y: -pivot.y)
        }

        let paused: Bool
        if case .paused = state {
            paused = true
            // Draw everything as one layer at 50%, so overlapping strokes don't darken.
            context.setAlpha(0.5)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        } else {
            paused = false
        }

        context.setLineCap(.round)
        context.setLineJoin(.round)
        drawKettle(in: context, color: bodyColor)

        switch state {
        case .idle:
            break
        case let .brewing(level), let .paused(level):
            drawSteam(wisps(for: level), in: context, color: steamColor)
        case .whistling:
            drawSteam(burst, in: context, color: steamColor)
            drawWhistleLines(in: context, color: bodyColor)
        case .dayComplete:
            drawCheck(in: context, color: bodyColor)
        }

        if paused {
            context.endTransparencyLayer()
        }
    }

    // MARK: Kettle

    public static func bodyPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 3.2, y: 1.75))
        path.addLine(to: CGPoint(x: 10.3, y: 1.75))
        path.addCurve(
            to: CGPoint(x: 11.6, y: 3.3),
            control1: CGPoint(x: 11.2, y: 1.75),
            control2: CGPoint(x: 11.75, y: 2.3)
        )
        path.addCurve(
            to: CGPoint(x: 9.5, y: 8.4),
            control1: CGPoint(x: 11.35, y: 5.6),
            control2: CGPoint(x: 10.7, y: 7.4)
        )
        path.addLine(to: CGPoint(x: 4.1, y: 8.4))
        path.addCurve(
            to: CGPoint(x: 2.0, y: 3.3),
            control1: CGPoint(x: 2.9, y: 7.4),
            control2: CGPoint(x: 2.25, y: 5.6)
        )
        path.addCurve(
            to: CGPoint(x: 3.2, y: 1.75),
            control1: CGPoint(x: 1.85, y: 2.3),
            control2: CGPoint(x: 2.4, y: 1.75)
        )
        path.closeSubpath()
        return path
    }

    static func handlePath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 3.7, y: 8.4))
        path.addCurve(
            to: CGPoint(x: 9.9, y: 8.4),
            control1: CGPoint(x: 3.3, y: 12.8),
            control2: CGPoint(x: 10.3, y: 12.8)
        )
        return path
    }

    static func spoutPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 11.4, y: 4.6))
        path.addQuadCurve(to: CGPoint(x: 15.0, y: 8.0), control: CGPoint(x: 13.4, y: 5.0))
        return path
    }

    static let knob = CGRect(x: 6.0, y: 8.55, width: 1.6, height: 1.6)

    static func drawKettle(in context: CGContext, color: CGColor) {
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(outlineWidth)
        for path in [bodyPath(), handlePath(), spoutPath()] {
            context.addPath(path)
            context.strokePath()
        }
        context.fillEllipse(in: knob)
    }

    // MARK: Steam

    struct Wisp: Equatable {
        /// Centre line x and the y where it starts.
        var x: CGFloat
        var baseY: CGFloat
        var height: CGFloat
        var opacity: CGFloat = 1
    }

    /// The three wisps at full steam, inner (left) to outer (right), each a different height.
    static let fullSteam = [
        Wisp(x: 12.6, baseY: 10.0, height: 6.0),
        Wisp(x: 14.5, baseY: 9.6, height: 7.4),
        Wisp(x: 16.4, baseY: 10.2, height: 5.6),
    ]

    /// The whistle's full burst: every wisp a little taller.
    static let burst = fullSteam.map { Wisp(
        x: $0.x,
        baseY: $0.baseY - 0.2,
        height: min($0.height * 1.12, 17.4 - $0.baseY)
    ) }

    /// SPEC section 6.2: the steam shrinks and fades from the outermost wisp inward.
    static func wisps(for level: SteamLevel) -> [Wisp] {
        let inner = fullSteam[0], middle = fullSteam[1], outer = fullSteam[2]
        func shortened(_ wisp: Wisp, _ factor: CGFloat, opacity: CGFloat = 1) -> Wisp {
            Wisp(x: wisp.x, baseY: wisp.baseY, height: wisp.height * factor, opacity: opacity)
        }
        switch level {
        case .five: return fullSteam
        case .four: return [inner, middle, shortened(outer, 0.65, opacity: 0.7)]
        case .three: return [inner, middle]
        case .two: return [shortened(inner, 0.6), shortened(middle, 0.55, opacity: 0.5)]
        case .one: return [shortened(inner, 0.45, opacity: 0.4)]
        case .none: return []
        }
    }

    /// A soft S-curve rising from the base.
    static func wispPath(_ wisp: Wisp) -> CGPath {
        let path = CGMutablePath()
        let sway: CGFloat = 2.0
        path.move(to: CGPoint(x: wisp.x, y: wisp.baseY))
        path.addCurve(
            to: CGPoint(x: wisp.x, y: wisp.baseY + wisp.height),
            control1: CGPoint(x: wisp.x + sway, y: wisp.baseY + wisp.height / 3),
            control2: CGPoint(x: wisp.x - sway, y: wisp.baseY + wisp.height * 2 / 3)
        )
        return path
    }

    /// The full-steam wisps as one filled outline, so the app icon can paint them with a gradient.
    public static func fullSteamOutline() -> CGPath {
        let path = CGMutablePath()
        for wisp in fullSteam {
            path.addPath(wispPath(wisp).copy(
                strokingWithWidth: steamWidth,
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 10
            ))
        }
        return path
    }

    static func drawSteam(_ wisps: [Wisp], in context: CGContext, color: CGColor) {
        context.setLineWidth(steamWidth)
        for wisp in wisps {
            context.setStrokeColor(color.copy(alpha: color.alpha * wisp.opacity) ?? color)
            context.addPath(wispPath(wisp))
            context.strokePath()
        }
    }

    // MARK: Details

    static func drawWhistleLines(in context: CGContext, color: CGColor) {
        context.setStrokeColor(color)
        context.setLineWidth(detailWidth)
        context.strokeLineSegments(between: [
            CGPoint(x: 16.3, y: 6.9), CGPoint(x: 17.5, y: 7.5),
            CGPoint(x: 16.1, y: 5.6), CGPoint(x: 17.4, y: 5.3),
        ])
    }

    static func drawCheck(in context: CGContext, color: CGColor) {
        context.setStrokeColor(color)
        context.setLineWidth(detailWidth + 0.1)
        context.addLines(between: [CGPoint(x: 4.7, y: 5.0), CGPoint(x: 6.2, y: 3.6), CGPoint(x: 8.9, y: 6.3)])
        context.strokePath()
    }
}
