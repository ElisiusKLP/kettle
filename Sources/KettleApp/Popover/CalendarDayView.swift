import KettleCore
import SwiftUI

/// The day as a compact calendar, like Calendar's day view: time marks down the left, each block
/// at its derived time, and a line at the current time. Pending blocks can be dragged to a new
/// time, which pins them there (`PlanEngine.pin`).
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

    @State private var drag: (taskID: UUID, offset: CGFloat)?
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
        let blocks = state.calendarBlocks(now: now)
        let tasks = Dictionary(uniqueKeysWithValues: state.plan.tasks.map { ($0.id, $0) })
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
        let dragOffset = drag?.taskID == task.id ? drag?.offset ?? 0 : 0
        return CalendarBlock(
            task: task,
            label: state.label(for: task),
            block: block,
            isActive: task.id == state.activeTaskID,
            isHovered: hovered == task.id,
            showsDetails: height >= 30,
            dropTime: drag?.taskID == task.id ? timeText(dropTime(block, offset: dragOffset)) : nil,
            state: state
        )
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .padding(.leading, Self.gutterWidth + 2)
        .offset(y: top + dragOffset)
        .zIndex(drag?.taskID == task.id ? 1 : 0)
        .onHover { inside in
            if inside {
                hovered = task.id
            } else if hovered == task.id {
                hovered = nil
            }
        }
        .gesture(dragGesture(task, block), including: task.status == .pending ? .all : .subviews)
    }

    private func dragGesture(_ task: PlanTask, _ block: ScheduledBlock) -> some Gesture {
        // Global coordinates: the block moves with the drag, so its own would shift under it.
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                drag = (task.id, value.translation.height)
            }
            .onEnded { value in
                drag = nil
                state.pin(task.id, at: dropTime(block, offset: value.translation.height), now: now)
            }
    }

    /// Where a block dragged by `offset` points lands, snapped and kept within the day (a fixed
    /// start is a time on the plan's own day).
    private func dropTime(_ block: ScheduledBlock, offset: CGFloat) -> LocalTime {
        let raw = Double(minutes(block.start)) + Double(offset / pointsPerMinute)
        let snapped = Int((raw / Double(Self.snapMinutes)).rounded()) * Self.snapMinutes
        let clamped = min(max(snapped, 0), 24 * 60 - Self.snapMinutes)
        return LocalTime(hour: clamped / 60, minute: clamped % 60) ?? .midnight
    }

    private func timeText(_ time: LocalTime) -> String {
        state.date.date(at: time, in: state.calendar).formatted(date: .omitted, time: .shortened)
    }

    // MARK: Geometry

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

/// One block in the calendar: label colour, title, times when there's room, the countdown while
/// active, and duration buttons on hover.
private struct CalendarBlock: View {
    let task: PlanTask
    let label: KettleCore.Label?
    let block: ScheduledBlock
    let isActive: Bool
    let isHovered: Bool
    /// Room for a second line with the times.
    let showsDetails: Bool
    /// While dragging: where it would land.
    let dropTime: String?
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
            if let dropTime {
                Text(dropTime).font(.caption2.monospacedDigit().bold())
            } else if isActive {
                Countdown(task: task).font(.caption.monospacedDigit())
            }
            if isHovered, dropTime == nil, !task.isFinished {
                durationButtons
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
        .contentShape(Rectangle())
        .contextMenu { TaskMenu(task: task, state: state) }
        .help(task.status == .pending ? "Drag to another time" : "")
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

    private var durationButtons: some View {
        HStack(spacing: 2) {
            Button { state.adjust(task.id, by: -state.settings.resizeStepMinutes) } label: {
                Image(systemName: "minus.circle")
            }
            .accessibilityLabel("Shorten \(task.title)")
            Button { state.adjust(task.id, by: state.settings.resizeStepMinutes) } label: {
                Image(systemName: "plus.circle")
            }
            .accessibilityLabel("Lengthen \(task.title)")
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .help("Change the duration by \(state.settings.resizeStepMinutes) minutes")
    }
}
