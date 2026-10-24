import AppIntents
import FocusSignalCore

/// Runs from an app-open personal automation without bringing FocusSignal forward.
/// Returns `true` only when a pending intervention has been saved.
struct RecordShortcutAppOpenIntent: AppIntent {
    static let title: LocalizedStringResource = "Record FocusSignal App Open"
    static let description = IntentDescription(
        "Counts this app open and returns true only when FocusSignal needs to show an intervention."
    )

    // iOS 16.4–25 compatibility. On iOS 26+, supportedModes below explicitly prefers background.
    static var openAppWhenRun: Bool { false }

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "FocusSignal app alias", default: "feed")
    var appAlias: String

    @Parameter(title: "Return URL (optional)", default: "")
    var returnURL: String

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        // Keep this action exclusive to the no-entitlement Shortcut demo target.
        guard ScreenTimeRuntime.isShortcutDemoBuild else { return .result(value: false) }

        let runtime = try ScreenTimeRuntime()
        let now = Date()
        let shouldIntervene = try runtime.mutate(at: now) { state -> Bool in
            state.recordShortcutOpen(appID: appAlias, returnURL: returnURL, at: now) != nil
        }

        return .result(value: shouldIntervene)
    }
}
