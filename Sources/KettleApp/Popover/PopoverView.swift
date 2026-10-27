import KettleCore
import SwiftUI

/// The day plan: day switcher, quick add, the blocks, and the timer controls.
struct PopoverView: View {
    @Bindable var state: PopoverState
    let openSettings: () -> Void
    let openStats: () -> Void
    @FocusState private var quickAddFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            quickAddField
            Divider()
            TimelineView(.everyMinute) { context in
                taskList(now: context.date)
            }
            Divider()
            footer
        }
        .frame(width: 360, height: 460)
        .background(hiddenShortcuts)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button { state.showDay(offset: -1) } label: { Image(systemName: "chevron.left") }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .accessibilityLabel("Previous day")
            Spacer()
            VStack(spacing: 0) {
                Text(DayTitle.relative(state.date, today: state.today)).font(.headline)
                Text(DayTitle.long(state.date, calendar: state.calendar)).font(.caption).foregroundStyle(.secondary)
            }
            .onTapGesture { state.showToday() }
            Spacer()
            Button { state.showDay(offset: 1) } label: { Image(systemName: "chevron.right") }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .accessibilityLabel("Next day")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var quickAddField: some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField("Add a task, e.g. Write report 45m #work", text: $state.quickAdd)
                .textFieldStyle(.roundedBorder)
                .focused($quickAddFocused)
                .onSubmit { state.submitQuickAdd() }
            if let error = state.quickAddError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: Tasks

    @ViewBuilder
    private func taskList(now: Date) -> some View {
        if state.plan.tasks.isEmpty {
            Text("Nothing on the stove. Add your first task.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let schedule = state.schedule(now: now)
            List {
                ForEach(state.plan.tasks) { task in
                    TaskRow(
                        task: task,
                        label: state.label(for: task),
                        block: schedule[task.id],
                        isActive: task.id == state.activeTaskID,
                        state: state
                    )
                }
                .onMove { state.move(from: $0, to: $1) }
                if PlanEngine.isComplete(state.plan) {
                    Text(state.date == state.today ? "All brewed for today." : "All brewed.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if state.isTimerDay {
                Button(toggleTitle) { state.toggle() }
                    .disabled(!state.hasStartableTask)
                Button("Done") { state.done() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(state.activeTaskID == nil)
                Button("Keep brewing +\(state.settings.extendMinutes)m") { state.keepBrewing() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(!state.isBrewing)
                Spacer()
                if state.yesterdayUnfinished > 0 {
                    Button("Carry over \(state.yesterdayUnfinished)") { state.carryOver() }
                        .help("Move yesterday's unfinished tasks to the end of today")
                }
            } else {
                Text("Planning \(DayTitle.relative(state.date, today: state.today).lowercased())")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Back to today") { state.showToday() }
            }
            Button(action: openStats) { Image(systemName: "chart.bar") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Stats")
            Button(action: openSettings) { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .keyboardShortcut(",", modifiers: .command)
                .accessibilityLabel("Settings")
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var toggleTitle: String {
        if state.isBrewing {
            return "Pause"
        }
        return state.activeTaskID == nil ? "Start" : "Resume"
    }

    /// Shortcuts without a visible button.
    private var hiddenShortcuts: some View {
        Button("New task") { quickAddFocused = true }
            .keyboardShortcut("n", modifiers: .command)
            .hidden()
    }
}

/// Day names for the header.
enum DayTitle {
    static func relative(_ date: LocalDate, today: LocalDate) -> String {
        switch date.dayNumber - today.dayNumber {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        default: "\(date)"
        }
    }

    static func long(_ date: LocalDate, calendar: Calendar) -> String {
        date.date(in: calendar).formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}
