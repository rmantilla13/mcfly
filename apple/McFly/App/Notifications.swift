import Foundation
import Observation
import UserNotifications
#if os(iOS)
import UIKit
#endif

/// Where notifications meet the app: the iPhone's push token from Apple, a
/// tap on a message's notification (open Messages), its Reply (send it), and
/// whether the thread is on screen (then a message from home needs no banner).
/// AppModel sets the handlers when it's made, which is at launch, so a Reply
/// sent from the lock screen while the app wasn't running still goes.
@MainActor
@Observable
final class PushCenter {
    static let shared = PushCenter()

    /// A message's notification was tapped: the app opens Messages.
    var openMessages = false
    /// Messages is on screen.
    var showingMessages = false

    @ObservationIgnored private(set) var token: String?
    @ObservationIgnored var onToken: ((String) -> Void)?
    @ObservationIgnored var onReply: ((String) async -> Void)?
    @ObservationIgnored var onMessage: (() -> Void)?

    /// Apple's token for this install, as hex.
    func received(token data: Data) {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        token = hex
        onToken?(hex)
    }
}

/// The notification centre's delegate, on both platforms: the iPhone's
/// pushes (the `notify` function) and the Mac's own notifications for what
/// its poll found. Installed before launch finishes, as Apple asks, so a tap
/// that launched the app is seen.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// As the notify function sends them (functions/notify/apns.ts).
    static let messageCategory = "MCFLY_MESSAGE"
    static let messageThread = "mcfly-messages"
    static let replyAction = "MCFLY_REPLY"

    func install() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let reply = UNTextInputNotificationAction(identifier: Self.replyAction, title: "Reply", options: [],
                                                  textInputButtonTitle: "Send", textInputPlaceholder: "Message home")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.messageCategory, actions: [reply], intentIdentifiers: [], options: []),
        ])
    }

    static func isMessage(_ content: UNNotificationContent) -> Bool {
        content.categoryIdentifier == messageCategory || content.userInfo["message_id"] != nil
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let isMessage = Self.isMessage(notification.request.content)
        let showing = await MainActor.run {
            if isMessage { PushCenter.shared.onMessage?() }
            return PushCenter.shared.showingMessages
        }
        return isMessage && showing ? [] : [.banner, .list, .sound, .badge]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard Self.isMessage(response.notification.request.content) else { return }
        if response.actionIdentifier == Self.replyAction, let text = (response as? UNTextInputNotificationResponse)?.userText {
            let reply = await MainActor.run { PushCenter.shared.onReply }
            await reply?(text)
        } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            await MainActor.run { PushCenter.shared.openMessages = true }
        }
    }
}

#if os(iOS)
/// Only for Apple's token: SwiftUI has no other way to hear it.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushCenter.shared.received(token: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // A simulator, or a build without the push entitlement: Messages still works, without notifications.
        print("McFly: no push token:", error.localizedDescription)
    }
}
#endif
