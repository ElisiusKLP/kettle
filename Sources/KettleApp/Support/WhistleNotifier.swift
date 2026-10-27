import Foundation
import KettleCore
import UserNotifications

/// Schedules the time's-up notification ahead of time (so it fires even while Kettle isn't
/// ticking) and handles its Done and Keep brewing actions. Local notifications only.
final class WhistleNotifier: NSObject, UNUserNotificationCenterDelegate {
    /// Followed by the task ID, so a new whistle never replaces one still on screen.
    private static let identifierPrefix = "io.github.kettle.whistle."
    /// Overtime: Done and Keep brewing.
    private static let category = "WHISTLE"
    /// The task has already finished: Keep brewing only.
    private static let finishedCategory = "WHISTLE_FINISHED"
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
    /// Whether macOS lets the whistle notification play its sound, as of the last check. If not,
    /// the app plays it itself.
    private(set) var canPlaySound = true

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
        let previous = scheduled
        scheduled = request
        // Kettle posts nothing but whistles.
        center.removeAllPendingNotificationRequests()
        // A whistle for a task that finished when its time ran out stays up, so its Keep
        // brewing still works. Any other one is out of date now.
        if previous.map({ model.engine.reopenableID != $0.taskID }) ?? true {
            center.removeAllDeliveredNotifications()
        }
        guard let request else { return }
        askForPermissionOnce()
        checkSoundPermission()

        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = request
            .playsSound ? UNNotificationSound(named: UNNotificationSoundName(Whistle.soundFile)) : nil
        content.categoryIdentifier = request.offersDone ? Self.category : Self.finishedCategory
        content.userInfo = [Self.taskKey: request.taskID.uuidString]
        // A calendar trigger fires at the wall-clock time, also after the Mac has slept.
        let components = Calendar.autoupdatingCurrent.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: request.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = Self.identifierPrefix + request.taskID.uuidString
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)) { error in
            if let error {
                Log.app.error("Scheduling the whistle failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func registerActions(_ settings: AppSettings) {
        let titles = Whistle.keepBrewingTitles(settings)
        guard registeredTitles != [titles.main, titles.secondary] else { return }
        registeredTitles = [titles.main, titles.secondary]
        let keepBrewing = [
            UNNotificationAction(identifier: Action.keepBrewing.rawValue, title: titles.main),
            UNNotificationAction(identifier: Action.keepBrewingSecondary.rawValue, title: titles.secondary),
        ]
        let done = UNNotificationAction(identifier: Action.done.rawValue, title: "Done")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [done] + keepBrewing, intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.finishedCategory, actions: keepBrewing, intentIdentifiers: []),
        ])
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

    private func checkSoundPermission() {
        center.getNotificationSettings { settings in
            let allowed = settings.authorizationStatus == .authorized && settings.soundSetting == .enabled
            DispatchQueue.main.async { self.canPlaySound = allowed }
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
            // Only act on the task the notification was about, while that still makes sense.
            if let action, let id = taskID.flatMap(UUID.init(uuidString:)) {
                switch action {
                case .done where model.engine.activeTask?.id == id:
                    model.done()
                case .keepBrewing where model.engine.canKeepBrewing(id):
                    model.keepBrewing(taskID: id)
                case .keepBrewingSecondary where model.engine.canKeepBrewing(id):
                    model.keepBrewing(secondary: true, taskID: id)
                default:
                    break
                }
                onChange()
            }
            completionHandler()
        }
    }
}
