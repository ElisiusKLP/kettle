import KettleCore
import SwiftUI

/// The day as a compact calendar, like Calendar's day view: time marks down the left, each block
/// at its derived time, and a line at the current time. Pending blocks can be dragged to a new
/// time, which pins them there (`PlanEngine.pin`). Dragging a block's bottom edge changes its
/// duration, and a pending block's top edge its start. While dragging, the whole day is laid
/// out as if dropped there, so the other blocks make room instead of being covered.
struct CalendarDayView: View {
    let state: PopoverState
    let now: Date

    /// Drops snap to this many minutes.
    static let snapMinutes = 5
    static let gutterWidth: CGFloat = 46
    static let minimumBlockHeight: CGFloat = 16
    /// Room above midnight's mark so its label isn't cut off.
    static let topInset: CGFloat = 8
    /// Blocks running past midnight extend the calendar, up to noon the next day.
    static let maximumMinutes = 36 * 60

    /// Height of the strip at the top and bottom of a block that resizes it.
    static let edgeHeight: CGFloat = 5

    /// A drag in progress.
    private struct Drag {
        let taskID: UUID
        let kind: DragKind
        let translation: CGFloat
    }

    @State private var drag: Drag?

    private var interval: Int {
        state.settings.calendarIntervalMinutes
    }

    /// Vertical scale: finer time marks get more room, so the calendar stays readable.
    private var pointsPerMinute: CGFloat {
        switch interval {
        case 15: 1.6
        case 30: 1.0
        default: 0.75
        }
    }

    private var dayStart: Date {
        state.date.date(in: state.calendar)
    }

    var body: some View {
        let (plan, blocks) = preview(state.calendarBlocks(now: now))
        let tasks = Dictionary(uniqueKeysWithValues: plan.tasks.map { ($0.id, $0) })
        let length = dayLength(blocks)
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    marks(length)
                    ForEach(blocks, id: \.taskID) { block in
                        if let task = tasks[block.taskID] {
                            blockView(task, block)
                        }
                    }
                    if state.date == state.today {
                        nowLine
                    }
                }
                .frame(height: y(minutes: length) + Self.topInset, alignment: .top)
                .padding(.trailing, 8)
            }
            .onAppear {
                // Scroll so the hour before now (or before the first block) is at the top.
                let first = state.date == state.today ? now : (blocks.first?.start ?? dayStart + 8 * 3600)
                let mark = max(0, minutes(first) - 60) / interval
                DispatchQueue.main.async { proxy.scrollTo(mark, anchor: .top) }
            }
        }
        .overlay(alignment: .top) {
            if state.plan.tasks.isEmpty {
                hint("Nothing on the stove. Add your first task.")
            } else if PlanEngine.isComplete(state.plan) {
                hint(state.date == state.today ? "All brewed for today." : "All brewed.")
            }
        }
    }

    // MARK: Time marks

    /// Minutes shown: the whole day, plus however long the last block runs past midnight
    /// (up to 12 hours), to the next mark.
    private func dayLength(_ blocks: [ScheduledBlock]) -> Int {
        let last = blocks.map { Int($0.end.timeIntervalSince(dayStart) / 60) }.max() ?? 0
        let length = min(max(last, 24 * 60), Self.maximumMinutes)
        return (length + interval - 1) / interval * interval
    }

    private func marks(_ length: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(0 ..< length / interval, id: \.self) { index in
                let minute = index * interval
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(minute % 60 == 0 ? 0.25 : 0.12))
                        .frame(height: 1)
                        .padding(.leading, Self.gutterWidth)
                    Text(markLabel(minute))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(minute % 60 == 0 ? .secondary : .tertiary)
                        .frame(width: Self.gutterWidth - 6, alignment: .trailing)
                        .offset(y: -6)
                }
                .frame(height: CGFloat(interval) * pointsPerMinute, alignment: .top)
                .id(index)
            }
        }
        .padding(.top, Self.topInset)
        .accessibilityHidden(true)
    }

    /// "9 AM" or "09" on the hour (following the user's locale), ":30" in between.
    private func markLabel(_ minute: Int) -> String {
        guard minute % 60 == 0 else { return String(format: ":%02d", minute % 60) }
        return (dayStart + TimeInterval(minute * 60)).formatted(.dateTime.hour())
    }

    private var nowLine: some View {
        HStack(spacing: 0) {
            Circle().fill(.red).frame(width: 6, height: 6)
            Rectangle().fill(.red).frame(height: 1)
        }
        .padding(.leading, Self.gutterWidth - 3)
        .offset(y: y(minutes: minutes(now)) - 3)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Blocks

    private func blockView(_ task: PlanTask, _ block: ScheduledBlock) -> some View {
        let top = y(minutes: minutes(block.start))
        let bottom = y(minutes: minutes(block.end))
        let height = max(Self.minimumBlockHeight, bottom - top)
        let dragged = drag?.taskID == task.id ? drag?.kind : nil
        return CalendarBlock(
            task: task,
            label: state.label(for: task),
            block: block,
            isActive: task.id == state.activeTaskID,
            isDragged: dragged != nil,
            showsDetails: height >= 30,
            corner: cornerText(task, block, dragged: dragged),
            state: state
        )
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .overlay(alignment: .top) {
            if task.status == .pending {
                edge(task, .top, height: height)
            }
        }
        .overlay(alignment: .bottom) {
            if !task.isFinished {
                edge(task, .bottom, height: height)
            }
        }
        .padding(.leading, Self.gutterWidth + 2)
        .offset(y: top)
        .zIndex(dragged != nil ? 1 : 0)
        .gesture(dragGesture(task.id, .move), including: task.status == .pending ? .all : .subviews)
    }

    /// The strip along a block's top or bottom edge that resizes it, with the resize cursor.
    private func edge(_ task: PlanTask, _ kind: DragKind, height: CGFloat) -> some View {
        Color.clear
            .frame(height: min(Self.edgeHeight, height / 4))
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(dragGesture(task.id, kind))
    }

    private func dragGesture(_ taskID: UUID, _ kind: DragKind) -> some Gesture {
        // Global coordinates: the block moves with the drag, so its own would shift under it.
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                drag = Drag(taskID: taskID, kind: kind, translation: value.translation.height)
            }
            .onEnded { value in
                let finished = Drag(taskID: taskID, kind: kind, translation: value.translation.height)
                drag = nil
                if let change = change(for: finished, blocks: state.calendarBlocks(now: now)) {
                    state.rearrange(change)
                }
            }
    }

    /// The shown plan and its blocks, or while dragging, both as they'd be after the drop.
    private func preview(_ blocks: [ScheduledBlock]) -> (DayPlan, [ScheduledBlock]) {
        guard let drag, let change = change(for: drag, blocks: blocks) else { return (state.plan, blocks) }
        var plan = state.plan
        change(&plan)
        return (plan, state.calendarBlocks(for: plan, now: now))
    }

    /// The plan edit a drag makes, worked out against the blocks as they were before it.
    private func change(for drag: Drag, blocks: [ScheduledBlock]) -> ((inout DayPlan) -> Void)? {
        guard let block = blocks.first(where: { $0.taskID == drag.taskID }) else { return nil }
        let moved = Double(drag.translation / pointsPerMinute)
        let calendar = state.calendar
        let taskID = drag.taskID
        switch drag.kind {
        case .move:
            let time = localTime(snapped(offset(block.start) + moved))
            return { PlanEngine.pin(taskID: taskID, at: time, in: &$0, schedule: blocks, calendar: calendar) }
        case .top:
            // At least one snap step before the end.
            let latest = Int(offset(block.end)) - Self.snapMinutes
            let time = localTime(min(snapped(offset(block.start) + moved), latest))
            return { PlanEngine.resize(taskID: taskID, start: time, in: &$0, schedule: blocks, calendar: calendar) }
        case .bottom:
            let end = dayStart + TimeInterval(snapped(offset(block.end) + moved) * 60)
            let now = state.date == state.today ? now : nil
            return { PlanEngine.resize(taskID: taskID, end: end, in: &$0, schedule: blocks, now: now) }
        }
    }

    /// The right corner: while dragging, the new start (or the new length for the bottom edge);
    /// otherwise the countdown for the active task and the length for every other one.
    private func cornerText(_ task: PlanTask, _ block: ScheduledBlock, dragged: DragKind?) -> CalendarBlock.Corner {
        switch dragged {
        case .move, .top:
            .text(block.start.formatted(date: .omitted, time: .shortened), emphasised: true)
        case .bottom:
            .text(DurationText.short(seconds: Int(block.end.timeIntervalSince(block.start))), emphasised: true)
        case nil where task.id == state.activeTaskID:
            .countdown
        case nil:
            .text(DurationText.short(seconds: lengthSeconds(task, block)), emphasised: false)
        }
    }

    /// Done tasks show the time actually brewed; others their planned length with extensions.
    private func lengthSeconds(_ task: PlanTask, _ block: ScheduledBlock) -> Int {
        switch task.status {
        case .done, .skipped: Int(block.end.timeIntervalSince(block.start))
        default: task.totalMinutes * 60
        }
    }

    /// Minutes since the start of the shown day, rounded to the snap step.
    private func snapped(_ minutes: Double) -> Int {
        Int((minutes / Double(Self.snapMinutes)).rounded()) * Self.snapMinutes
    }

    /// A time on the shown day (fixed starts can't run past midnight).
    private func localTime(_ minutes: Int) -> LocalTime {
        let clamped = min(max(minutes, 0), 24 * 60 - Self.snapMinutes)
        return LocalTime(hour: clamped / 60, minute: clamped % 60) ?? .midnight
    }

    // MARK: Geometry

    /// Minutes from the start of the shown day.
    private func offset(_ date: Date) -> Double {
        date.timeIntervalSince(dayStart) / 60
    }

    /// Minutes from the start of the shown day, kept within what the calendar shows.
    private func minutes(_ date: Date) -> Int {
        min(max(Int(date.timeIntervalSince(dayStart) / 60), 0), Self.maximumMinutes)
    }

    private func y(minutes: Int) -> CGFloat {
        Self.topInset + CGFloat(minutes) * pointsPerMinute
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 8)
    }
}

/// What a calendar drag moves: the whole block, or one of its edges.
private enum DragKind {
    case move, top, bottom
}

/// One block in the calendar: label colour, title, times when there's room, and the countdown or
/// length in the right corner.
private struct CalendarBlock: View {
    enum Corner {
        case countdown
        case text(String, emphasised: Bool)
    }

    let task: PlanTask
    let label: KettleCore.Label?
    let block: ScheduledBlock
    let isActive: Bool
    let isDragged: Bool
    /// Room for a second line with the times.
    let showsDetails: Bool
    let corner: Corner
    let state: PopoverState

    private var color: Color {
        label.map { Color(hex: $0.colorHex) } ?? .secondary
    }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 3) {
                    if task.status == .done {
                        Image(systemName: "checkmark").font(.caption2.bold())
                    }
                    Text(task.title)
                        .font(.caption.weight(.medium))
                        .strikethrough(task.status == .skipped)
                        .lineLimit(1)
                }
                if showsDetails {
                    Text(details).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            switch corner {
            case .countdown:
                Countdown(task: task).font(.caption.monospacedDigit().weight(.medium))
            case let .text(text, emphasised):
                Text(text)
                    .font(.caption.monospacedDigit().weight(emphasised ? .bold : .regular))
                    .foregroundStyle(emphasised ? .primary : .secondary)
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, 4)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(task.isFinished ? .secondary : .primary)
        .background(alignment: .leading) {
            ZStack(alignment: .leading) {
                // Opaque underneath, so the time marks don't show through the tint.
                RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .windowBackgroundColor))
                RoundedRectangle(cornerRadius: 4).fill(color.opacity(isActive ? 0.35 : 0.2))
                RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3)
            }
            .opacity(task.isFinished ? 0.55 : 1)
        }
        .overlay {
            if isActive {
                RoundedRectangle(cornerRadius: 4).strokeBorder(color, lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(isDragged ? 0.25 : 0), radius: 3, y: 1)
        .contentShape(Rectangle())
        .contextMenu { TaskMenu(task: task, state: state) }
        .help(help)
    }

    private var help: String {
        switch task.status {
        case .pending: "Drag to move. Drag the top or bottom edge to change the time."
        case .brewing, .paused: "Drag the bottom edge to change the length."
        case .done, .skipped: ""
        }
    }

    /// "09:00–09:45 · work · Paused"
    private var details: String {
        let start = block.start.formatted(date: .omitted, time: .shortened)
        let end = block.end.formatted(date: .omitted, time: .shortened)
        var parts = ["\(start)–\(end)"]
        if let label {
            parts.append(label.name)
        }
        if task.status == .paused {
            parts.append("Paused")
        }
        return parts.joined(separator: " · ")
    }
}
