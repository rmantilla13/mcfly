import Foundation
#if os(iOS)
import UIKit
#endif

/// Keeps the screen from sleeping while something needs it (voice mode is
/// hands-free, so the phone mustn't lock mid-conversation). Reference counted
/// by reason, so two holders don't release each other's.
@MainActor
enum ScreenAwake {
    private static var reasons: Set<String> = []
    #if os(iOS)
    private static var previous = false
    #else
    private static var activity: NSObjectProtocol?
    #endif

    static func hold(_ reason: String) {
        guard reasons.insert(reason).inserted, reasons.count == 1 else { return }
        #if os(iOS)
        previous = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        #else
        activity = ProcessInfo.processInfo.beginActivity(options: .idleDisplaySleepDisabled, reason: "McFly is listening")
        #endif
    }

    static func release(_ reason: String) {
        guard reasons.remove(reason) != nil, reasons.isEmpty else { return }
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = previous
        #else
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        #endif
    }
}
