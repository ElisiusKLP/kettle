import AppKit
import KettleCore
import KettleIcon

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: KettleModel?
    private var statusItemController: StatusItemController?

    private var isDev: Bool {
        Bundle.main.bundleIdentifier != Kettle.bundleID
    }

    func applicationDidFinishLaunching(_: Notification) {
        let folder: URL
        do {
            folder = try DataLocation.resolve()
        } catch {
            Log.app.fault("No Application Support folder: \(String(describing: error), privacy: .public)")
            NSApp.terminate(nil)
            return
        }
        let store = JSONStore(directory: folder, calendar: .autoupdatingCurrent)
        store.onWriteError = { error in
            Log.storage.error("Write failed: \(String(describing: error), privacy: .public)")
        }
        do {
            let model = try KettleModel(store: store, clock: SystemClock(), calendar: .autoupdatingCurrent)
            model.onError = { error in
                Log.storage.error("\(String(describing: error), privacy: .public)")
            }
            self.model = model
            statusItemController = StatusItemController(
                model: model,
                style: isDev ? .dev : .template,
                dataFolder: folder
            )
            let variant = isDev ? "Kettle Dev" : "Kettle"
            Log.app.info("\(variant, privacy: .public) started")
        } catch {
            Log.app.fault("Could not load data: \(String(describing: error), privacy: .public)")
            showLoadFailure(error, folder: folder)
        }
    }

    func applicationWillTerminate(_: Notification) {
        model?.flush()
    }

    /// Kettle won't start on top of data it can't read, so the user can fix or restore it first.
    private func showLoadFailure(_ error: Error, folder: URL) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Kettle couldn't read its data"
        alert.informativeText = """
        \(String(describing: error))

        Nothing has been changed. Fix or remove the file in the data folder, then open Kettle again.
        """
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Reveal Data Folder")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        }
        NSApp.terminate(nil)
    }
}
