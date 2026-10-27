import Foundation
import KettleCore

/// Fills the dev data folder (or `KETTLE_DATA_DIR`) with two weeks of realistic demo data:
/// labels (one archived), finished past days with sessions, today's plan and tomorrow's.
/// Deterministic, so every seeded folder looks the same relative to today.
enum Seed {
    static func run(arguments: [String]) throws {
        let brewing = arguments.contains("--brewing")
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )
        let folder = DataLocation.resolve(
            environment: ProcessInfo.processInfo.environment,
            bundleIdentifier: Kettle.devBundleID,
            applicationSupport: applicationSupport
        )
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        guard existing.allSatisfy({ $0 == ".DS_Store" }) else {
            throw ToolError("\(folder.path) already has data. Run make reset-dev first.")
        }

        let calendar = Calendar.autoupdatingCurrent
        let store = JSONStore(directory: folder, calendar: calendar)
        var generator = DemoGenerator(calendar: calendar, today: LocalDate(Date(), in: calendar))
        let data = generator.make(brewing: brewing)

        store.saveLabels(data.labels)
        for plan in data.plans {
            store.savePlan(plan)
        }
        for session in data.sessions {
            try store.appendSession(session)
        }
        try store.flush()
        try DailyTotalsCache(store: store, calendar: calendar).rebuild()
        try store.flush()

        print("Seeded \(folder.path): \(data.labels.count) labels, \(data.plans.count) days, "
            + "\(data.sessions.count) sessions\(brewing ? ", first task brewing" : "")")
    }
}

/// Builds the demo data with a fixed-seed generator.
struct DemoGenerator {
    struct Output {
        var labels: [Label]
        var plans: [DayPlan]
        var sessions: [Session]
    }

    let calendar: Calendar
    let today: LocalDate
    private var state: UInt64 = 7

    init(calendar: Calendar, today: LocalDate) {
        self.calendar = calendar
        self.today = today
    }

    static let catalogue: [(label: String, titles: [String])] = [
        ("work", ["Write report", "Deep work", "Code review", "Plan sprint", "Team sync", "Design doc"]),
        ("admin", ["Emails", "Invoices", "Calendar cleanup"]),
        ("health", ["Gym", "Run", "Yoga", "Walk"]),
        ("learning", ["Read a chapter", "Swift course", "Spanish practice"]),
        ("home", ["Groceries", "Laundry", "Cook dinner"]),
        ("garden", ["Water plants", "Weed the beds"]),
    ]

    mutating func make(brewing: Bool) -> Output {
        let labels = Self.catalogue.enumerated().map { index, entry in
            // "garden" was archived after the first week; its stats stay.
            Label(name: entry.label, colorHex: Label.palette[index], isArchived: entry.label == "garden")
        }
        var plans: [DayPlan] = []
        var sessions: [Session] = []
        for offset in -14 ... -1 {
            let (plan, daySessions) = pastDay(today.adding(days: offset), labels: labels, archivedGarden: offset > -8)
            plans.append(plan)
            sessions += daySessions
        }
        plans.append(upcomingDay(today, labels: labels, count: 5, brewing: brewing))
        plans.append(upcomingDay(today.adding(days: 1), labels: labels, count: 3, brewing: false))
        return Output(labels: labels, plans: plans, sessions: sessions)
    }

    private mutating func pastDay(_ date: LocalDate, labels: [Label], archivedGarden: Bool) -> (DayPlan, [Session]) {
        let weekend = date.weekday == 1 || date.weekday == 7
        let usable = labels.filter { weekend ? ["health", "home", "learning", "garden"].contains($0.name) : true }
            .filter { !(archivedGarden && $0.name == "garden") }
        let startMinutes = 8 * 60 + 30 + next(5) * 15 // 08:30 to 09:30
        let start = LocalTime(hour: startMinutes / 60, minute: startMinutes % 60) ?? .midnight
        var plan = DayPlan(date: date, startTime: start)
        var sessions: [Session] = []
        var clock = date.date(at: start, in: calendar)

        for _ in 0 ..< (weekend ? 2 + next(3) : 4 + next(4)) {
            let label = usable[next(usable.count)]
            let titles = Self.catalogue.first { $0.label == label.name }?.titles ?? ["Task"]
            var task = PlanTask(title: titles[next(titles.count)], labelID: label.id, plannedMinutes: 15 + next(16) * 5)
            let outcome = next(20)
            if outcome < 15 { // done, sometimes over time and extended
                let actual = task.plannedMinutes * 60 * (70 + next(70)) / 100
                let overrun = actual - task.plannedMinutes * 60
                if overrun > 0 {
                    task.extendedMinutes = (overrun + 599) / 600 * 10
                }
                task.status = .done
                task.brewedSeconds = actual
                // One session, or two with a short break in between.
                let split = next(3) == 0 ? actual / 2 : actual
                sessions.append(Session(
                    taskID: task.id,
                    labelID: label.id,
                    start: clock,
                    end: clock + TimeInterval(split),
                    extensionsMinutes: 0
                ))
                clock += TimeInterval(split)
                if split < actual {
                    clock += TimeInterval(300 + next(600))
                    sessions.append(Session(
                        taskID: task.id,
                        labelID: label.id,
                        start: clock,
                        end: clock + TimeInterval(actual - split),
                        extensionsMinutes: task.extendedMinutes
                    ))
                    clock += TimeInterval(actual - split)
                } else if task.extendedMinutes > 0 {
                    sessions[sessions.count - 1].extensionsMinutes = task.extendedMinutes
                }
            } else if outcome < 17 {
                task.status = .skipped
            }
            plan.tasks.append(task)
            clock += TimeInterval(60 * next(20))
        }
        return (plan, sessions)
    }

    private mutating func upcomingDay(_ date: LocalDate, labels: [Label], count: Int, brewing: Bool) -> DayPlan {
        let active = labels.filter { !$0.isArchived }
        var plan = DayPlan(date: date)
        for index in 0 ..< count {
            let label = active[next(active.count)]
            let titles = Self.catalogue.first { $0.label == label.name }?.titles ?? ["Task"]
            var task = PlanTask(title: titles[next(titles.count)], labelID: label.id, plannedMinutes: 20 + next(9) * 5)
            if brewing, index == 0 {
                // As if Start had just been pressed.
                let now = Date()
                task.status = .brewing
                task.brewingSince = now
                task.fixedStart = now
                plan.startTime = LocalTime(now, in: .autoupdatingCurrent)
            }
            plan.tasks.append(task)
        }
        return plan
    }

    /// A number in `0 ..< bound` from a 64-bit LCG.
    private mutating func next(_ bound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 33) % UInt64(bound))
    }
}
