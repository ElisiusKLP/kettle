import Foundation

/// Formats the menubar countdown without heap allocations: every result fits in Swift's
/// inline small-string storage (15 UTF-8 bytes).
///
/// - seconds: `23:41`, `1:02:03`, and in overtime `+00:42`, `+1:00:05`
/// - minutes: `24m`, `1h 05m`, and in overtime `+3m`, `+1h 05m`
///
/// The countdown rounds up and overtime counts up from `+00:00`, so the display reaches
/// zero exactly when the kettle whistles.
public enum CountdownFormatter {
    /// Longest shown time: 99:59:59.
    static let maximumSeconds = 99 * 3600 + 59 * 60 + 59

    public static func string(remaining: TimeInterval, precision: TimerPrecision) -> String {
        let overtime = remaining <= 0
        let magnitude = overtime ? -remaining : remaining
        switch precision {
        case .seconds:
            let seconds = whole(magnitude, roundingUp: !overtime, limit: maximumSeconds)
            return format(sign: overtime, hours: seconds / 3600, minutes: seconds / 60 % 60, seconds: seconds % 60)
        case .minutes:
            let minutes = whole(magnitude / 60, roundingUp: !overtime, limit: maximumSeconds / 60)
            return format(sign: overtime, hours: minutes / 60, minutes: minutes % 60, seconds: nil)
        }
    }

    private static func whole(_ value: Double, roundingUp: Bool, limit: Int) -> Int {
        guard value.isFinite else { return limit }
        return Int(min(max(value.rounded(roundingUp ? .up : .down), 0), Double(limit)))
    }

    /// Writes ASCII into a small string. `seconds == nil` selects the minutes style. Uses static
    /// helpers with `inout` rather than nested functions, which would box `count` on the heap
    /// in unoptimised builds.
    private static func format(sign: Bool, hours: Int, minutes: Int, seconds: Int?) -> String {
        String(unsafeUninitializedCapacity: 15) { buffer in
            var count = 0
            if sign {
                put("+", into: buffer, at: &count)
            }
            if let seconds {
                if hours > 0 {
                    putDigits(hours, pad: false, into: buffer, at: &count)
                    put(":", into: buffer, at: &count)
                }
                putDigits(minutes, pad: true, into: buffer, at: &count)
                put(":", into: buffer, at: &count)
                putDigits(seconds, pad: true, into: buffer, at: &count)
            } else if hours > 0 {
                putDigits(hours, pad: false, into: buffer, at: &count)
                put("h", into: buffer, at: &count)
                put(" ", into: buffer, at: &count)
                putDigits(minutes, pad: true, into: buffer, at: &count)
                put("m", into: buffer, at: &count)
            } else {
                putDigits(minutes, pad: false, into: buffer, at: &count)
                put("m", into: buffer, at: &count)
            }
            return count
        }
    }

    private static func put(
        _ ascii: Unicode.Scalar,
        into buffer: UnsafeMutableBufferPointer<UInt8>,
        at count: inout Int
    ) {
        buffer[count] = UInt8(ascii: ascii)
        count += 1
    }

    /// Writes 0–99, with a leading zero if `pad`.
    private static func putDigits(
        _ value: Int,
        pad: Bool,
        into buffer: UnsafeMutableBufferPointer<UInt8>,
        at count: inout Int
    ) {
        if value >= 10 || pad {
            buffer[count] = UInt8(ascii: "0") + UInt8(value / 10)
            count += 1
        }
        buffer[count] = UInt8(ascii: "0") + UInt8(value % 10)
        count += 1
    }
}
