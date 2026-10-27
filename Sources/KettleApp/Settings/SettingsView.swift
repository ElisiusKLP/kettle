import KettleCore
import SwiftUI

struct SettingsView: View {
    @Bindable var state: SettingsState

    var body: some View {
        TabView {
            GeneralSettings(state: state).tabItem { SwiftUI.Label("General", systemImage: "gearshape") }
            LabelSettings(state: state).tabItem { SwiftUI.Label("Labels", systemImage: "tag") }
            DataSettings(state: state).tabItem { SwiftUI.Label("Data", systemImage: "externaldrive") }
        }
        .padding(16)
        .frame(width: 480, height: 400)
    }
}

private struct GeneralSettings: View {
    @Bindable var state: SettingsState

    var body: some View {
        Form {
            Stepper(
                "Keep brewing adds \(state.settings.extendMinutes) min",
                value: $state.settings.extendMinutes,
                in: 1 ... 120
            )
            Stepper(
                "Second option adds \(state.settings.secondaryExtendMinutes) min",
                value: $state.settings.secondaryExtendMinutes,
                in: 1 ... 120
            )
            Toggle("Start the next task automatically after Done", isOn: $state.settings.autoStartNext)
            Picker("Menubar shows", selection: $state.settings.menubarFormat) {
                Text("Kettle only").tag(MenubarFormat.iconOnly)
                Text("Kettle and time").tag(MenubarFormat.iconAndTime)
                Text("Kettle, task and time").tag(MenubarFormat.iconTitleAndTime)
            }
            Picker("Countdown", selection: $state.settings.timerPrecision) {
                Text("Minutes, seconds in the last minute").tag(TimerPrecision.smart)
                Text("Seconds (uses a little more energy)").tag(TimerPrecision.seconds)
                Text("Minutes").tag(TimerPrecision.minutes)
            }
            Toggle("Whistle sound", isOn: $state.settings.whistleSound)
            Toggle("Notify when time's up", isOn: $state.settings.notifyOnFinish)
            Picker("Weeks start on", selection: $state.settings.weekStartsOn) {
                ForEach(Weekday.allCases, id: \.self) { day in
                    Text(day.rawValue.capitalized).tag(day)
                }
            }
            Toggle("Open Kettle at login", isOn: $state.settings.launchAtLogin)
            if let message = state.launchAtLoginMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct LabelSettings: View {
    let state: SettingsState

    var body: some View {
        VStack(alignment: .leading) {
            List(state.sortedLabels) { label in
                LabelRow(label: label, state: state)
            }
            HStack {
                Button("Add Label") { state.addLabel() }
                Spacer()
                Text("Archived labels are hidden when planning but keep their stats.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct LabelRow: View {
    let label: KettleCore.Label
    let state: SettingsState
    @State private var name = ""

    var body: some View {
        HStack {
            ColorPicker("Colour", selection: Binding(
                get: { Color(hex: label.colorHex) },
                set: { color in
                    var changed = label
                    changed.colorHex = color.hexString
                    state.update(changed)
                }
            ), supportsOpacity: false)
                .labelsHidden()
            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .foregroundStyle(label.isArchived ? .secondary : .primary)
                .onSubmit(rename)
                .onAppear { name = label.name }
                .onChange(of: label.name) { name = label.name }
            Spacer()
            Toggle("Archived", isOn: Binding(
                get: { label.isArchived },
                set: { archived in
                    var changed = label
                    changed.isArchived = archived
                    state.update(changed)
                }
            ))
            .toggleStyle(.checkbox)
        }
    }

    private func rename() {
        var changed = label
        changed.name = name
        state.update(changed)
    }
}

private struct DataSettings: View {
    let state: SettingsState

    var body: some View {
        Form {
            Section("Data folder") {
                Text(state.dataFolder.path)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(3)
                Button("Reveal in Finder") { state.revealDataFolder() }
            }
            Section("Export and import") {
                HStack {
                    Button("Export JSON…") { state.export(csv: false) }
                    Button("Export CSV…") { state.export(csv: true) }
                    Button("Import JSON…") { state.importJSON() }
                }
            }
            Section {
                Button("Delete All Data…", role: .destructive) { state.deleteAllData() }
            }
            if let message = state.dataMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

extension Color {
    /// `#RRGGBB` in sRGB.
    var hexString: String {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return "#808080" }
        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
