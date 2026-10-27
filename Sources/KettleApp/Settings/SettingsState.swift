import AppKit
import KettleCore
import Observation
import UniformTypeIdentifiers

/// What the Settings window edits. Created with the window and dropped when it closes.
@Observable
final class SettingsState {
    var settings: AppSettings {
        didSet { save() }
    }

    private(set) var labels: [KettleCore.Label] = []
    /// One-line result of the last Data action, e.g. "Imported 120 sessions."
    var dataMessage: String?
    var launchAtLoginMessage: String?

    let dataFolder: URL

    @ObservationIgnored private let model: KettleModel
    @ObservationIgnored private let onChange: () -> Void

    init(model: KettleModel, dataFolder: URL, onChange: @escaping () -> Void) {
        self.model = model
        self.dataFolder = dataFolder
        self.onChange = onChange
        settings = model.settings
        labels = model.labels
    }

    // MARK: General

    private func save() {
        guard settings != model.settings else { return }
        if settings.launchAtLogin != model.settings.launchAtLogin {
            launchAtLoginMessage = LaunchAtLogin.set(settings.launchAtLogin)
        }
        model.updateSettings(settings)
        onChange()
    }

    // MARK: Labels

    /// Active labels first, then archived ones, each alphabetically.
    var sortedLabels: [KettleCore.Label] {
        labels.sorted { ($0.isArchived ? 1 : 0, $0.name.lowercased()) < ($1.isArchived ? 1 : 0, $1.name.lowercased()) }
    }

    func update(_ label: KettleCore.Label) {
        guard let index = labels.firstIndex(where: { $0.id == label.id }) else { return }
        var label = label
        label.name = label.name.trimmingCharacters(in: .whitespaces)
        guard !label.name.isEmpty else { return }
        labels[index] = label
        model.updateLabels(labels)
        onChange()
    }

    func addLabel() {
        var name = "new label"
        var number = 2
        while labels.contains(where: { $0.name == name }) {
            name = "new label \(number)"
            number += 1
        }
        labels.append(KettleCore.Label(name: name, colorHex: KettleCore.Label.nextColor(after: labels)))
        model.updateLabels(labels)
        onChange()
    }

    // MARK: Data

    func revealDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([dataFolder])
    }

    func export(csv: Bool) {
        let panel = NSSavePanel()
        let day = LocalDate(Date(), in: .autoupdatingCurrent)
        panel.nameFieldStringValue = "Kettle \(day).\(csv ? "csv" : "json")"
        panel.allowedContentTypes = [csv ? .commaSeparatedText : .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try (csv ? model.exportCSV() : model.exportJSON()).write(to: url, options: .atomic)
            dataMessage = "Exported to \(url.lastPathComponent)."
        } catch {
            dataMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let alert = NSAlert()
        alert.messageText = "Import \(url.lastPathComponent)?"
        alert.informativeText = """
        The file is merged into your data: nothing is deleted, but days in the file replace \
        those days' plans, and its settings replace yours.
        """
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let summary = try model.importJSON(Data(contentsOf: url))
            dataMessage = "Imported \(summary.plans) days, \(summary.labels) labels "
                + "and \(summary.newSessions) new sessions."
            reload()
        } catch {
            dataMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    func deleteAllData() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Delete all Kettle data?"
        alert.informativeText = "Plans, labels, settings and statistics are deleted. This can't be undone."
        alert.addButton(withTitle: "Delete All Data")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try model.deleteAllData()
            dataMessage = "All data deleted."
            reload()
        } catch {
            dataMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func reload() {
        labels = model.labels
        settings = model.settings
        onChange()
    }
}
