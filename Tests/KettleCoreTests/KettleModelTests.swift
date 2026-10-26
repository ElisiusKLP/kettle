import Foundation
@testable import KettleCore
import Testing

struct KettleModelTests {
    let folder: TemporaryDirectory
    let calendar = Calendar.gregorian("Europe/Copenhagen")
    let today = LocalDate.ymd("2026-10-26")
    /// 09:00 in Copenhagen on `today`.
    let clock = FakeClock(.iso("2026-10-26T08:00:00Z"))

    init() throws {
        folder = try TemporaryDirectory()
    }

    func makeStore() -> JSONStore {
        JSONStore(directory: folder.url, scheduler: ManualScheduler(), calendar: calendar)
    }

    func makeModel(_ store: JSONStore? = nil) throws -> KettleModel {
        try KettleModel(store: store ?? makeStore(), clock: clock, calendar: calendar)
    }

    @Test func startsWithTodaysPlanAndDefaults() throws {
        let model = try makeModel()
        #expect(model.engine.plan == DayPlan(date: today))
        #expect(model.labels.isEmpty)
        #expect(model.settings == AppSettings())
        #expect(model.today == today)
    }

    @Test func quickAddSavesThePlanAndNewLabels() throws {
        let store = makeStore()
        let model = try makeModel(store)
        let task = try model.add(QuickAddParser.parse("Write report 45m #work"))
        try store.flush()

        let reopened = try makeModel()
        #expect(reopened.engine.plan.tasks == [task])
        #expect(reopened.labels.map(\.name) == ["work"])
        #expect(task.labelID == reopened.labels.first?.id)
    }

    @Test func timerActionsSaveThePlanAndRecordSessionsAndStats() throws {
        let store = makeStore()
        let model = try makeModel(store)
        try model.add(QuickAddParser.parse("Write report 45m #work"))
        try model.add(QuickAddParser.parse("Emails 20"))

        model.toggle()
        clock.advance(by: 600)
        model.toggle() // pause
        model.start() // resume
        model.keepBrewing()
        clock.advance(by: 300)
        model.done()
        try store.flush()

        let sessions = try store.loadSessions(monthOf: today)
        #expect(sessions.map(\.duration) == [600, 300])
        #expect(sessions.last?.extensionsMinutes == 10)
        let reopened = try makeModel()
        #expect(reopened.engine.plan.tasks.map(\.status) == [.done, .pending])
        let workID = try #require(reopened.labels.first?.id)
        let totals = try store.loadDailyTotals()[today, workID]
        #expect(totals.seconds == 900)
        #expect(totals.sessions == 2)
        #expect(totals.tasksDone == 1)
        #expect(totals.plannedMinutes == 45)
        #expect(totals.extendedMinutes == 10)
    }

    @Test func secondaryKeepBrewingUsesItsOwnAmount() throws {
        let model = try makeModel()
        var settings = model.settings
        settings.secondaryExtendMinutes = 7
        model.updateSettings(settings)
        model.add(QuickAddEntry(title: "Tea", minutes: 5, labelName: nil))
        model.start()
        model.keepBrewing(secondary: true)
        #expect(model.engine.activeTask?.extendedMinutes == 7)
    }

    @Test func settingsAreSavedAndReachTheTimer() throws {
        let store = makeStore()
        let model = try makeModel(store)
        var settings = model.settings
        settings.autoStartNext = true
        model.updateSettings(settings)
        model.updateSettings(settings)
        try store.flush()
        #expect(model.engine.settings.autoStartNext)
        #expect(try makeModel().settings.autoStartNext)
    }

    @Test func skipAndPlanEditsAreSaved() throws {
        let store = makeStore()
        let model = try makeModel(store)
        let first = model.add(QuickAddEntry(title: "A", minutes: 10, labelName: nil))
        let second = model.add(QuickAddEntry(title: "B", minutes: 10, labelName: nil))
        model.skip(taskID: first.id)
        model.editPlan { PlanEngine.adjust(taskID: second.id, byMinutes: 5, in: &$0) }
        model.pause() // nothing brewing: no change, no save
        try store.flush()
        let tasks = try makeModel().engine.plan.tasks
        #expect(tasks.map(\.status) == [.skipped, .pending])
        #expect(tasks[1].plannedMinutes == 15)
    }

    @Test func rollsOverToTheNewDayWhenIdle() throws {
        let store = makeStore()
        store.savePlan(DayPlan(date: today.adding(days: 1), tasks: [PlanTask(title: "Tomorrow", plannedMinutes: 5)]))
        let model = try makeModel(store)
        #expect(!model.rollOverIfNeeded())
        clock.advance(by: 16 * 3600) // 01:00 the next day
        #expect(model.rollOverIfNeeded())
        #expect(model.engine.plan.date == today.adding(days: 1))
        #expect(model.engine.plan.tasks.map(\.title) == ["Tomorrow"])
    }

    @Test func aBlockRunningPastMidnightKeepsItsDayUntilDone() throws {
        let model = try makeModel()
        model.add(QuickAddEntry(title: "Late", minutes: 120, labelName: nil))
        clock.advance(by: 14.5 * 3600) // 23:30
        model.start()
        clock.advance(by: 3600) // 00:30 the next day
        #expect(!model.rollOverIfNeeded())
        #expect(model.engine.plan.date == today)
        model.done()
        #expect(model.engine.plan.date == today.adding(days: 1))
    }

    @Test func saveErrorsAreReported() throws {
        try folder.write("{ broken", to: "plans/2026-10-26.json")
        #expect(throws: StoreError.self) { try makeModel() }

        try FileManager.default.removeItem(at: folder.url.appendingPathComponent("plans/2026-10-26.json"))
        let model = try makeModel()
        try folder.write("{ broken", to: StorePath.dailyTotals)
        var errors: [Error] = []
        model.onError = { errors.append($0) }
        model.add(QuickAddEntry(title: "A", minutes: 5, labelName: nil))
        #expect(errors.first is StoreError)

        try folder.write("{ broken", to: "plans/2026-10-27.json")
        clock.advance(by: 86400)
        #expect(!model.rollOverIfNeeded())
        #expect(errors.count == 2)
    }

    @Test func flushWritesPendingChanges() throws {
        let model = try makeModel()
        model.add(QuickAddEntry(title: "A", minutes: 5, labelName: nil))
        #expect(folder.allFiles().isEmpty)
        model.flush()
        #expect(folder.allFiles().contains("plans/2026-10-26.json"))
    }
}
