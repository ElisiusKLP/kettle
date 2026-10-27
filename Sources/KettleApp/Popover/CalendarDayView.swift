import KettleCore
import SwiftUI

/// The day as a compact calendar, like Calendar's day view: time marks down the left, each block
/// at its derived time, and a line at the current time. Pending blocks can be dragged to a new
/// time, which pins them there (`CalendarEdit`). Dragging a block's bottom edge changes its
/// duration, and a pending block's top edge its start. While dragging, the whole day is laid
/// out as if dropped there, so the other blocks make room instead of being covered. Hovering
/// shows − and + for the length, and a double-click opens the block editor. A brewing block is
/// locked; only Keep brewing extends it.
///
/// Blocks never overlap on screen: a short block is drawn at `minimumBlockHeight`, and the
/// blocks after it move down as far as needed to stay below it.
struct CalendarDayView: View {
    let state: PopoverState
    let now: Date

    /// Drops snap to this many minutes.
    static let snapMinutes = 5
    static let gutterWidth: CGFloat = 46
    static let minimumBlockHeight: CGFloat = 18
    /// Space between blocks that touch.
    static let blockGap: CGFloat = 1
    /// Blocks shorter than this on screen have no resize edges, so they're easy to move.
    static let minimumResizableHeight: CGFloat = 26
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

    /// Resets itself when a drag ends or is interrupted, so a preview can't get stuck.
    @GestureState private var drag: Drag?
    @State private var hovered: UUID?

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
        let frames = layout(blocks)
        let length = dayLength(blocks)
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    marks(length)
                    // In the shown plan's order, which doesn't change during a drag, so the
                    // dragged block keeps its identity (and its gesture).
                    ForEach(state.plan.tasks) { original in
                        if let task = tasks[original.id], let block = blocks.first(where: { $0.taskID == original.id }),
                           let frame = frames[original.id]
                        {
                            blockView(task, block, frame: frame)
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

    // MARK: Blocks

    /// Where each block is drawn: at its time, unless the block before it (drawn taller than
    /// its time, because it's short) is in the way.
    private func layout(_ blocks: [ScheduledBlock]) -> [UUID: (top: CGFloat, height: CGFloat)] {
        var frames: [UUID: (top: CGFloat, height: CGFloat)] = [:]
        var floor = -CGFloat.infinity
        for block in blocks {
            let top = max(y(minutes: minutes(block.start)), floor)
            let height = max(Self.minimumBlockHeight, y(minutes: minutes(block.end)) - y(minutes: minutes(block.start)))
            frames[block.taskID] = (top, height)
            floor = top + height + Self.blockGap
        }
        return frames
    }

    private func blockView(
        _ task: PlanTask,
        _ block: ScheduledBlock,
        frame: (top: CGFloat, height: CGFloat)
    ) -> some View {
        let top = frame.top
        let height = frame.height
        let resizable = height >= Self.minimumResizableHeight
        let dragged = drag?.taskID == task.id ? drag?.kind : nil
        let editable = CalendarEdit.canMove(task)
        let step = state.settings.resizeStepMinutes
        return CalendarBlock(
            task: task,
            label: state.label(for: task),
            block: block,
            isActive: task.id == state.activeTaskID,
            isDragged: dragged != nil,
            showsDetails: height >= 30,
            showsLengthButtons: editable && hovered == task.id && drag == nil,
            corner: cornerText(task, block, dragged: dragged),
            state: state,
            nudge: { direction in state.nudge(task.id, by: direction * step, now: now) }
        )
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .overlay(alignment: .top) {
            if resizable, task.status == .pending {
                edge(task, .top)
            }
        }
        .overlay(alignment: .bottom) {
            if resizable, CalendarEdit.canResize(task) {
                edge(task, .bottom)
            }
        }
        .padding(.leading, Self.gutterWidth + 2)
        .offset(y: top)
        .zIndex(dragged != nil ? 1 : 0)
        .onHover { inside in
            if inside {
                hovered = task.id
            } else if hovered == task.id {
                hovered = nil
            }
        }
        .gesture(dragGesture(task.id, .move), including: editable ? .all : .subviews)
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if editable {
                state.editingTaskID = task.id
            }
        })
    }

    /// The strip along a block's top or bottom edge that resizes it, with the resize cursor.
    private func edge(_ task: PlanTask, _ kind: DragKind) -> some View {
        Color.clear
            .frame(height: Self.edgeHeight)
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
            .updating($drag) { value, drag, _ in
                drag = Drag(taskID: taskID, kind: kind, translation: value.translation.height)
            }
            .onEnded { value in
                let finished = Drag(taskID: taskID, kind: kind, translation: value.translation.height)
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

    /// The plan edit a drag makes, worked out against the blocks as they were before it. A
    /// drag moves the start or end by as many minutes as it moved on screen, snapped.
    private func change(for drag: Drag, blocks: [ScheduledBlock]) -> ((inout DayPlan) -> Void)? {
        guard let block = blocks.first(where: { $0.taskID == drag.taskID }) else { return nil }
        let moved = Double(drag.translation / pointsPerMinute)
        let edit = CalendarEdit(schedule: blocks, now: state.date == state.today ? now : nil)
        let taskID = drag.taskID
        switch drag.kind {
        case .move:
            let start = snapped(block.start, by: moved)
            return { edit.move(taskID, to: start, in: &$0) }
        case .top:
            let start = snapped(block.start, by: moved)
            return { edit.resize(taskID, start: start, in: &$0) }
        case .bottom:
            let end = snapped(block.end, by: moved)
            return { edit.resize(taskID, end: end, in: &$0) }
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

    /// `date` moved by `minutes`, on the snap grid, kept within what the calendar shows.
    private func snapped(_ date: Date, by minutes: Double) -> Date {
        let raw = offset(date) + minutes
        let snapped = Int((raw / Double(Self.snapMinutes)).rounded()) * Self.snapMinutes
        let clamped = min(max(snapped, 0), Self.maximumMinutes - Self.snapMinutes)
        return dayStart + TimeInterval(clamped * 60)
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

// MARK: - Time marks

extension CalendarDayView {
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
}

/// What a calendar drag moves: the whole block, or one of its edges.
private enum DragKind {
    case move, top, bottom
}
