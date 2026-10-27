import Foundation
@testable import KettleCore
import Testing

struct WhistleSoundTests {
    let samples = WhistleSound.samples()
    let rate = Double(WhistleSound.sampleRate)

    /// Root mean square over `from..<to` seconds, from 0 to 1.
    func loudness(_ from: Double, _ to: Double) -> Double {
        let slice = samples[Int(from * rate) ..< Int(to * rate)]
        let sum = slice.reduce(0.0) { $0 + Double($1) * Double($1) }
        return (sum / Double(slice.count)).squareRoot() / Double(Int16.max)
    }

    /// Sign changes per second over `from..<to` seconds: about twice the dominant pitch.
    func crossings(_ from: Double, _ to: Double) -> Double {
        let slice = Array(samples[Int(from * rate) ..< Int(to * rate)])
        let count = zip(slice, slice.dropFirst()).count { ($0 < 0) != ($1 < 0) }
        return Double(count) / (to - from)
    }

    @Test func isShortAndStaysBelowClipping() {
        #expect(samples.count == Int(WhistleSound.duration * rate))
        // Notification sounds must be under 30 seconds.
        #expect(WhistleSound.duration < 30)
        let peak = samples.map { abs(Int($0)) }.max() ?? 0
        #expect(Double(peak) / Double(Int16.max) <= WhistleSound.peak + 0.001)
    }

    @Test func startsLowAndQuietThenGrowsLouderAndHigher() {
        #expect(loudness(0.2, 0.5) * 3 < loudness(1.9, 2.4))
        #expect(loudness(0.8, 1.2) < loudness(1.9, 2.4))
        #expect(crossings(0.2, 0.5) < crossings(1.9, 2.4))
        // The late whistle sits near its top pitch (two crossings per cycle).
        #expect(abs(crossings(2.0, 2.4) / 2 - WhistleSound.highPitch) < 250)
    }

    @Test func startsAndEndsWithoutAClick() {
        #expect(abs(Int(samples[0])) < 100)
        #expect(loudness(WhistleSound.duration - 0.01, WhistleSound.duration) < 0.005)
    }

    @Test func isDeterministic() {
        #expect(WhistleSound.samples() == samples)
    }

    @Test func wavHeaderDescribesMono16BitPCM() {
        let wav = WAV.encode([1, -2, 3], sampleRate: 44100)
        #expect(wav.count == 44 + 6)
        #expect(String(bytes: wav[0 ..< 4], encoding: .ascii) == "RIFF")
        #expect(String(bytes: wav[8 ..< 16], encoding: .ascii) == "WAVEfmt ")
        #expect(String(bytes: wav[36 ..< 40], encoding: .ascii) == "data")
        func integer(_ offset: Int, _ size: Int) -> Int {
            (0 ..< size).reduce(0) { $0 | Int(wav[offset + $1]) << (8 * $1) }
        }
        #expect(integer(4, 4) == 36 + 6) // RIFF size
        #expect(integer(20, 2) == 1) // PCM
        #expect(integer(22, 2) == 1) // mono
        #expect(integer(24, 4) == 44100)
        #expect(integer(34, 2) == 16)
        #expect(integer(40, 4) == 6)
        #expect(Array(wav[44 ..< 50]) == [1, 0, 0xFE, 0xFF, 3, 0])
    }
}
