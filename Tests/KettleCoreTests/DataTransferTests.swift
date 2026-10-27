import Foundation
@testable import KettleCore
import Testing

struct DataTransferTests {
    let folder: TemporaryDirectory
    let calendar = Calendar.gregorian("Europe/Copenhagen")
    let clock = FakeClock(.iso("2026-10-26T08:00:00Z"))

    init() throws {
        folder = try TemporaryDirectory()
    }

    func makeStore(_ directory: URL? = nil) -> JSONStore {
        JSONStore(directory: directory ?? folder.url, scheduler: ManualScheduler(), calendar: calendar)
    }

    @Test func exportAndImportRoundTripWithoutDataLoss() throws {
        try Fixtures.copy(to: folder)
        let source = makeStore()
        try source.appendSession(Session(
            taskID: UUID(),
            labelID: nil,
            start: .iso("2026-09-30T20:00:00Z"),
            end: .iso("2026-09-30T21:00:00Z"),
            extensionsMinutes: 5
        ))
        try DailyTotalsCache(store: source, calendar: calendar).rebuild()
        try source.flush()
        let exported = try DataTransfer.export(from: source, exportedAt: clock.now)
        let json = try DataTransfer.encode(exported)

        let emptyFolder = try TemporaryDirectory()
        let target = makeStore(emptyFolder.url)
        let summary = try DataTransfer.merge(DataTransfer.decode(json), into: target, calendar: calendar)
        try target.flush()

        #expect(summary == .init(labels: 2, plans: 1, newSessions: 3))
        let reExported = try DataTransfer.export(from: makeStore(emptyFolder.url), exportedAt: clock.now)
        #expect(reExported == exported)
        #expect(try makeStore(emptyFolder.url).loadDailyTotals() == source.loadDailyTotals())
        // Every file comes back byte for byte.
        for file in Fixtures.files where file != "sessions/2026-10.json" {
            #expect(try emptyFolder.read(file) == folder.read(file), "\(file)")
        }
    }

    @Test func importMergesWithoutDeleting() throws {
        let store = makeStore()
        let kept = Label(name: "kept", colorHex: "#000000")
        let renamed = Label(name: "old name", colorHex: "#111111")
        store.saveLabels([kept, renamed])
        let existing = Session(
            taskID: UUID(),
            labelID: nil,
            start: .iso("2026-10-01T08:00:00Z"),
            end: .iso("2026-10-01T09:00:00Z")
        )
        try store.appendSession(existing)
        store.savePlan(DayPlan(date: .ymd("2026-10-02"), tasks: [PlanTask(title: "Stays", plannedMinutes: 5)]))
        try store.flush()

        var import1 = try DataTransfer.export(from: makeStore(), exportedAt: clock.now)
        import1.labels = [Label(id: renamed.id, name: "new name", colorHex: "#111111")]
        let added = Session(
            taskID: UUID(),
            labelID: nil,
            start: .iso("2026-10-03T08:00:00Z"),
            end: .iso("2026-10-03T08:30:00Z")
        )
        import1.sessions = [existing, added]
        import1.plans = [DayPlan(date: .ymd("2026-10-03"), tasks: [PlanTask(title: "New", plannedMinutes: 5)])]

        let summary = try DataTransfer.merge(import1, into: store, calendar: calendar)
        try store.flush()

        #expect(summary == .init(labels: 1, plans: 1, newSessions: 1))
        let reopened = makeStore()
        #expect(try reopened.loadLabels().map(\.name) == ["kept", "new name"])
        #expect(try reopened.loadSessions(monthOf: .ymd("2026-10-01")) == [existing, added])
        #expect(try reopened.planDates() == [.ymd("2026-10-02"), .ymd("2026-10-03")])
        #expect(try reopened.loadDailyTotals()[.ymd("2026-10-03"), nil].seconds == 1800)
    }

    @Test func newerExportFormatIsRefused() throws {
        var export = try DataTransfer.export(from: makeStore(), exportedAt: clock.now)
        export.formatVersion = 99
        let data = try DataTransfer.encode(export)
        #expect(throws: DataTransferError.newerFormat(found: 99, supported: 1)) { try DataTransfer.decode(data) }
    }

    @Test func csvHasOneEscapedRowPerSessionInLocalTime() {
        let label = Label(name: "work, mostly", colorHex: "#000000")
        let task = PlanTask(title: "Say \"hi\"", labelID: label.id, plannedMinutes: 30)
        let export = KettleExport(
            formatVersion: 1, exportedAt: clock.now, settings: AppSettings(), labels: [label],
            plans: [DayPlan(date: .ymd("2026-10-26"), tasks: [task])],
            sessions: [
                Session(
                    taskID: task.id,
                    labelID: label.id,
                    start: .iso("2026-10-26T08:00:00Z"),
                    end: .iso("2026-10-26T08:45:30Z"),
                    extensionsMinutes: 10
                ),
                Session(
                    taskID: UUID(),
                    labelID: nil,
                    start: .iso("2026-10-26T22:30:00Z"),
                    end: .iso("2026-10-26T23:00:00Z")
                ),
            ]
        )
        let lines = DataTransfer.csv(export, calendar: calendar).split(separator: "\n").map(String.init)
        #expect(lines == [
            "date,start,end,minutes,label,task,extension_minutes",
            #"2026-10-26,09:00:00,09:45:30,45.5,"work, mostly","Say ""hi""",10"#,
            "2026-10-26,23:30:00,00:00:00,30.0,,,0",
        ])
    }

    @Test(arguments: [("plain", "plain"), ("a,b", "\"a,b\""), ("say \"x\"", "\"say \"\"x\"\"\""), ("a\nb", "\"a\nb\"")])
    func escapesCSVFields(field: String, expected: String) {
        #expect(DataTransfer.escape(field) == expected)
    }

    // MARK: Through the model

    @Test func modelExportImportAndDeleteAll() throws {
        let store = makeStore()
        let model = try KettleModel(store: store, clock: clock, calendar: calendar)
        model.add(QuickAddEntry(title: "Write", minutes: 30, labelName: "work"))
        model.start()
        clock.advance(by: 600)
        model.done()
        let json = try model.exportJSON()
        let csv = try String(bytes: model.exportCSV(), encoding: .utf8) ?? ""
        #expect(csv.contains(",work,Write,0"))

        try model.deleteAllData()
        #expect(model.labels.isEmpty)
        #expect(model.engine.plan.tasks.isEmpty)
        #expect(folder.allFiles().isEmpty)

        let summary = try model.importJSON(json)
        #expect(summary.newSessions == 1)
        #expect(model.labels.map(\.name) == ["work"])
        #expect(model.engine.plan.tasks.map(\.status) == [.done])
        #expect(try store.loadDailyTotals()[.ymd("2026-10-26"), model.labels[0].id].seconds == 600)
    }

    @Test func updatingLabelsSavesThem() throws {
        let store = makeStore()
        let model = try KettleModel(store: store, clock: clock, calendar: calendar)
        let label = Label(name: "garden", colorHex: "#00FF00")
        model.updateLabels([label])
        model.updateLabels([label])
        try store.flush()
        #expect(try makeStore().loadLabels() == [label])
    }
}
