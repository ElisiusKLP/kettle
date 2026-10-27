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
    /// Blocks shorter than this on screen have no top resize zone, so they stay easy to move.
    static let minimumTopEdgeHeight: CGFloat = 30
    /// Room above midnight's mark so its label isn't cut off.
    static let topInset: CGFloat = 8
    /// Blocks running past midnight extend the calendar, up to noon the next day.
    static let maximumMinutes = 36 * 60

    /// Resize zones are this share of a block's height, within `edgeHeights`.
    static let edgeShare: CGFloat = 0.25
    static let edgeHeights: ClosedRange<CGFloat> = 6 ... 12
    /// The calendar's own coordinate space. Drags are measured in it: it doesn't move while a
    /// block does, and block frames are known in it.
    static let space = "calendar"
    /// A press that moves less than this is a click (or double-click), not a drag.
    static let clickDistance: CGFloat = 3

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
                .coordinateSpace(.named(Self.space))
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
        let edges = edgeZones(task, height: height)
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
            handles: hovered == task.id && drag == nil ? (edges.top > 0, edges.bottom > 0) : (false, false),
            corner: cornerText(task, block, dragged: dragged),
            state: state,
            nudge: { direction in state.nudge(task.id, by: direction * step, now: now) }
        )
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .padding(.leading, Self.gutterWidth + 2)
        .offset(y: top)
        .zIndex(dragged != nil ? 1 : 0)
        .onContinuousHover(coordinateSpace: .named(Self.space)) { phase in
            switch phase {
            case let .active(location):
                hovered = task.id
                // On every move, from the same test the gesture uses, so the cursor always
                // shows what a press there would do. AppKit resets cursors freely, so setting
                // it once on entering a zone isn't enough.
                guard drag == nil else { return }
                Self.cursor(for: dragKind(task, at: location.y)).set()
            case .ended:
                if hovered == task.id {
                    hovered = nil
                }
                if drag == nil {
                    NSCursor.arrow.set()
                }
            }
        }
        .gesture(blockGesture(task))
    }

    /// The resize zones' heights for a block drawn `height` tall (0: none). The bottom zone is a
    /// quarter of the block, 6–12 pt, leaving the rest for moving. The top zone (pending blocks
    /// only) needs a taller block, so short ones stay easy to move.
    private func edgeZones(_ task: PlanTask, height: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        let zone = min(max(height * Self.edgeShare, Self.edgeHeights.lowerBound), Self.edgeHeights.upperBound)
        let top = task.status == .pending && height >= Self.minimumTopEdgeHeight ? zone : 0
        let bottom = CalendarEdit.canResize(task) ? zone : 0
        return (top, bottom)
    }

    /// The up-down arrows over a resize zone, the arrow anywhere else.
    private static func cursor(for kind: DragKind?) -> NSCursor {
        switch kind {
        case .top, .bottom: .resizeUpDown
        case .move, nil: .arrow
        }
    }

    /// One gesture per block, so moving and resizing can never both happen. Where the press
    /// starts decides the kind: the top or bottom strip resizes, anywhere else moves. A press
    /// that barely moves is a click, and a double-click opens the block editor.
    private func blockGesture(_ task: PlanTask) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .updating($drag) { value, drag, _ in
                guard drag != nil || abs(value.translation.height) >= Self.clickDistance,
                      let kind = dragKind(task, at: value.startLocation.y)
                else { return }
                drag = Drag(taskID: task.id, kind: kind, translation: value.translation.height)
                // Keep the arrows while resizing, even once the pointer leaves the zone.
                Self.cursor(for: kind).set()
            }
            .onEnded { value in
                guard abs(value.translation.height) >= Self.clickDistance else {
                    if (NSApp.currentEvent?.clickCount ?? 0) >= 2, CalendarEdit.canMove(task) {
                        state.editingTaskID = task.id
                    }
                    return
                }
                let blocks = state.calendarBlocks(now: now)
                guard let kind = dragKind(task, at: value.startLocation.y),
                      let change = change(
                          for: Drag(taskID: task.id, kind: kind, translation: value.translation.height),
                          blocks: blocks
                      )
                else { return }
                state.rearrange(change)
            }
    }

    /// What a press at `y` (in the calendar's space) on the task's block does, judged against
    /// the layout before any drag; nil for a locked block.
    private func dragKind(_ task: PlanTask, at y: CGFloat) -> DragKind? {
        guard CalendarEdit.canMove(task), let frame = layout(state.calendarBlocks(now: now))[task.id] else {
            return nil
        }
        let edges = edgeZones(task, height: frame.height)
        if y < frame.top + edges.top {
            return .top
        }
        if y > frame.top + frame.height - edges.bottom {
            return .bottom
        }
        return .move
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
