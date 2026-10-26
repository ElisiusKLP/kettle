import Foundation
@testable import KettleCore
import Testing

struct JSONStoreTests {
    let folder: TemporaryDirectory
    let scheduler = ManualScheduler()
    let calendar = Calendar.gregorian("Europe/Copenhagen")
    let today = LocalDate.ymd("2026-10-26")

    init() throws {
        folder = try TemporaryDirectory()
    }

    func makeStore(fileSystem: FileSystem = LocalFileSystem(), migrator: Migrator = .standard) -> JSONStore {
        JSONStore(
            directory: folder.url, fileSystem: fileSystem, scheduler: scheduler, migrator: migrator, calendar: calendar
        )
    }

    // MARK: Round trip

    @Test func missingFilesLoadAsDefaults() throws {
        let store = makeStore()
        #expect(try store.loadSettings() == AppSettings())
        #expect(try store.loadLabels().isEmpty)
        #expect(try store.loadPlan(for: today) == DayPlan(date: today))
        #expect(try store.loadSessions(monthOf: today).isEmpty)
        #expect(folder.allFiles().isEmpty)
    }

    @Test func roundTripsEveryDocument() throws {
        var settings = AppSettings()
        settings.extendMinutes = 20
        settings.timerPrecision = .minutes
        settings.weekStartsOn = .sunday
        let work = Label(name: "work", colorHex: "#C8743A")
        let plan = DayPlan(date: today, tasks: [
            PlanTask(
                title: "Write report",
                labelID: work.id,
                plannedMinutes: 45,
                notes: "draft",
                status: .brewing,
                extendedMinutes: 10,
                brewedSeconds: 120,
                brewingSince: .iso("2026-10-26T08:00:00Z")
            ),
            PlanTask(title: "Emails", plannedMinutes: 20),
        ], startTime: LocalTime("09:00"))
        let session = Session(
            taskID: plan.tasks[0].id,
            labelID: work.id,
            start: .iso("2026-10-26T07:00:00Z"),
            end: .iso("2026-10-26T07:45:00Z"),
            extensionsMinutes: 10
        )

        let store = makeStore()
        store.saveSettings(settings)
        store.saveLabels([work])
        store.savePlan(plan)
        try store.appendSession(session)
        try store.flush()

        let reopened = makeStore()
        #expect(try reopened.loadSettings() == settings)
        #expect(try reopened.loadLabels() == [work])
        #expect(try reopened.loadPlan(for: today) == plan)
        #expect(try reopened.loadSessions(monthOf: today) == [session])
    }

    @Test func fixtureFolderLoadsAndRewritesByteForByte() throws {
        try Fixtures.copy(to: folder)
        let store = makeStore()
        let settings = try store.loadSettings()
        let labels = try store.loadLabels()
        let plan = try store.loadPlan(for: today)
        let sessions = try store.loadSessions(monthOf: today)
        #expect(settings.extendMinutes == 15)
        #expect(labels.map(\.name) == ["work", "health"])
        #expect(plan.tasks.map(\.status) == [.done, .brewing, .pending])
        #expect(sessions.count == 2)

        for file in Fixtures.files {
            try FileManager.default.removeItem(at: folder.url.appendingPathComponent(file))
        }
        store.saveSettings(settings)
        store.saveLabels(labels)
        store.savePlan(plan)
        for session in sessions {
            try store.appendSession(session)
        }
        try store.flush()

        for file in Fixtures.files {
            let expected = try String(contentsOf: Fixtures.dataFolder.appendingPathComponent(file), encoding: .utf8)
            #expect(try folder.read(file) == expected, "\(file) differs from its fixture")
        }
    }

    @Test func everyFileCarriesASchemaVersion() throws {
        let store = makeStore()
        store.saveSettings(AppSettings())
        store.saveLabels([])
        store.savePlan(DayPlan(date: today))
        try store.appendSession(Session(
            taskID: UUID(),
            labelID: nil,
            start: .iso("2026-10-26T07:00:00Z"),
            end: .iso("2026-10-26T07:01:00Z")
        ))
        try store.flush()
        for file in ["settings.json", "labels.json", "plans/2026-10-26.json", "sessions/2026-10.json"] {
            #expect(try folder.read(file).contains(#""schemaVersion" : 1"#), "\(file)")
        }
    }

    // MARK: Startup

    @Test func startupLoadsOnlySettingsLabelsAndTodaysPlan() throws {
        try Fixtures.copy(to: folder)
        try folder.write(#"{"date":"2026-10-25","schemaVersion":1,"tasks":[]}"#, to: "plans/2026-10-25.json")
        try folder.write(#"{"date":"2026-10-27","schemaVersion":1,"tasks":[]}"#, to: "plans/2026-10-27.json")
        let fileSystem = RecordingFileSystem(root: folder.url)

        let snapshot = try makeStore(fileSystem: fileSystem).loadStartupSnapshot(today: today)

        #expect(Set(fileSystem.reads) == ["settings.json", "labels.json", "plans/2026-10-26.json"])
        #expect(fileSystem.reads.count == 3)
        #expect(snapshot.today.date == today)
        #expect(snapshot.labels.count == 2)
        #expect(snapshot.settings.extendMinutes == 15)
    }

    // MARK: Debouncing

    @Test func savesAreDebouncedIntoOneWritePerFile() throws {
        let fileSystem = RecordingFileSystem(root: folder.url)
        let store = makeStore(fileSystem: fileSystem)
        for minutes in [10, 20, 30] {
            store.savePlan(DayPlan(date: today, tasks: [PlanTask(title: "Tea", plannedMinutes: minutes)]))
        }
        store.saveSettings(AppSettings())

        #expect(fileSystem.writes.isEmpty)
        #expect(scheduler.scheduled.count == 1)
        #expect(scheduler.scheduled.first?.delay == 0.5)

        scheduler.runAll()

        #expect(fileSystem.writes.sorted() == ["plans/2026-10-26.json", "settings.json"])
        #expect(try makeStore().loadPlan(for: today).tasks.first?.plannedMinutes == 30)
        #expect(!store.hasPendingWrites)
    }

    @Test func pendingSavesAreVisibleBeforeTheyAreWritten() throws {
        let store = makeStore()
        let plan = DayPlan(date: today, tasks: [PlanTask(title: "Tea", plannedMinutes: 5)])
        store.savePlan(plan)
        #expect(try store.loadPlan(for: today) == plan)
        #expect(folder.allFiles().isEmpty)
    }

    @Test func manualFlushCancelsTheScheduledOne() throws {
        let fileSystem = RecordingFileSystem(root: folder.url)
        let store = makeStore(fileSystem: fileSystem)
        store.saveSettings(AppSettings())
        try store.flush()
        store.saveLabels([])
        #expect(scheduler.scheduled.count == 2)

        scheduler.runAll()

        // The first scheduled flush is stale and does nothing; the second writes the labels.
        #expect(fileSystem.writes == ["settings.json", "labels.json"])
    }

    @Test func failedWritesStayPendingAndAreRetried() throws {
        let fileSystem = RecordingFileSystem(root: folder.url)
        let store = makeStore(fileSystem: fileSystem)
        var reported: [Error] = []
        store.onWriteError = { reported.append($0) }
        fileSystem.failWrites = true
        store.saveSettings(AppSettings())

        scheduler.runAll()
        #expect(reported.count == 1)
        #expect(store.hasPendingWrites)

        fileSystem.failWrites = false
        try store.flush()
        #expect(!store.hasPendingWrites)
        #expect(fileSystem.writes == ["settings.json"])
    }

    // MARK: Sessions

    @Test func sessionsGoToTheLocalMonthOfTheirStart() throws {
        let store = makeStore()
        // 23:30 UTC on 31 October is 00:30 on 1 November in Copenhagen.
        let session = Session(
            taskID: UUID(),
            labelID: nil,
            start: .iso("2026-10-31T23:30:00Z"),
            end: .iso("2026-11-01T00:10:00Z")
        )
        try store.appendSession(session)
        try store.flush()
        #expect(folder.allFiles() == ["sessions/2026-11.json"])
        #expect(try store.loadSessions(monthOf: .ymd("2026-11-15")) == [session])
    }

    @Test func appendingKeepsEarlierSessions() throws {
        try Fixtures.copy(to: folder)
        let store = makeStore()
        let session = Session(
            taskID: UUID(),
            labelID: nil,
            start: .iso("2026-10-26T10:00:00Z"),
            end: .iso("2026-10-26T10:30:00Z")
        )
        try store.appendSession(session)
        try store.flush()
        let sessions = try makeStore().loadSessions(monthOf: today)
        #expect(sessions.count == 3)
        #expect(sessions.last == session)
    }

    // MARK: Atomic writes

    @Test func writesReplaceTheFileAndLeaveNoTemporaryFiles() throws {
        try folder.write("old contents", to: "settings.json")
        let fileSystem = LocalFileSystem()
        let url = folder.url.appendingPathComponent("settings.json")
        try fileSystem.writeAtomically(Data("new contents".utf8), to: url)
        #expect(try folder.read("settings.json") == "new contents")
        #expect(folder.allFiles() == ["settings.json"])
    }

    @Test func failedReplaceKeepsTheDestinationAndCleansUp() throws {
        // A non-empty folder can't be replaced by a file, so the final rename fails.
        try folder.write("keep me", to: "settings.json/inside.txt")
        let url = folder.url.appendingPathComponent("settings.json")
        #expect(throws: POSIXError.self) {
            try LocalFileSystem().writeAtomically(Data("new".utf8), to: url)
        }
        #expect(try folder.read("settings.json/inside.txt") == "keep me")
        #expect(folder.allFiles() == ["settings.json/inside.txt"])
    }

    @Test func createsMissingFolders() throws {
        let url = folder.url.appendingPathComponent("plans/deep/file.json")
        try LocalFileSystem().writeAtomically(Data("{}".utf8), to: url)
        #expect(try folder.read("plans/deep/file.json") == "{}")
    }

    // MARK: Unreadable files are never overwritten

    @Test func corruptFileIsReportedAndProtected() throws {
        try folder.write("{ not json", to: "settings.json")
        let store = makeStore()
        var reported: [Error] = []
        store.onWriteError = { reported.append($0) }

        #expect(throws: StoreError.self) { try store.loadSettings() }
        store.saveSettings(AppSettings())
        try store.flush()

        #expect(try folder.read("settings.json") == "{ not json")
        #expect(reported.first as? StoreError == .writeBlocked(path: "settings.json"))
    }

    @Test func fixedFileCanBeSavedAgain() throws {
        try folder.write("{ not json", to: "labels.json")
        let store = makeStore()
        #expect(throws: StoreError.self) { try store.loadLabels() }
        try folder.write(#"{"labels":[],"schemaVersion":1}"#, to: "labels.json")
        #expect(try store.loadLabels().isEmpty)
        store.saveLabels([Label(name: "work", colorHex: "#000000")])
        try store.flush()
        #expect(try makeStore().loadLabels().map(\.name) == ["work"])
    }

    @Test func newerSchemaIsRefused() throws {
        try folder.write(#"{"labels":[],"schemaVersion":2}"#, to: "labels.json")
        let store = makeStore()
        #expect(throws: StoreError.self) { try store.loadLabels() }
        store.saveLabels([])
        try store.flush()
        #expect(try folder.read("labels.json").contains(#""schemaVersion":2"#))
    }

    @Test func missingSchemaVersionIsRefused() throws {
        try folder.write(#"{"labels":[]}"#, to: "labels.json")
        #expect(throws: StoreError.self) { try makeStore().loadLabels() }
    }
}

// MARK: - Migrations

extension JSONStoreTests {
    /// A hypothetical history for labels.json: v1 called the array "items", v2 renamed it to
    /// "labels", and v3 added `isArchived`.
    static let labelsMigrator = Migrator(currentVersions: [.labels: 3], steps: [.labels: [
        1: { object in
            object["labels"] = object.removeValue(forKey: "items")
        },
        2: { object in
            let labels = object["labels"] as? [[String: Any]] ?? []
            object["labels"] = labels.map { label in
                var label = label
                label["isArchived"] = false
                return label
            }
        },
    ]])

    @Test func migratesOlderFilesStepByStep() throws {
        try folder.write(
            ##"{"schemaVersion":1,"items":[{"id":"8A0C3E52-6B0E-4C55-9C0A-2F4C1D7B1A01","name":"work","##
                + ##""colorHex":"#fff"}]}"##,
            to: "labels.json"
        )
        let store = makeStore(migrator: Self.labelsMigrator)
        let labels = try store.loadLabels()
        #expect(labels.map(\.name) == ["work"])
        #expect(labels.first?.isArchived == false)

        store.saveLabels(labels)
        try store.flush()
        #expect(try folder.read("labels.json").contains(#""schemaVersion" : 3"#))
    }

    @Test func migratesFromAnIntermediateVersion() throws {
        try folder.write(#"{"schemaVersion":2,"labels":[]}"#, to: "labels.json")
        #expect(try makeStore(migrator: Self.labelsMigrator).loadLabels().isEmpty)
    }

    @Test func missingMigrationStepIsAnError() throws {
        let migrator = Migrator(currentVersions: [.labels: 2], steps: [:])
        let data = Data(#"{"schemaVersion":1,"labels":[]}"#.utf8)
        #expect(throws: MigrationError.missingStep(kind: .labels, from: 1)) {
            try migrator.decode(LabelList.self, from: data, using: KettleJSON.makeDecoder())
        }
    }

    @Test func migratorRejectsNewerAndUnversionedFiles() throws {
        let decoder = KettleJSON.makeDecoder()
        #expect(throws: MigrationError.newerSchema(kind: .settings, found: 9, supported: 1)) {
            try Migrator.standard.decode(AppSettings.self, from: Data(#"{"schemaVersion":9}"#.utf8), using: decoder)
        }
        #expect(throws: MigrationError.missingSchemaVersion) {
            try Migrator.standard.decode(AppSettings.self, from: Data("{}".utf8), using: decoder)
        }
    }

    @Test func standardMigratorIsAtVersionOneForEveryKind() {
        for kind in DocumentKind.allCases {
            #expect(Migrator.standard.currentVersion(of: kind) == 1)
        }
    }
}
