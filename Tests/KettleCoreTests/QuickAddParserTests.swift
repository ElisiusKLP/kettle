@testable import KettleCore
import Testing

struct QuickAddParserTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let input: String
        let title: String
        let minutes: Int
        let label: String?

        init(_ input: String, _ title: String, _ minutes: Int, _ label: String? = nil) {
            self.input = input
            self.title = title
            self.minutes = minutes
            self.label = label
        }

        var testDescription: String {
            input
        }
    }

    @Test(arguments: [
        // The spec's examples.
        Case("Write report 45m #work", "Write report", 45, "work"),
        Case("Gym 1h #health", "Gym", 60, "health"),
        Case("Emails 20", "Emails", 20),
        Case("Deep work 1h30m #work", "Deep work", 90, "work"),
        // Duration forms.
        Case("Read 1h30", "Read", 90),
        Case("Read 2h", "Read", 120),
        Case("Read 12h", "Read", 720),
        Case("Read 1M", "Read", 1),
        Case("Read 1H15M", "Read", 75),
        Case("Read 0h45m", "Read", 45),
        // Label position and form.
        Case("#work Write report 45m", "Write report", 45, "work"),
        Case("Write #work report 45m", "Write report", 45, "work"),
        Case("Write report #work 45m", "Write report", 45, "work"),
        Case("Plan #deep-work_2 25m", "Plan", 25, "deep-work_2"),
        Case("Café #santé 10m", "Café", 10, "santé"),
        Case("Review PR #42 #work 30m", "Review PR #42", 30, "work"),
        Case("Tidy #home #chores", "Tidy #home", 30, "chores"),
        Case("Price #1 deal", "Price #1 deal", 30),
        Case("Odd # tag", "Odd # tag", 30),
        // No duration: the default applies, and numbers inside the title stay there.
        Case("Emails", "Emails", 30),
        Case("Read 2 chapters", "Read 2 chapters", 30),
        Case("45m Write report", "45m Write report", 30),
        Case("Call 1h2h", "Call 1h2h", 30),
        Case("Call 30m15", "Call 30m15", 30),
        Case("Call h", "Call h", 30),
        Case("Call 1hm", "Call 1hm", 30),
        Case("Call m5", "Call m5", 30),
        Case("Call 5x", "Call 5x", 30),
        // Whitespace is collapsed.
        Case("  Write   report \t 45m  ", "Write report", 45),
    ])
    func parses(_ testCase: Case) throws {
        let entry = try QuickAddParser.parse(testCase.input)
        #expect(entry == QuickAddEntry(title: testCase.title, minutes: testCase.minutes, labelName: testCase.label))
    }

    @Test(arguments: ["", "   ", "45m", "#work", "45m #work", "#work 1h"])
    func rejectsInputWithoutATitle(_ input: String) {
        #expect(throws: QuickAddError.emptyTitle) { try QuickAddParser.parse(input) }
    }

    @Test(arguments: [
        "Tea 0",
        "Tea 0m",
        "Tea 0h0m",
        "Tea 721",
        "Tea 12h1m",
        "Tea 13h",
        "Tea 99999999999999999999999",
        "Tea 9999999999999999999h"
    ])
    func rejectsDurationsOutOfRange(_ input: String) {
        #expect(throws: QuickAddError.durationOutOfRange) { try QuickAddParser.parse(input) }
    }

    @Test func defaultDurationIsWithinTheAllowedRange() {
        #expect(PlanTask.plannedMinutesRange.contains(QuickAddParser.defaultMinutes))
    }

    @Test func aDurationOnItsOwn() {
        #expect(QuickAddParser.minutes("45") == 45)
        #expect(QuickAddParser.minutes(" 45m ") == 45)
        #expect(QuickAddParser.minutes("1h30") == 90)
        #expect(QuickAddParser.minutes("1 h 5 m") == 65)
        #expect(QuickAddParser.minutes("0") == nil)
        #expect(QuickAddParser.minutes("13h") == nil)
        #expect(QuickAddParser.minutes("soon") == nil)
    }
}
