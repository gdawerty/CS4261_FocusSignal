import SwiftUI
import FamilyControls
import UIKit
import FocusSignalCore

@MainActor
final class SessionViewModel: ObservableObject {
    @Published var database = SessionDatabase()
    @Published var errorMessage: String?
    @Published var presentedResultsID: UUID?
    @Published var demoFeedback = ""
    @Published var isAuthorizing = false
    private var runtime: ScreenTimeRuntime?
    private var refreshCount = 0

    static let demoApps = [(id: "video", name: "Video app"), (id: "feed", name: "Social feed"), (id: "forum", name: "Forum app")]
    var active: FocusSession? { database.activeSession }
    var canMonitor: Bool { runtime?.canMonitor == true }
    var isShortcutDemoBuild: Bool { ScreenTimeRuntime.isShortcutDemoBuild }
    var isReady: Bool { runtime != nil }
    var results: FocusSession? { database.sessions.first { $0.id == presentedResultsID } }

    init() {
        do {
            let runtime = try ScreenTimeRuntime()
            self.runtime = runtime
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-reset") && ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                try runtime.deleteAll()
            }
            #endif
            try runtime.reconcile()
            database = try runtime.store.read()
        } catch { errorMessage = error.localizedDescription }
    }

    func refresh(force: Bool = false) {
        guard let runtime else { return }
        perform {
            let previousID = active?.id
            refreshCount += 1
            if force || refreshCount % 5 == 0 { try runtime.reconcile() }
            let updated = try runtime.store.read()
            if updated != database { database = updated }
            if let previousID, active == nil { presentedResultsID = previousID }
        }
    }

    func authorize() async {
        isAuthorizing = true
        defer { isAuthorizing = false }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            refresh(force: true)
        } catch { errorMessage = error.localizedDescription }
    }

    @discardableResult
    func start(title: String, mode: TriggerMode, configuration: SessionConfiguration,
               selection: FamilyActivitySelection, demoAppIDs: Set<String>) -> Bool {
        guard let runtime else { return false }
        return perform {
            try runtime.start(title: title, mode: mode, configuration: configuration, selection: selection, demoAppIDs: demoAppIDs)
            presentedResultsID = nil
            demoFeedback = ""
            database = try runtime.store.read()
        }
    }

    func attempt(appID: String, force: Bool = false) {
        guard let runtime, let session = active else { return }
        perform {
            let trigger = try runtime.mutate { state in
                state.simulateAttempt(sessionID: session.id, appID: appID, at: Date(), force: force)
            }
            database = try runtime.store.read()
            if !session.apps.contains(where: { $0.id == appID }) {
                demoFeedback = "Ignored: this app isn’t selected."
            } else if session.allowedAppIDs.contains(appID) {
                demoFeedback = "Allowed until this session ends."
            } else if trigger != nil {
                demoFeedback = "Simulated intervention triggered."
            } else {
                demoFeedback = "\(active?.attemptTimes.count ?? 0) of \(session.configuration.attemptThreshold) attempts in the current window."
            }
        }
    }

    @discardableResult
    func handleExternalURL(_ url: URL, at date: Date = Date()) -> Bool {
        if ShortcutInterventionURL.route(from: url) != nil {
            return handleShortcutIntervention(url)
        }
        guard let appID = ShortcutAttemptURL.appID(from: url),
              let runtime, let session = active, session.mode == .shortcuts else { return false }
        return perform {
            let trigger = try runtime.mutate(at: date) {
                $0.recordShortcutAttempt(sessionID: session.id, appID: appID, at: date)
            }
            database = try runtime.store.read()
            if !session.apps.contains(where: { $0.id == appID }) {
                demoFeedback = "Ignored: this Shortcuts app alias isn’t selected."
            } else if session.allowedAppIDs.contains(appID) {
                demoFeedback = "Ignored: Continue already allowed this app until the session ends."
            } else if trigger != nil {
                demoFeedback = "Shortcuts app-open threshold reached."
            } else {
                demoFeedback = "\(active?.attemptTimes.count ?? 0) of \(session.configuration.attemptThreshold) app opens in the current window."
            }
        }
    }

    @discardableResult
    func handleShortcutIntervention(_ url: URL) -> Bool {
        guard let route = ShortcutInterventionURL.route(from: url), let runtime else { return false }
        do {
            try runtime.reconcile()
            let updated = try runtime.store.read()
            guard let session = updated.activeSession,
                  session.mode == .shortcuts,
                  let pendingTriggerID = session.pendingTriggerID,
                  route.sessionID == nil || route.sessionID == session.id,
                  route.triggerID == nil || route.triggerID == pendingTriggerID else {
                database = updated
                return false
            }
            database = updated
            demoFeedback = "Shortcuts app-open threshold reached. Choose Continue to return to that app if a return URL was configured."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func decide(_ decision: Decision, trigger: TriggerRecord, continueReason: ContinueReason? = nil) {
        guard let runtime, let session = active, let appID = trigger.appID else { return }
        var returnDestination: URL?
        let succeeded = perform {
            let accepted = try runtime.mutate {
                $0.decide(sessionID: session.id, appID: appID, triggerID: trigger.id,
                          decision: decision, at: Date(), continueReason: continueReason)
            }
            database = try runtime.store.read()
            if !accepted { throw FocusError.invalidDecision }
            if decision == .continue, session.mode == .shortcuts,
               let canonical = ShortcutReturnURL.canonicalString(trigger.returnURL) {
                returnDestination = URL(string: canonical)
                demoFeedback = "Continue recorded. This app alias is allowed until the session ends; returning now."
            } else if decision == .continue {
                demoFeedback = "Continue recorded. This app alias is allowed until the session ends. Switch back to the app manually."
            } else {
                demoFeedback = "Go Back recorded. The configured cooldown is active."
            }
        }
        guard succeeded, let returnDestination else { return }
        UIApplication.shared.open(returnDestination) { [weak self] didOpen in
            guard !didOpen else { return }
            Task { @MainActor [weak self] in
                self?.demoFeedback = "Continue is recorded, but iOS could not open the return URL. Switch back to the app manually."
            }
        }
    }

    func end(cancelled: Bool = false) {
        guard let runtime, let id = active?.id else { return }
        perform {
            try runtime.end(id, status: cancelled ? .cancelled : .completed)
            database = try runtime.store.read()
            presentedResultsID = id
        }
    }

    func rate(sessionID: UUID, usefulness: Int, annoyance: Int) {
        guard let runtime else { return }
        perform {
            try runtime.mutate { try $0.rate(sessionID: sessionID, usefulness: usefulness, annoyance: annoyance) }
            database = try runtime.store.read()
        }
    }

    func deleteAll() {
        guard let runtime else { return }
        perform {
            try runtime.deleteAll()
            database = try runtime.store.read()
            presentedResultsID = nil
            demoFeedback = ""
        }
    }

    @discardableResult
    private func perform(_ work: () throws -> Void) -> Bool {
        do { try work(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
}
