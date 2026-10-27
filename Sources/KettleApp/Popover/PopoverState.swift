import Foundation
import KettleCore
import Observation

/// What the popover shows, created when it opens and dropped when it closes. It copies what it
/// needs from `KettleModel` and reloads after each action, so no observation machinery runs
/// while the popover is closed.
@Observable
final class PopoverState {
    /// The day being shown. Other days are read from disk on demand and not kept.
    private(set) var date: LocalDate
    private(set) var plan: DayPlan
    private(set) var labels: [Label] = []
    private(set) var settings = AppSettings()
    /// Unfinished tasks from yesterday, offered by "Carry over unfinished".
    private(set) var yesterdayUnfinished = 0
    var quickAdd = ""
    var quickAddError: String?

    @ObservationIgnored private let model: KettleModel
    /// Called after every change. The app reloads this state in response.
    @ObservationIgnored private let onChange: () -> Void
    @ObservationIgnored let calendar = Calendar.autoupdatingCurrent

    init(model: KettleModel, onChange: @escaping () -> Void) {
        self.model = model
        self.onChange = onChange
        date = model.engine.plan.date
        plan = model.engine.plan
        reload()
    }

    /// True when the shown day is the timer's day, where Start, Done and friends apply.
    var isTimerDay: Bool {
        date == model.engine.plan.date
    }

    var today: LocalDate {
        model.today
    }

    // These read the observed `plan` copy, not the model, so SwiftUI redraws when they change.

    var activeTaskID: UUID? {
        isTimerDay ? plan.tasks.first { $0.status == .brewing || $0.status == .paused }?.id : nil
    }

    /// Which timer buttons apply on the timer's day.
    var controls: TimerControls {
        TimerControls(plan: plan, reopenableID: model.engine.reopenableID)
    }

    /// The timer actions for a task's context menu.
    func actions(for task: PlanTask) -> [TimerControls.TaskAction] {
        TimerControls.actions(for: task, isTimerDay: isTimerDay, reopenableID: model.engine.reopenableID)
    }

    // MARK: Days

    func showDay(offset: Int) {
        date = date.adding(days: offset)
        reload()
    }

    func showToday() {
        date = model.engine.plan.date
        reload()
    }

    // MARK: Actions

    func submitQuickAdd() {
        do {
            let entry = try QuickAddParser.parse(quickAdd)
            model.add(entry, to: date)
            quickAdd = ""
            quickAddError = nil
            changed()
        } catch QuickAddError.emptyTitle {
            quickAddError = "Add a title, like “Emails 20m #admin”."
        } catch {
            quickAddError = "Durations go from 1 minute to 12 hours."
        }
    }

    func toggle() {
        act { $0.toggle() }
    }

    /// Finishes the active task, or marks `taskID` done.
    func done(_ taskID: UUID? = nil) {
        act { $0.done(taskID: taskID) }
    }

    /// Keep brewing the brewing task, or `taskID` (which may have just finished).
    func keepBrewing(_ taskID: UUID? = nil) {
        act { $0.keepBrewing(taskID: taskID) }
    }

    func start(_ taskID: UUID) {
        act { $0.start(taskID: taskID) }
    }

    func skip(_ taskID: UUID) {
        if isTimerDay {
            act { $0.skip(taskID: taskID) }
        } else {
            edit { plan in
                guard let index = plan.tasks.firstIndex(where: { $0.id == taskID }) else { return }
                plan.tasks[index].status = .skipped
            }
        }
    }

    func remove(_ taskID: UUID) {
        edit { PlanEngine.remove(taskID: taskID, from: &$0) }
    }

    func move(from source: IndexSet, to destination: Int) {
        edit { PlanEngine.move(in: &$0, fromOffsets: source, toOffset: destination) }
    }

    func adjust(_ taskID: UUID, by minutes: Int) {
        edit { PlanEngine.adjust(taskID: taskID, byMinutes: minutes, in: &$0) }
    }

    func carryOver() {
        act { $0.carryOverUnfinished() }
    }

    // MARK: Display helpers

    /// Derived start and end times, or nil when the day has no anchor yet.
    func schedule(now: Date) -> [UUID: ScheduledBlock] {
        guard let anchor = PlanEngine.anchor(for: plan, today: today, now: now, calendar: calendar) else {
            return [:]
        }
        let live = date == today ? now : nil
        let blocks = PlanEngine.schedule(for: plan, from: anchor, now: live)
        return Dictionary(uniqueKeysWithValues: blocks.map { ($0.taskID, $0) })
    }

    func label(for task: PlanTask) -> Label? {
        task.labelID.flatMap { id in labels.first { $0.id == id } }
    }

    // MARK: Private

    private func act(_ action: (KettleModel) -> Void) {
        guard isTimerDay else { return }
        action(model)
        changed()
    }

    private func edit(_ change: (inout DayPlan) -> Void) {
        model.editPlan(for: date, change)
        changed()
    }

    /// Tells the app, which redraws the menubar and calls `reload()`.
    private func changed() {
        onChange()
    }

    func reload() {
        do {
            plan = try model.plan(for: date)
        } catch {
            plan = DayPlan(date: date)
            quickAddError = "This day's plan couldn't be read, so it can't be changed."
        }
        labels = model.labels
        settings = model.settings
        let yesterday = today.adding(days: -1)
        yesterdayUnfinished = isTimerDay && date == today
            ? ((try? model.plan(for: yesterday)).map(PlanEngine.unfinishedCount) ?? 0)
            : 0
    }
}
