import KettleCore
import SwiftUI

/// One block in the calendar: label colour, title, times when there's room, and the countdown or
/// length in the right corner.
struct CalendarBlock: View {
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
