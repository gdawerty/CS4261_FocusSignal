import Foundation
import FamilyControls
import DeviceActivity
import ManagedSettings
import FocusSignalCore

enum ScreenTimeError: LocalizedError {
    case appGroupUnavailable, authorizationRequired, appsOnly, invalidToken, simulator
    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable: return "Real-device mode needs a registered App Group and Family Controls signing. Follow the setup steps in README. Demo mode is available now."
        case .authorizationRequired: return "Allow Screen Time access before starting real-device mode."
        case .appsOnly: return "Select individual apps only. Entire categories and websites are not supported in this prototype."
        case .invalidToken: return "Your app selection is no longer valid. Select the apps again."
        case .simulator: return "Use Demo mode in the simulator. Real usage monitoring needs a signed physical iPhone build."
        }
    }
}

protocol BehaviorTriggerEngine {
    func start(session: FocusSession) throws
    func stop(sessionID: UUID)
}

struct SimulatedPatternTrigger: BehaviorTriggerEngine {
    func start(session: FocusSession) throws {}
    func stop(sessionID: UUID) {}
    // The actual timestamp queue is in SessionDatabase so it survives process restarts and is testable.
}

struct DeviceActivityThresholdTrigger: BehaviorTriggerEngine {
    static let prefix = "focussignal.session."
    static let event = DeviceActivityEvent.Name("selected-app-usage")
    static func name(_ id: UUID) -> DeviceActivityName { .init(prefix + id.uuidString) }
    static func sessionID(_ name: DeviceActivityName) -> UUID? {
        guard name.rawValue.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(name.rawValue.dropFirst(prefix.count)))
    }

    func start(session: FocusSession) throws {
        #if targetEnvironment(simulator)
        throw ScreenTimeError.simulator
        #else
        let tokens = try ScreenTimeRuntime.tokens(for: session.apps)
        guard !tokens.isEmpty else { throw FocusError.emptySelection }
        let window = try MonitoringWindow(session: session)
        let schedule = DeviceActivitySchedule(intervalStart: window.start, intervalEnd: window.end, repeats: false)
        guard let resolved = schedule.nextInterval, resolved.duration >= 900,
              abs(resolved.end.timeIntervalSince(session.scheduledEnd)) < 2 else {
            throw FocusError.invalidConfiguration
        }
        let event = DeviceActivityEvent(applications: tokens, categories: [], webDomains: [],
                                        threshold: DateComponents(second: session.configuration.usageThresholdSeconds),
                                        includesPastActivity: false)
        try DeviceActivityCenter().startMonitoring(Self.name(session.id), during: schedule, events: [Self.event: event])
        #endif
    }

    func stop(sessionID: UUID) {
        #if !targetEnvironment(simulator)
        DeviceActivityCenter().stopMonitoring([Self.name(sessionID)])
        #endif
    }
}

/// Shared by the app, monitor and shield action extension. It has no dependence on a running UI.
final class ScreenTimeRuntime {
    static let storeName = ManagedSettingsStore.Name("FocusSignal.Session")
    static var isShortcutDemoBuild: Bool {
        Bundle.main.object(forInfoDictionaryKey: "FocusSignalBuildFlavor") as? String == "shortcuts"
    }
    let store: LocalStore
    let canMonitor: Bool

    init(forExtension: Bool = false) throws {
        let base: URL
        if Self.isShortcutDemoBuild {
            guard !forExtension else { throw ScreenTimeError.appGroupUnavailable }
            canMonitor = false
            base = try Self.appDirectory()
        } else {
            #if targetEnvironment(simulator)
            guard !forExtension else { throw ScreenTimeError.simulator }
            canMonitor = false
            base = try Self.appDirectory()
            #else
            if let group = Bundle.main.object(forInfoDictionaryKey: "FocusSignalAppGroup") as? String,
               let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
                base = container
                canMonitor = true
            } else {
                guard !forExtension else { throw ScreenTimeError.appGroupUnavailable }
                base = try Self.appDirectory()
                canMonitor = false
            }
            #endif
        }
        // UI tests have isolated storage and can never delete a real user's sessions.
        #if DEBUG
        let directoryName = ProcessInfo.processInfo.arguments.contains("--ui-testing") ? "FocusSignalUITests" : "FocusSignal"
        #else
        let directoryName = "FocusSignal"
        #endif
        store = try LocalStore(directory: base.appendingPathComponent(directoryName, isDirectory: true))
    }

    private static func appDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
    }

    static var authorized: Bool {
        let status = AuthorizationCenter.shared.authorizationStatus
        if status == .approved { return true }
        if #available(iOS 26.4, *), status == .approvedWithDataAccess { return true }
        return false
    }

    static func tokens(for apps: [SelectedApp]) throws -> Set<ApplicationToken> {
        try Set(apps.map { app in
            guard let data = app.tokenData,
                  let token = try? JSONDecoder().decode(ApplicationToken.self, from: data) else {
                throw ScreenTimeError.invalidToken
            }
            return token
        })
    }

    private func engine(for mode: TriggerMode) -> any BehaviorTriggerEngine {
        switch mode {
        case .simulated, .shortcuts: SimulatedPatternTrigger()
        case .deviceActivity: DeviceActivityThresholdTrigger()
        }
    }

    @discardableResult
    func mutate<T>(at date: Date = Date(), _ update: (inout SessionDatabase) throws -> T) throws -> T {
        try store.transaction({ state in
            state.expire(at: date)
            return try update(&state)
        }, afterCommit: { state in try self.synchronizeShield(state, at: date) })
    }

    private func synchronizeShield(_ state: SessionDatabase, at date: Date) throws {
        #if !targetEnvironment(simulator)
        guard canMonitor else { return }
        let settings = ManagedSettingsStore(named: Self.storeName)
        guard let session = state.activeSession, session.mode == .deviceActivity,
              session.isActive(at: date), Self.authorized else {
            settings.clearAllSettings()
            return
        }
        let ids = session.shieldedAppIDs(at: date)
        let tokens = try Self.tokens(for: session.apps.filter { ids.contains($0.id) })
        // This prototype only writes this named store and only shields individual apps.
        settings.shield.applicationCategories = nil
        settings.shield.webDomains = nil
        settings.shield.webDomainCategories = nil
        settings.shield.applications = tokens.isEmpty ? nil : tokens
        #endif
    }

    func start(title: String, mode: TriggerMode, configuration: SessionConfiguration,
               selection: FamilyActivitySelection, demoAppIDs: Set<String>) throws {
        try reconcile()
        let apps: [SelectedApp]
        if mode == .deviceActivity {
            guard canMonitor else { throw ScreenTimeError.appGroupUnavailable }
            guard Self.authorized else { throw ScreenTimeError.authorizationRequired }
            guard selection.categoryTokens.isEmpty, selection.webDomainTokens.isEmpty else { throw ScreenTimeError.appsOnly }
            apps = try selection.applicationTokens.map { SelectedApp(tokenData: try JSONEncoder().encode($0)) }
        } else {
            apps = demoAppIDs.sorted().map { SelectedApp(id: $0) }
        }
        let now = Date()
        let session = try mutate(at: now) {
            try $0.start(title: title, mode: mode, configuration: configuration, apps: apps, at: now)
        }
        do {
            try engine(for: mode).start(session: session)
        } catch {
            // Persist cancellation before stopping: a delayed threshold must not reapply a shield.
            try? mutate { $0.end(sessionID: session.id, status: .interrupted, at: Date()) }
            engine(for: mode).stop(sessionID: session.id)
            throw error
        }
    }

    func end(_ id: UUID, status: SessionStatus = .completed) throws {
        try mutate { $0.end(sessionID: id, status: status, at: Date()) }
        DeviceActivityThresholdTrigger().stop(sessionID: id)
    }

    func reconcile() throws {
        let now = Date()
        let expiredID = try mutate(at: now) { state -> UUID? in
            if let active = state.activeSession, active.mode == .deviceActivity, !Self.authorized {
                state.end(sessionID: active.id, status: .interrupted, at: now)
                return active.id
            }
            return nil
        }
        if let expiredID { DeviceActivityThresholdTrigger().stop(sessionID: expiredID) }
        #if !targetEnvironment(simulator)
        if canMonitor {
            let active = try store.read().activeSession
            let center = DeviceActivityCenter()
            let stale = center.activities.filter {
                guard let id = DeviceActivityThresholdTrigger.sessionID($0) else { return false }
                return active?.id != id || active?.mode != .deviceActivity
            }
            if !stale.isEmpty { center.stopMonitoring(stale) }
            // Recover from termination after persisting a session but before registering its monitor.
            if let active, active.mode == .deviceActivity,
               !center.activities.contains(DeviceActivityThresholdTrigger.name(active.id)) {
                try end(active.id, status: .interrupted)
            }
        }
        #endif
    }

    func deleteAll() throws {
        try store.reset(afterCommit: { state in try self.synchronizeShield(state, at: Date()) })
        #if !targetEnvironment(simulator)
        if canMonitor {
            let center = DeviceActivityCenter()
            center.stopMonitoring(center.activities.filter { DeviceActivityThresholdTrigger.sessionID($0) != nil })
        }
        #endif
    }

    func handleThreshold(activity: DeviceActivityName, event: DeviceActivityEvent.Name) throws {
        guard event == DeviceActivityThresholdTrigger.event,
              let id = DeviceActivityThresholdTrigger.sessionID(activity) else { return }
        let now = Date()
        try mutate(at: now) { state in
            if !Self.authorized { state.end(sessionID: id, status: .interrupted, at: now) }
            else { _ = state.reachUsageThreshold(sessionID: id, at: now) }
        }
    }

    func handleIntervalEnd(activity: DeviceActivityName) throws {
        guard let id = DeviceActivityThresholdTrigger.sessionID(activity) else { return }
        // Do not stop/restart monitoring from inside a monitor callback.
        try mutate { $0.end(sessionID: id, at: Date()) }
    }

    func handleDecision(_ decision: Decision, reason: ContinueReason? = nil, token: ApplicationToken) throws {
        let now = Date()
        try mutate(at: now) { state in
            guard let active = state.activeSession, active.mode == .deviceActivity,
                  let trigger = active.triggers.first,
                  let app = active.apps.first(where: {
                      guard let data = $0.tokenData else { return false }
                      return (try? JSONDecoder().decode(ApplicationToken.self, from: data)) == token
                  }) else { return }
            _ = state.decide(sessionID: active.id, appID: app.id, triggerID: trigger.id,
                             decision: decision, at: now, continueReason: reason)
        }
    }
}
