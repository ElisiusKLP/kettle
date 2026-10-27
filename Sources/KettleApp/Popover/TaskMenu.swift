import KettleCore
import SwiftUI

/// A task's right-click menu, in both the list and the calendar: the timer actions that apply
/// to it (`TimerControls`), then Delete.
struct TaskMenu: View {
    let task: PlanTask
    let state: PopoverState

    var body: some View {
        ForEach(state.actions(for: task), id: \.self) { action in
            switch action {
            case .start: Button("Start") { state.start(task.id) }
            case .pause: Button("Pause") { state.toggle() }
            case .resume: Button("Resume") { state.toggle() }
            case .done: Button("Done") { state.done(task.id) }
            case .keepBrewing: Button("Keep brewing +\(state.settings.extendMinutes)m") { state.keepBrewing(task.id) }
            case .skip: Button("Skip") { state.skip(task.id) }
            }
        }
        if task.status == .pending, let time = task.fixedStart {
            let text = state.date.date(at: time, in: state.calendar).formatted(date: .omitted, time: .shortened)
            Button("Unpin from \(text)") { state.unpin(task.id) }
        }
        Divider()
        Button("Delete", role: .destructive) { state.remove(task.id) }
    }
}

/// The active task's live countdown. Ticks once a second, but only while the popover is open
/// and only for this one task.
struct Countdown: View {
    let task: PlanTask

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = task.remainingSeconds(at: context.date)
            Text(CountdownFormatter.string(remaining: remaining, precision: .seconds))
                .monospacedDigit()
                .accessibilityLabel(StatusDescription.spoken(remaining: remaining))
        }
    }
}
