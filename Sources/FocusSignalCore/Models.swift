import Foundation

public enum TriggerMode: String, Codable, CaseIterable, Sendable {
    case simulated, shortcuts, deviceActivity
}

/// A Shortcuts personal automation reports an app open by launching this custom URL.
/// The app alias is explicit because iOS does not include the source app in the URL.
public enum ShortcutAttemptURL {
    public static let scheme = "focussignal"
    public static let shortcutDemoScheme = "focussignal-shortcuts"
    public static let host = "attempt"

    public static func make(appID: String, scheme: String = ShortcutAttemptURL.scheme) -> URL? {
        guard isValidAppID(appID), acceptedSchemes.contains(scheme.lowercased()) else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: "app", value: appID)]
        return components.url
    }

    public static func appID(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), acceptedSchemes.contains(scheme),
              components.host?.lowercased() == host,
              components.user == nil, components.password == nil, components.port == nil,
              components.path.isEmpty, components.fragment == nil,
              let items = components.queryItems, items.count == 1,
              items[0].name == "app", let appID = items[0].value,
              isValidAppID(appID) else { return nil }
        return appID
    }

    private static func isValidAppID(_ appID: String) -> Bool {
        !appID.isEmpty && appID.utf8.count <= 48 &&
            appID.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ ")).contains($0)
            } && !appID.contains(" ")
    }

    private static let acceptedSchemes: Set<String> = [scheme, shortcutDemoScheme]
}

public struct ShortcutInterventionRoute: Equatable, Sendable {
    /// Nil IDs identify the stable Shortcuts route, which resolves the current pending trigger.
    /// Populated IDs support older links that carried an exact trigger identity.
    public let sessionID: UUID?
    public let triggerID: UUID?

    public init(sessionID: UUID? = nil, triggerID: UUID? = nil) {
        self.sessionID = sessionID
        self.triggerID = triggerID
    }
}

/// A separate route is used to present a trigger that the background Shortcut action
/// has already recorded. It must never record another app-open attempt.
public enum ShortcutInterventionURL {
    public static let host = "intervention"
    private static let acceptedSchemes: Set<String> = [
        ShortcutAttemptURL.scheme, ShortcutAttemptURL.shortcutDemoScheme
    ]

    /// Stable destination for Shortcuts' `If result is true` branch.
    public static func make(scheme: String = ShortcutAttemptURL.shortcutDemoScheme) -> URL? {
        guard acceptedSchemes.contains(scheme.lowercased()) else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        return components.url
    }

    /// Legacy form, retained for already-created links with explicit IDs.
    public static func make(sessionID: UUID, triggerID: UUID,
                            scheme: String = ShortcutAttemptURL.shortcutDemoScheme) -> URL? {
        guard acceptedSchemes.contains(scheme.lowercased()) else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [
            URLQueryItem(name: "session", value: sessionID.uuidString),
            URLQueryItem(name: "trigger", value: triggerID.uuidString)
        ]
        return components.url
    }

    public static func route(from url: URL) -> ShortcutInterventionRoute? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), acceptedSchemes.contains(scheme),
              components.host?.lowercased() == host,
              components.user == nil, components.password == nil, components.port == nil,
              components.path.isEmpty, components.fragment == nil else { return nil }

        guard let items = components.queryItems, !items.isEmpty else {
            return ShortcutInterventionRoute()
        }
        guard items.count == 2,
              let sessionValue = items.first(where: { $0.name == "session" })?.value,
              let triggerValue = items.first(where: { $0.name == "trigger" })?.value,
              let sessionID = UUID(uuidString: sessionValue),
              let triggerID = UUID(uuidString: triggerValue) else { return nil }
        return ShortcutInterventionRoute(sessionID: sessionID, triggerID: triggerID)
    }
}

/// Validates an optional app-specific URL supplied by that app's personal automation.
/// FocusSignal's own routes and non-URL payload schemes are never valid return destinations.
public enum ShortcutReturnURL {
    public static func canonicalString(_ rawValue: String?) -> String? {
        guard let rawValue, !rawValue.isEmpty, rawValue.utf8.count <= 2_048,
              let components = URLComponents(string: rawValue),
              let scheme = components.scheme?.lowercased(),
              scheme.unicodeScalars.first.map(CharacterSet.letters.contains) == true,
              scheme.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "+.-").union(.alphanumerics).contains($0)
              }),
              ![ShortcutAttemptURL.scheme, ShortcutAttemptURL.shortcutDemoScheme,
                "javascript", "data", "file", "shortcuts"].contains(scheme),
              components.user == nil, components.password == nil,
              components.fragment == nil else { return nil }
        if scheme == "http" || scheme == "https" {
            guard let host = components.host, !host.isEmpty else { return nil }
        }
        return components.url?.absoluteString
    }
}

public enum SessionStatus: String, Codable, Sendable {
    case active, completed, cancelled, interrupted
}

public enum Decision: String, Codable, Sendable {
    case goBack, `continue`
}

/// Follow-up window for observing a reported selected-app open after Go Back.
public enum ReopenObservation {
    public static let windowSeconds: TimeInterval = 180
}

public enum ContinueReason: String, Codable, CaseIterable, Sendable {
    case takingBreak
    case needSomething
    case browsing

    public var title: String {
        switch self {
        case .takingBreak: return "Taking a break"
        case .needSomething: return "I need something from this app"
        case .browsing: return "Just browsing"
        }
    }
}

public enum TriggerKind: String, Codable, Sendable {
    case repeatedAttempts, manual, usageThreshold
}

public enum FocusError: LocalizedError, Equatable {
    case invalidConfiguration, emptySelection, sessionAlreadyActive, noActiveSession
    case invalidDecision, invalidRating, unsupportedVersion, corruptStore, lockFailed

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "Choose a 15–120 minute session, a valid usage threshold, and positive trigger settings."
        case .emptySelection: return "Select at least one distracting app."
        case .sessionAlreadyActive: return "End the current focus session first."
        case .noActiveSession: return "There is no active focus session."
        case .invalidDecision: return "This intervention is no longer active."
        case .invalidRating: return "Ratings must be between 1 and 5."
        case .unsupportedVersion: return "This data was created by a different version of FocusSignal."
        case .corruptStore: return "Local data could not be read. It has been preserved; use Delete All Local Data to reset it."
        case .lockFailed: return "Local data is busy or unavailable. Please try again."
        }
    }
}

public struct SessionConfiguration: Codable, Equatable, Sendable {
    public var durationMinutes: Int
    public var usageThresholdSeconds: Int
    public var attemptThreshold: Int
    public var windowSeconds: TimeInterval
    public var cooldownSeconds: TimeInterval

    public init(durationMinutes: Int = 30, usageThresholdSeconds: Int = 60,
                attemptThreshold: Int = 3, windowSeconds: TimeInterval = 300,
                cooldownSeconds: TimeInterval = 60) {
        self.durationMinutes = durationMinutes
        self.usageThresholdSeconds = usageThresholdSeconds
        self.attemptThreshold = attemptThreshold
        self.windowSeconds = windowSeconds
        self.cooldownSeconds = cooldownSeconds
    }

    public func validate() throws {
        guard (15...120).contains(durationMinutes), usageThresholdSeconds > 0,
              usageThresholdSeconds < durationMinutes * 60,
              (1...100).contains(attemptThreshold), windowSeconds.isFinite,
              windowSeconds > 0, cooldownSeconds.isFinite, cooldownSeconds >= 0 else {
            throw FocusError.invalidConfiguration
        }
    }
}

/// IDs are random local aliases. Tokens never appear in the event log or exports.
public struct SelectedApp: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var tokenData: Data?
    public init(id: String = UUID().uuidString, tokenData: Data? = nil) {
        self.id = id
        self.tokenData = tokenData
    }
}

public struct TriggerRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var kind: TriggerKind
    public var attemptCount: Int?
    public var appID: String?
    /// Held only while this intervention is pending, then cleared on decision/session end.
    public var returnURL: String?
    public init(id: UUID = UUID(), timestamp: Date, kind: TriggerKind,
                attemptCount: Int? = nil, appID: String? = nil, returnURL: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.attemptCount = attemptCount
        self.appID = appID
        self.returnURL = returnURL
    }
}

public struct DecisionRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var triggerID: UUID
    public var appID: String
    public var timestamp: Date
    public var decision: Decision
    /// Older locally stored decisions do not have a reason; native shield actions may not collect one.
    public var continueReason: ContinueReason?
    /// Present only for Go Back decisions in Shortcut mode. Optional for older local records.
    public var reopenObservationEndsAt: Date?
    /// First selected-app open reported during the observation window, if any.
    public var reopenedAt: Date?

    public init(id: UUID, triggerID: UUID, appID: String, timestamp: Date,
                decision: Decision, continueReason: ContinueReason? = nil,
                reopenObservationEndsAt: Date? = nil, reopenedAt: Date? = nil) {
        self.id = id
        self.triggerID = triggerID
        self.appID = appID
        self.timestamp = timestamp
        self.decision = decision
        self.continueReason = continueReason
        self.reopenObservationEndsAt = reopenObservationEndsAt
        self.reopenedAt = reopenedAt
    }
}

public struct SessionRatings: Codable, Equatable, Sendable {
    public var usefulness: Int
    public var annoyance: Int
    public init(usefulness: Int, annoyance: Int) throws {
        guard (1...5).contains(usefulness), (1...5).contains(annoyance) else {
            throw FocusError.invalidRating
        }
        self.usefulness = usefulness
        self.annoyance = annoyance
    }
}

public struct FocusSession: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var mode: TriggerMode
    public var configuration: SessionConfiguration
    public var startedAt: Date
    public var scheduledEnd: Date
    public var endedAt: Date?
    public var status: SessionStatus = .active
    public var apps: [SelectedApp]
    public var allowedAppIDs: Set<String> = []
    public var attemptTimes: [Date] = []
    public var lastAttemptAt: Date?
    public var triggers: [TriggerRecord] = []
    public var decisions: [DecisionRecord] = []
    public var pendingTriggerID: UUID?
    public var ratings: SessionRatings?

    public var pendingTrigger: TriggerRecord? {
        triggers.first { $0.id == pendingTriggerID }
    }

    public func isActive(at date: Date) -> Bool {
        status == .active && date >= startedAt && date < scheduledEnd
    }

    /// Applying a shield is not proof that the user saw it; keep trigger and decision counts separate.
    public func shieldedAppIDs(at date: Date) -> Set<String> {
        guard mode == .deviceActivity, isActive(at: date), !triggers.isEmpty else { return [] }
        return Set(apps.map(\.id)).subtracting(allowedAppIDs)
    }
}

public struct SessionMetrics: Equatable, Sendable {
    public let triggerCount: Int
    public let goBackCount: Int
    public let continueCount: Int
    public let continueReasonCounts: [ContinueReason: Int]
    public let reopenTrackingAvailable: Bool
    public let trackedGoBackCount: Int
    public let reopenedAfterGoBackCount: Int
    public let noReopenObservedCount: Int
    public let incompleteFollowUpCount: Int
    public var decisionCount: Int { goBackCount + continueCount }
    public var goBackFraction: Double? {
        decisionCount == 0 ? nil : Double(goBackCount) / Double(decisionCount)
    }
    public var continueFraction: Double? {
        decisionCount == 0 ? nil : Double(continueCount) / Double(decisionCount)
    }
    public init(session: FocusSession, asOf date: Date = Date()) {
        triggerCount = session.triggers.count
        goBackCount = session.decisions.filter { $0.decision == .goBack }.count
        continueCount = session.decisions.filter { $0.decision == .continue }.count
        continueReasonCounts = Dictionary(grouping: session.decisions.compactMap { decision in
            decision.decision == .continue ? decision.continueReason : nil
        }, by: { $0 }).mapValues(\.count)

        reopenTrackingAvailable = session.mode == .shortcuts
        let trackedDecisions = session.mode == .shortcuts
            ? session.decisions.filter { $0.decision == .goBack && $0.reopenObservationEndsAt != nil }
            : []
        trackedGoBackCount = trackedDecisions.count
        reopenedAfterGoBackCount = trackedDecisions.filter { $0.reopenedAt != nil }.count
        // An ended session is the limit of observation, even if the result is viewed later.
        let observedThrough = session.endedAt ?? date
        noReopenObservedCount = trackedDecisions.filter {
            $0.reopenedAt == nil && $0.reopenObservationEndsAt.map { observedThrough >= $0 } == true
        }.count
        incompleteFollowUpCount = trackedDecisions.filter {
            $0.reopenedAt == nil && $0.reopenObservationEndsAt.map { observedThrough < $0 } == true
        }.count
    }
}
