import KettleCore
import SwiftUI

/// One block: label colour, title, derived times, duration stepper, and the live countdown
/// when it's the active task.
struct TaskRow: View {
    let task: PlanTask
    let label: KettleCore.Label?
    let block: ScheduledBlock?
    let isActive: Bool
    let state: PopoverState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(label.map { Color(hex: $0.colorHex) } ?? Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .strikethrough(task.status == .skipped)
                    .foregroundStyle(task.isFinished ? .secondary : .primary)
                    .lineLimit(1)
                Text(details).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            if isActive {
                countdown
            }
            Text("\(task.totalMinutes)m")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Stepper("Duration", onIncrement: {
                state.adjust(task.id, by: state.settings.resizeStepMinutes)
            }, onDecrement: {
                state.adjust(task.id, by: -state.settings.resizeStepMinutes)
            })
            .labelsHidden()
            .accessibilityLabel("Duration of \(task.title), \(task.totalMinutes) minutes")
            .disabled(task.isFinished)
        }
        .padding(.vertical, 2)
        .listRowBackground(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
        .contextMenu { menu }
    }

    /// "09:00–09:45 · work", plus the status for finished and paused tasks.
    private var details: String {
        var parts: [String] = []
        if let block {
            let start = block.start.formatted(date: .omitted, time: .shortened)
            let end = block.end.formatted(date: .omitted, time: .shortened)
            parts.append("\(start)–\(end)")
        }
        if let label {
            parts.append(label.name)
        }
        switch task.status {
        case .brewing: parts.append("Brewing")
        case .paused: parts.append("Paused")
        case .done: parts.append("Done")
        case .skipped: parts.append("Skipped")
        case .pending: break
        }
        return parts.joined(separator: " · ")
    }

    /// Ticks once a second, but only while the popover is open and only in this row.
    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = task.remainingSeconds(at: context.date)
            Text(CountdownFormatter.string(remaining: remaining, precision: .seconds))
                .monospacedDigit()
                .fontWeight(.medium)
                .accessibilityLabel(StatusDescription.spoken(remaining: remaining))
        }
    }

    @ViewBuilder
    private var menu: some View {
        if state.isTimerDay, !task.isFinished, !isActive {
            Button("Start") { state.start(task.id) }
        }
        if !task.isFinished {
            Button("Skip") { state.skip(task.id) }
        }
        Button("Delete", role: .destructive) { state.remove(task.id) }
    }
}

extension Color {
    /// `#RRGGBB`; anything else falls back to grey.
    init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self = .gray
            return
        }
        self.init(
            .sRGB,
            red: Double(value >> 16 & 0xFF) / 255,
            green: Double(value >> 8 & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
