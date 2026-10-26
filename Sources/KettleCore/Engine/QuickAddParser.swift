import Foundation

/// The result of parsing a quick-add line such as `Write report 45m #work`.
public struct QuickAddEntry: Equatable, Sendable {
    public var title: String
    public var minutes: Int
    /// The label name without `#`, as typed. Nil if the line has no label.
    public var labelName: String?

    public init(title: String, minutes: Int, labelName: String?) {
        self.title = title
        self.minutes = minutes
        self.labelName = labelName
    }
}

public enum QuickAddError: Error, Equatable {
    case emptyTitle
    case durationOutOfRange
}

/// Parses quick-add shorthand:
///
/// - a duration as the last word (after removing the label): `45m`, `1h`, `1h30m`, `1h30`,
///   or a bare number of minutes. Without one the task gets `defaultMinutes`.
/// - a label anywhere: `#` followed by a letter, then letters, digits, `-` or `_`. If there
///   are several, the last one is the label and the others stay in the title.
/// - everything else, with whitespace collapsed, is the title.
public enum QuickAddParser {
    public static let defaultMinutes = 30

    public static func parse(_ input: String) throws -> QuickAddEntry {
        var words = input.split(whereSeparator: \.isWhitespace)

        var labelName: String?
        if let index = words.lastIndex(where: isLabel) {
            labelName = String(words[index].dropFirst())
            words.remove(at: index)
        }

        var minutes = defaultMinutes
        if let last = words.last, let parsed = duration(in: last) {
            guard PlanTask.plannedMinutesRange.contains(parsed) else {
                throw QuickAddError.durationOutOfRange
            }
            minutes = parsed
            words.removeLast()
        }

        guard !words.isEmpty else { throw QuickAddError.emptyTitle }
        return QuickAddEntry(title: words.joined(separator: " "), minutes: minutes, labelName: labelName)
    }

    static func isLabel(_ word: Substring) -> Bool {
        guard word.first == "#", let first = word.dropFirst().first, first.isLetter else { return false }
        return word.dropFirst().allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    /// Minutes, or nil if `word` isn't a duration. Values too large for `Int` saturate to `Int.max`.
    static func duration(in word: Substring) -> Int? {
        var hours: Int?
        var minutes: Int?
        var digits = ""
        var finished = false

        for character in word.lowercased() {
            guard !finished else { return nil }
            switch character {
            case "0" ... "9":
                digits.append(character)
            case "h" where hours == nil && !digits.isEmpty:
                hours = Int(digits) ?? Int.max
                digits = ""
            case "m" where !digits.isEmpty:
                minutes = Int(digits) ?? Int.max
                digits = ""
                finished = true
            default:
                return nil
            }
        }
        if !digits.isEmpty {
            minutes = Int(digits) ?? Int.max
        }
        guard hours != nil || minutes != nil else { return nil }

        let (hourMinutes, overflow) = (hours ?? 0).multipliedReportingOverflow(by: 60)
        let (total, sumOverflow) = hourMinutes.addingReportingOverflow(minutes ?? 0)
        return overflow || sumOverflow ? Int.max : total
    }
}
