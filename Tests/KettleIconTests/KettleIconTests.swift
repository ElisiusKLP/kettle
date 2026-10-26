import AppKit
import KettleCore
@testable import KettleIcon
import Testing

struct KettleIconTests {
    /// Pixels of a 2× rendering, with helpers to sum alpha over regions given in points.
    struct Pixels {
        let rep: NSBitmapImageRep

        init(_ state: IconState, style: KettleIcon.Style = .template, rotation: CGFloat = 0) throws {
            rep = try #require(KettleIcon.bitmap(
                of: KettleIcon.image(for: state, style: style, rotation: rotation),
                scale: 2
            ))
        }

        /// Sum of alpha (0...1) over the region, in points with y up.
        func alpha(x: ClosedRange<CGFloat> = 0 ... 18, y: ClosedRange<CGFloat> = 0 ... 18) -> CGFloat {
            var sum: CGFloat = 0
            forEachPixel(x: x, y: y) { color in sum += color.alphaComponent }
            return sum
        }

        func maxAlpha() -> CGFloat {
            var result: CGFloat = 0
            forEachPixel(x: 0 ... 18, y: 0 ... 18) { result = max(result, $0.alphaComponent) }
            return result
        }

        func forEachPixel(x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>, _ body: (NSColor) -> Void) {
            let height = rep.pixelsHigh
            for row in 0 ..< height {
                for column in 0 ..< rep.pixelsWide {
                    // Bitmap rows run top to bottom; drawing coordinates run bottom to top.
                    let point = CGPoint(x: (CGFloat(column) + 0.5) / 2, y: (CGFloat(height - 1 - row) + 0.5) / 2)
                    guard x.contains(point.x), y.contains(point.y), let color = rep.colorAt(x: column, y: row) else {
                        continue
                    }
                    body(color)
                }
            }
        }

        var data: Data {
            Data(bytes: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh)
        }
    }

    /// Only steam is drawn above the spout and to the right of the handle.
    static let steamX: ClosedRange<CGFloat> = 11.5 ... 18
    static let steamY: ClosedRange<CGFloat> = 9.4 ... 18

    @Test(arguments: IconState.allCases)
    func everyStateIs18PointsAndATemplate(state: IconState) throws {
        let image = KettleIcon.image(for: state)
        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(image.isTemplate)
        let pixels = try Pixels(state)
        #expect(pixels.rep.pixelsWide == 36)
        #expect(pixels.alpha() > 0)
    }

    @Test(arguments: IconState.allCases)
    func templateImagesAreBlackWithAlphaOnly(state: IconState) throws {
        try Pixels(state).forEachPixel(x: 0 ... 18, y: 0 ... 18) { color in
            guard color.alphaComponent > 0.01 else { return }
            #expect(color.redComponent < 0.01 && color.greenComponent < 0.01 && color.blueComponent < 0.01)
        }
    }

    @Test(arguments: IconState.allCases)
    func devImagesAreOrangeAndNotTemplates(state: IconState) throws {
        #expect(!KettleIcon.image(for: state, style: .dev).isTemplate)
        var orangePixels = 0
        try Pixels(state, style: .dev).forEachPixel(x: 0 ... 18, y: 0 ... 18) { color in
            guard color.alphaComponent > 0.5 else { return }
            let rgb = color.usingColorSpace(.sRGB) ?? color
            #expect(rgb.redComponent > rgb.blueComponent + 0.3)
            orangePixels += 1
        }
        #expect(orangePixels > 0)
    }

    @Test func steamHasAlphaForEveryStepAndGrowsWithIt() throws {
        var previous: CGFloat = -1
        for level in SteamLevel.allCases {
            let steam = try Pixels(.brewing(level)).alpha(x: Self.steamX, y: Self.steamY)
            if level == .none {
                #expect(steam == 0)
            } else {
                #expect(steam > 0, "step \(level.rawValue) has no steam")
            }
            #expect(steam > previous, "step \(level.rawValue) should show more steam than the step below")
            previous = steam
        }
    }

    @Test(arguments: [IconState.idle, .dayComplete, .paused(.none)])
    func statesWithoutSteamHaveNone(state: IconState) throws {
        #expect(try Pixels(state).alpha(x: Self.steamX, y: Self.steamY) == 0)
    }

    @Test func whistlingHasTheFullestSteam() throws {
        let whistle = try Pixels(.whistling).alpha(x: Self.steamX, y: Self.steamY)
        let full = try Pixels(.brewing(.five)).alpha(x: Self.steamX, y: Self.steamY)
        #expect(whistle >= full)
    }

    @Test(arguments: SteamLevel.allCases)
    func pausedIsHalfAlphaWithTheStepFrozen(level: SteamLevel) throws {
        let paused = try Pixels(.paused(level))
        #expect(paused.maxAlpha() <= 0.52)
        #expect(paused.maxAlpha() >= 0.45)
        let brewingSteam = level == .none ? 0 : try Pixels(.brewing(level)).alpha(x: Self.steamX, y: Self.steamY)
        let pausedSteam = paused.alpha(x: Self.steamX, y: Self.steamY)
        #expect(abs(pausedSteam - brewingSteam / 2) <= brewingSteam * 0.05 + 0.01)
    }

    @Test func everyStateLooksDifferent() throws {
        let renderings = try IconState.allCases.map { try Pixels($0).data }
        #expect(Set(renderings).count == IconState.allCases.count)
    }

    @Test func wiggleRotatesTheDrawing() throws {
        let still = try Pixels(.whistling)
        let tilted = try Pixels(.whistling, rotation: 0.12)
        #expect(still.data != tilted.data)
        #expect(abs(still.alpha() - tilted.alpha()) / still.alpha() < 0.1)
    }

    @Test func preRendersEveryState() {
        let images = KettleIcon.allImages(style: .template)
        #expect(images.count == IconState.allCases.count)
        let allTemplates = images.values.allSatisfy(\.isTemplate)
        #expect(allTemplates)
    }

    @Test func steamFadesFromTheOutermostWispInward() {
        let full = KettleDrawing.wisps(for: .five)
        #expect(full.count == 3)
        #expect(Set(full.map(\.height)).count == 3, "each wisp has a different height")
        let four = KettleDrawing.wisps(for: .four)
        #expect(four[2].height < full[2].height && four[2].opacity == 0.7)
        #expect(KettleDrawing.wisps(for: .three).map(\.x) == [full[0].x, full[1].x])
        let two = KettleDrawing.wisps(for: .two)
        #expect(two[1].opacity == 0.5)
        let one = KettleDrawing.wisps(for: .one)
        #expect(one.count == 1 && one[0].opacity == 0.4 && one[0].x == full[0].x)
        #expect(KettleDrawing.wisps(for: .none).isEmpty)
    }
}

extension IconState: CustomTestStringConvertible {
    public var testDescription: String {
        switch self {
        case .idle: "idle"
        case let .brewing(level): "brewing \(level.rawValue)"
        case let .paused(level): "paused \(level.rawValue)"
        case .whistling: "whistling"
        case .dayComplete: "day complete"
        }
    }
}
