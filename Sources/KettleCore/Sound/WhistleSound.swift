import Foundation

/// The kettle whistle, synthesised so it can be regenerated from code like the app icon.
/// `kettle-tools whistle` writes it to `Resources/Whistle.wav`, which the notification and the
/// app play. Nothing here runs in the app.
///
/// It starts as a quiet, low, breathy hiss that rises in pitch and loudness into a shrill
/// two-tone whistle, then stops: a kettle coming to the boil, compressed into a few seconds.
public enum WhistleSound {
    public static let sampleRate = 44100
    public static let duration = 2.8
    /// Seconds over which pitch and loudness build up.
    static let rise = 2.3
    static let fadeOut = 0.3
    static let lowPitch = 1100.0
    static let highPitch = 2100.0
    static let peak = 0.7

    /// Mono 16-bit samples. Deterministic: the noise comes from a fixed-seed generator.
    public static func samples() -> [Int16] {
        let count = Int(duration * Double(sampleRate))
        var raw = [Double](repeating: 0, count: count)
        var noise = NoiseGenerator()
        var filter = ResonantFilter()
        var phase1 = 0.0
        var phase2 = 0.0
        let step = 1 / Double(sampleRate)

        for index in 0 ..< count {
            let time = Double(index) * step
            let progress = min(time / rise, 1)
            // Pitch rises quickly at first, then settles, with a slight flutter.
            let glide = 1 - (1 - progress) * (1 - progress)
            let flutter = 1 + 0.006 * sin(2 * .pi * 5.5 * time)
            let pitch = (lowPitch + (highPitch - lowPitch) * glide) * flutter
            // Two slightly detuned tones beat against each other, like a two-chamber whistle.
            phase1 += 2 * .pi * pitch * step
            phase2 += 2 * .pi * pitch * 1.0075 * step
            let tone = (sin(phase1) + 0.6 * sin(phase2) + 0.08 * sin(2 * phase1)) / 1.68
            // Steam: noise ringing around the whistle's pitch.
            let steam = filter.process(noise.next(), frequency: pitch, sampleRate: Double(sampleRate))
            // The hiss comes first; the whistle grows out of it.
            let toneLevel = pow(progress, 1.3)
            let steamLevel = 0.12 + 0.3 * (1 - progress)
            let loudness = 0.1 + 0.9 * pow(progress, 1.6)
            raw[index] = loudness * envelope(time) * (toneLevel * tone + steamLevel * steam)
        }

        let maximum = raw.reduce(0) { max($0, abs($1)) }
        let scale = maximum > 0 ? peak / maximum : 0
        return raw.map { Int16(($0 * scale * Double(Int16.max)).rounded()) }
    }

    /// The samples as a 16-bit mono PCM WAV file.
    public static func wav() -> Data {
        WAV.encode(samples(), sampleRate: sampleRate)
    }

    /// A short fade-in against clicks, and a fade-out at the end.
    private static func envelope(_ time: Double) -> Double {
        let fadeIn = min(time / 0.02, 1)
        let remaining = duration - time
        let tail = remaining < fadeOut ? 0.5 - 0.5 * cos(.pi * remaining / fadeOut) : 1
        return fadeIn * tail
    }
}

/// White noise from a 64-bit linear congruential generator, so the sound is reproducible.
private struct NoiseGenerator {
    private var state: UInt64 = 0x4B45_5454_4C45 // "KETTLE"

    /// A value in -1...1.
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 52) - 1
    }
}

/// A Chamberlin state-variable band-pass filter with a high Q, which makes noise "sing".
private struct ResonantFilter {
    private var low = 0.0
    private var band = 0.0
    private let damping = 1 / 12.0

    mutating func process(_ input: Double, frequency: Double, sampleRate: Double) -> Double {
        let coefficient = 2 * sin(.pi * frequency / sampleRate)
        low += coefficient * band
        let high = input - low - damping * band
        band += coefficient * high
        return band
    }
}

/// Minimal WAV (RIFF, PCM) encoding.
public enum WAV {
    public static func encode(_ samples: [Int16], sampleRate: Int) -> Data {
        let dataSize = samples.count * 2
        var data = Data()
        data.reserveCapacity(44 + dataSize)
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize), to: &data)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16), to: &data) // fmt chunk size
        append(UInt16(1), to: &data) // PCM
        append(UInt16(1), to: &data) // mono
        append(UInt32(sampleRate), to: &data)
        append(UInt32(sampleRate * 2), to: &data) // bytes per second
        append(UInt16(2), to: &data) // bytes per frame
        append(UInt16(16), to: &data) // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize), to: &data)
        for sample in samples {
            append(UInt16(bitPattern: sample), to: &data)
        }
        return data
    }

    private static func append(_ value: some FixedWidthInteger, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}
