import Foundation
import KettleCore
import UserNotifications

/// Schedules the time's-up notification ahead of time (so it fires even while Kettle isn't
/// ticking) and handles its Done and Keep brewing actions. Local notifications only.
final class WhistleNotifier: NSObject, UNUserNotificationCenterDelegate {
    private static let identifier = "io.github.kettle.whistle"
    private static let category = "WHISTLE"
    private static let taskKey = "taskID"

    private enum Action: String {
        case done = "DONE"
        case keepBrewing = "KEEP_BREWING"
        case keepBrewingSecondary = "KEEP_BREWING_SECONDARY"
    }

    private let model: KettleModel
    private let onChange: () -> Void
    private let center = UNUserNotificationCenter.current()
    private var scheduled: WhistleRequest?
    private var registeredTitles: [String] = []
    private var askedForPermission = false

    init(model: KettleModel, onChange: @escaping () -> Void) {
        self.model = model
        self.onChange = onChange
        super.init()
        center.delegate = self
    }

    /// Call after anything that can move the end of the brewing block or change the settings.
    /// Not on every tick: the request only changes when the plan or settings do.
    func update() {
        let now = Date()
        let settings = model.settings
        registerActions(settings)
        let request = Whistle.request(engine: model.engine, now: now, settings: settings)
        guard request != scheduled else { return }
        scheduled = request
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        if model.engine.activeTask?.id != request?.taskID || request == nil {
            center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
        }
        guard let request else { return }
        askForPermissionOnce()

        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = request.playsSound ? .default : nil
        content.categoryIdentifier = Self.category
        content.userInfo = [Self.taskKey: request.taskID.uuidString]
        // A calendar trigger fires at the wall-clock time, also after the Mac has slept.
        let components = Calendar.autoupdatingCurrent.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: request.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger)) { error in
            if let error {
                Log.app.error("Scheduling the whistle failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func registerActions(_ settings: AppSettings) {
        let titles = Whistle.keepBrewingTitles(settings)
        guard registeredTitles != [titles.main, titles.secondary] else { return }
        registeredTitles = [titles.main, titles.secondary]
        let category = UNNotificationCategory(
            identifier: Self.category,
            actions: [
                UNNotificationAction(identifier: Action.done.rawValue, title: "Done"),
                UNNotificationAction(identifier: Action.keepBrewing.rawValue, title: titles.main),
                UNNotificationAction(identifier: Action.keepBrewingSecondary.rawValue, title: titles.secondary),
            ],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
    }

    private func askForPermissionOnce() {
        guard !askedForPermission else { return }
        askedForPermission = true
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if !granted {
                Log.app.info("Notifications not allowed\(error.map { ": \($0)" } ?? "", privacy: .public)")
            }
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = Action(rawValue: response.actionIdentifier)
        let taskID = response.notification.request.content.userInfo[Self.taskKey] as? String
        DispatchQueue.main.async { [self] in
            // Only act on the task the notification was about.
            if let action, model.engine.activeTask?.id.uuidString == taskID {
                switch action {
                case .done: model.done()
                case .keepBrewing: model.keepBrewing()
                case .keepBrewingSecondary: model.keepBrewing(secondary: true)
                }
                onChange()
            }
            completionHandler()
        }
    }
}
