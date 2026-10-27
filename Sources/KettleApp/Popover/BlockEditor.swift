import KettleCore
import SwiftUI

/// Set a block's length and its start and end times exactly (double-click a block). The three
/// fields stay in step: a new start keeps the length, a new end or length moves the end.
/// Saving goes through `CalendarEdit.set`, so later blocks are pushed down as with a drag.
struct BlockEditor: View {
    let task: PlanTask
    let state: PopoverState
    let now: Date

    @State private var start: Date
    @State private var end: Date
    @State private var length: String
    @FocusState private var lengthFocused: Bool

    init(task: PlanTask, block: ScheduledBlock, state: PopoverState, now: Date) {
        self.task = task
        self.state = state
        self.now = now
        _start = State(initialValue: block.start)
        _end = State(initialValue: block.end)
        _length = State(initialValue: Self.text(minutes: Self.minutes(from: block.start, to: block.end)))
    }

    private var minutes: Int {
        Self.minutes(from: start, to: end)
    }

    private var lengthIsValid: Bool {
        QuickAddParser.minutes(length) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(task.title).font(.headline).lineLimit(1)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("Length").foregroundStyle(.secondary)
                    TextField("45m", text: $length)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .focused($lengthFocused)
                        .onSubmit(save)
                    if !lengthIsValid {
                        Text("1m to 12h").font(.caption).foregroundStyle(.red)
                    }
                }
                GridRow {
                    Text("From").foregroundStyle(.secondary)
                    DatePicker("From", selection: $start, displayedComponents: .hourAndMinute).labelsHidden()
                }
                GridRow {
                    Text("To").foregroundStyle(.secondary)
                    DatePicker("To", selection: $end, displayedComponents: .hourAndMinute).labelsHidden()
                }
            }
            .datePickerStyle(.field)
            if task.status == .paused {
                Text("Paused: it keeps at least a minute more than it has brewed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { state.editingTaskID = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!lengthIsValid)
            }
        }
        .onAppear { lengthFocused = true }
        .onChange(of: start) { old, new in
            // Same length from the new start.
            end = new + end.timeIntervalSince(old)
        }
        .onChange(of: end) { _, new in
            // An end at or before the start means the next day.
            let fixed = Self.after(start, new)
            if fixed != new {
                end = fixed
            } else if QuickAddParser.minutes(length) != minutes {
                length = Self.text(minutes: minutes)
            }
        }
        .onChange(of: length) { _, new in
            if let typed = QuickAddParser.minutes(new), typed != minutes {
                end = start + TimeInterval(typed * 60)
            }
        }
    }

    private func save() {
        guard lengthIsValid else { return }
        state.setTimes(task.id, start: start, minutes: minutes, now: now)
        state.editingTaskID = nil
    }

    private static func minutes(from start: Date, to end: Date) -> Int {
        Int((end.timeIntervalSince(start) / 60).rounded())
    }

    /// `45m` or `1h 30m`.
    private static func text(minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    /// `end` moved by whole days so it's after `start` and less than a day later.
    private static func after(_ start: Date, _ end: Date) -> Date {
        var end = end
        while end <= start {
            end += 86400
        }
        while end.timeIntervalSince(start) > 86400 {
            end -= 86400
        }
        return end
    }
}
