import Foundation
@testable import KettleCore
import Testing

struct DailyTotalsCacheTests {
    let folder: TemporaryDirectory
    let calendar = Calendar.gregorian("Europe/Copenhagen")
    let labels = (0 ..< 4).map { Label(name: "label\($0)", colorHex: Label.palette[$0]) }

    init() throws {
        folder = try TemporaryDirectory()
    }

    func makeStore() -> JSONStore {
        JSONStore(directory: folder.url, scheduler: ManualScheduler(), calendar: calendar)
    }

    /// A small deterministic generator (64-bit LCG), so the test is reproducible.
    struct Generator {
        var state: UInt64

        mutating func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
    }

    @Test func incrementalUpdatesMatchAFullRebuild() throws {
        let store = makeStore()
        let cache = DailyTotalsCache(store: store, calendar: calendar)
        var random = Generator(state: 42)
        let firstDay = LocalDate.ymd("2026-09-01")

        for dayOffset in 0 ..< 60 {
            let date = firstDay.adding(days: dayOffset)
            var plan = DayPlan(date: date)
            for index in 0 ..< random.next(5) {
                let label = random.next(5) == 4 ? nil : labels[random.next(labels.count)].id
                plan.tasks.append(PlanTask(title: "Task \(index)", labelID: label, plannedMinutes: 5 + random.next(90)))
            }
            // Brew some tasks, recording each session as it closes, sometimes late into the night.
            var clock = try date.date(
                at: #require(LocalTime(hour: 8 + random.next(15), minute: random.next(60))),
                in: calendar
            )
            for index in plan.tasks.indices {
                let session = Session(
                    taskID: plan.tasks[index].id,
                    labelID: plan.tasks[index].labelID,
                    start: clock,
                    end: clock + TimeInterval(60 + random.next(7200))
                )
                try store.appendSession(session)
                try cache.record([session])
                plan.tasks[index].brewedSeconds = Int(session.duration)
                clock = session.end + TimeInterval(random.next(1800))
                // Save the plan after every change, as the app does.
                plan.tasks[index].status = [.done, .done, .skipped, .paused][random.next(4)]
                if random.next(3) == 0 {
                    plan.tasks[index].extendedMinutes = 5 + random.next(20)
                }
                store.savePlan(plan)
                try cache.record(plan)
            }
            // Occasionally relabel a finished task afterwards.
            if let first = plan.tasks.indices.first, random.next(4) == 0 {
                plan.tasks[first].labelID = labels[random.next(labels.count)].id
                store.savePlan(plan)
                try cache.record(plan)
            }
        }
        try store.flush()
        let incremental = try cache.load()

        try FileManager.default.removeItem(at: folder.url.appendingPathComponent(StorePath.dailyTotals))
        let rebuilt = try DailyTotalsCache(store: makeStore(), calendar: calendar).rebuild()

        #expect(!incremental.days.isEmpty)
        #expect(incremental == rebuilt)
    }

    @Test func rebuildIsSavedAndReadable() throws {
        let store = makeStore()
        try store.appendSession(Session(
            taskID: UUID(),
            labelID: labels[0].id,
            start: .iso("2026-10-26T08:00:00Z"),
            end: .iso("2026-10-26T09:00:00Z")
        ))
        try store.flush()
        let cache = DailyTotalsCache(store: store, calendar: calendar)
        let rebuilt = try cache.rebuild()
        try store.flush()
        #expect(try makeStore().loadDailyTotals() == rebuilt)
        #expect(rebuilt[.ymd("2026-10-26"), labels[0].id].seconds == 3600)
    }

    @Test func sessionsAddUpAndCountOnTheirStartDay() throws {
        let cache = DailyTotalsCache(store: makeStore(), calendar: calendar)
        try cache.record([
            Session(
                taskID: UUID(),
                labelID: nil,
                start: .iso("2026-10-26T22:30:00Z"),
                end: .iso("2026-10-26T23:15:00Z")
            ),
            Session(
                taskID: UUID(),
                labelID: nil,
                start: .iso("2026-10-26T08:00:00Z"),
                end: .iso("2026-10-26T08:10:00Z")
            ),
        ])
        try cache.record([])
        let totals = try cache.load()
        #expect(totals[.ymd("2026-10-26"), nil].seconds == 2400)
        #expect(totals[.ymd("2026-10-26"), nil].sessions == 2)
        #expect(totals[.ymd("2026-10-27"), nil].seconds == 900)
        #expect(totals[.ymd("2026-10-27"), nil].sessions == 0)
    }

    @Test func planFiguresAreReplacedNotAdded() throws {
        let cache = DailyTotalsCache(store: makeStore(), calendar: calendar)
        let date = LocalDate.ymd("2026-10-26")
        var plan = DayPlan(date: date, tasks: [
            PlanTask(
                title: "A",
                labelID: labels[0].id,
                plannedMinutes: 45,
                status: .done,
                extendedMinutes: 10,
                brewedSeconds: 3300
            ),
            PlanTask(title: "B", labelID: labels[0].id, plannedMinutes: 30, status: .skipped),
        ])
        try cache.record(plan)
        try cache.record(plan)
        var figures = try cache.load()[date, labels[0].id]
        #expect(figures.tasksDone == 1)
        #expect(figures.plannedMinutes == 45)
        #expect(figures.doneSeconds == 3300)
        #expect(figures.tasksExtended == 1)
        #expect(figures.extendedMinutes == 10)

        plan.tasks[0].labelID = labels[1].id
        try cache.record(plan)
        let totals = try cache.load()
        #expect(totals.days[date]?[labels[0].id] == nil)
        figures = totals[date, labels[1].id]
        #expect(figures.plannedMinutes == 45)
    }

    @Test func storedFormatIsReadableJSON() throws {
        let store = makeStore()
        var totals = DailyTotals()
        totals[.ymd("2026-10-26"), labels[0].id].seconds = 60
        totals[.ymd("2026-10-26"), nil].sessions = 1
        store.saveDailyTotals(totals)
        try store.flush()
        let json = try folder.read(StorePath.dailyTotals)
        #expect(json.contains(#""2026-10-26" : {"#))
        #expect(json.contains(#""none" : {"#))
        #expect(json.contains("\"\(labels[0].id.uuidString)\" : {"))
        #expect(try makeStore().loadDailyTotals() == totals)
    }

    @Test(arguments: [
        #"{"schemaVersion":1,"days":{"2026-13-01":{}}}"#,
        #"{"schemaVersion":1,"days":{"2026-10-26":{"not-a-uuid":{}}}}"#,
    ])
    func invalidKeysAreRejected(json: String) throws {
        try folder.write(json, to: StorePath.dailyTotals)
        #expect(throws: StoreError.self) { try makeStore().loadDailyTotals() }
    }

    @Test func storeListsPlanDaysAndSessionMonths() throws {
        try Fixtures.copy(to: folder)
        try folder.write("{}", to: "plans/notes.txt")
        let store = makeStore()
        store.savePlan(DayPlan(date: .ymd("2026-09-30")))
        try store.appendSession(Session(
            taskID: UUID(),
            labelID: nil,
            start: .iso("2026-08-01T10:00:00Z"),
            end: .iso("2026-08-01T11:00:00Z")
        ))
        #expect(try store.planDates() == [.ymd("2026-09-30"), .ymd("2026-10-26")])
        #expect(try store.sessionMonths() == [.ymd("2026-08-01"), .ymd("2026-10-01")])
        #expect(try makeStore().planDates() == [.ymd("2026-10-26")])
    }

    @Test func emptyStoreRebuildsToNothing() throws {
        #expect(try DailyTotalsCache(store: makeStore(), calendar: calendar).rebuild() == DailyTotals())
    }
}
