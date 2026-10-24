import ManagedSettings
import FocusSignalCore
import os

final class FocusShieldAction: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        let decision: Decision
        let continueReason: ContinueReason?
        switch action {
        case .primaryButtonPressed:
            decision = .goBack
            continueReason = nil
        case .secondaryButtonPressed:
            completionHandler(.close) // Never allow Continue without a reason on systems lacking the submenu.
            return
        case .firstSecondarySubmenuItemPressed:
            decision = .continue
            continueReason = .takingBreak
        case .secondSecondarySubmenuItemPressed:
            decision = .continue
            continueReason = .needSomething
        case .thirdSecondarySubmenuItemPressed:
            decision = .continue
            continueReason = .browsing
        default: completionHandler(.none); return // Ignore cancellation or unrecognized shield actions.
        }
        do {
            try ScreenTimeRuntime(forExtension: true).handleDecision(decision, reason: continueReason, token: application)
            completionHandler(decision == .goBack ? .close : .none)
        } catch {
            Logger(subsystem: "FocusSignal", category: "ShieldAction").error("Could not persist shield decision. Open FocusSignal to recover.")
            completionHandler(.close)
        }
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(.close) // Categories are explicitly rejected at setup.
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(.close)
    }
}
