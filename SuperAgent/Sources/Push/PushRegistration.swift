import Foundation
import UIKit
import UserNotifications
import os

private let log = Logger(subsystem: "dev.superagent.ios", category: "push")

/// Notification categories the Mac's pushes name (see desktop companion/push.ts).
enum NotificationCategory {
    static let approval = "APPROVAL"
    static let done = "DONE"
    static let approve = "APPROVE"
    static let deny = "DENY"

    static func register() {
        let approve = UNNotificationAction(identifier: approve, title: "Approve", options: [.authenticationRequired])
        let deny = UNNotificationAction(identifier: deny, title: "Deny", options: [.destructive, .authenticationRequired])
        let approvalCat = UNNotificationCategory(identifier: approval, actions: [approve, deny], intentIdentifiers: [],
                                                 hiddenPreviewsBodyPlaceholder: "Claude wants to act", options: [])
        let doneCat = UNNotificationCategory(identifier: done, actions: [], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([approvalCat, doneCat])
    }
}

/// What a SuperAgent push carries besides the visible alert.
struct PushInfo: Sendable {
    var kind: String
    var chatId: String?
    var workspaceId: String?
    var approvalId: String?

    init?(userInfo: [AnyHashable: Any]) {
        guard let sa = userInfo["sa"] as? [String: Any], let kind = sa["kind"] as? String else { return nil }
        self.kind = kind
        chatId = sa["chatId"] as? String
        workspaceId = sa["workspaceId"] as? String
        approvalId = sa["approvalId"] as? String
    }
}

/// APNs registration and notification handling. The app state answers
/// approvals; this only routes.
final class PushDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set by the App once AppState exists.
    @MainActor static weak var app: AppState?
    /// A tap on a notification before the UI is ready is kept here.
    @MainActor static var pendingOpen: PushInfo?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationCategory.register()
        Task { await Self.requestAuthorization() }
        return true
    }

    static func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            log.info("notifications granted=\(granted)")
            if granted { await MainActor.run { UIApplication.shared.registerForRemoteNotifications() } }
        } catch {
            log.error("authorization failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        log.info("apns token \(token.prefix(8), privacy: .public)…")
        Task { @MainActor in Self.app?.registerPushToken(token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        log.error("apns registration failed: \(error.localizedDescription, privacy: .public)")
    }

    // Foreground: show the banner anyway (the chat may not be the one on screen).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    // A tap or an action button. Runs in the background for actions.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        // Pull the Sendable bits out before hopping actors.
        let info = PushInfo(userInfo: response.notification.request.content.userInfo)
        let action = response.actionIdentifier
        guard let info else { return }
        await Self.route(info: info, action: action)
    }

    @MainActor
    private static func route(info: PushInfo, action: String) async {
        switch action {
        case NotificationCategory.approve, NotificationCategory.deny:
            guard let approvalId = info.approvalId else { return }
            await answer(approvalId: approvalId, approve: action == NotificationCategory.approve)
        default:
            pendingOpen = info
            app?.openFromPush(info)
        }
    }

    /// Answer an approval without bringing the app to the foreground: a short
    /// connection through the relay, inside the background time iOS grants.
    @MainActor
    static func answer(approvalId: String, approve: Bool) async {
        let task = UIApplication.shared.beginBackgroundTask(withName: "approval")
        defer { UIApplication.shared.endBackgroundTask(task) }
        guard let app else { return }
        var ok = false
        for machine in app.machines {
            let c = app.connection(for: machine)
            if c.state != .connected { c.connect() }
            for _ in 0..<40 where c.state != .connected { try? await Task.sleep(for: .milliseconds(250)) }
            guard c.state == .connected else { continue }
            if (try? await c.answerApproval(id: approvalId, approve: approve)) != nil {
                ok = true
                break
            }
        }
        if !ok {
            let content = UNMutableNotificationContent()
            content.title = "Couldn't reach your Mac"
            content.body = "Open SuperAgent to answer this from the app."
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "sa-fail-\(approvalId)", content: content, trigger: nil))
        }
    }
}
