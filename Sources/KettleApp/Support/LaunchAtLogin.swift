import ServiceManagement

/// Open at login, via `SMAppService` (SPEC section 5.4).
enum LaunchAtLogin {
    /// Registers or unregisters the app. Returns a message for the user when something needs
    /// their attention, or nil when it simply worked.
    static func set(_ enabled: Bool) -> String? {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            Log.app.error("Launch at login: \(String(describing: error), privacy: .public)")
            return "Couldn't change this: \(error.localizedDescription)"
        }
        if service.status == .requiresApproval {
            return "Allow Kettle in System Settings → General → Login Items."
        }
        return nil
    }
}
