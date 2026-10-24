import Foundation

public struct SessionDatabase: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var sessions: [FocusSession] = []
    public init() {}
    public var activeSession: FocusSession? { sessions.last { $0.status == .active } }

    @discardableResult
    public mutating func start(title: String, mode: TriggerMode, configuration: SessionConfiguration,
                               apps: [SelectedApp], at date: Date, id: UUID = UUID()) throws -> FocusSession {
        expire(at: date)
        guard activeSession == nil else { throw FocusError.sessionAlreadyActive }
        try configuration.validate()
        guard !apps.isEmpty, Set(apps.map(\.id)).count == apps.count else { throw FocusError.emptySelection }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = FocusSession(id: id, title: trimmed.isEmpty ? "Studying" : trimmed, mode: mode,
                                   configuration: configuration, startedAt: date,
                                   scheduledEnd: date.addingTimeInterval(Double(configuration.durationMinutes * 60)),
                                   apps: apps)
        sessions.append(session)
        // Bound local prototype history to 50 sessions; active session is always the newest.
        if sessions.count > 50 { sessions.removeFirst(sessions.count - 50) }
        return session
    }

    public mutating func expire(at date: Date) {
        for index in sessions.indices where sessions[index].status == .active && date >= sessions[index].scheduledEnd {
            finish(index: index, status: .completed, at: sessions[index].scheduledEnd)
        }
    }

    public mutating func end(sessionID: UUID, status: SessionStatus = .completed, at date: Date) {
        guard status != .active,
              let index = sessions.firstIndex(where: { $0.id == sessionID && $0.status == .active }) else { return }
        finish(index: index, status: status, at: min(date, sessions[index].scheduledEnd))
    }

    private mutating func finish(index: Int, status: SessionStatus, at date: Date) {
        sessions[index].status = status
        sessions[index].endedAt = max(date, sessions[index].startedAt)
        sessions[index].pendingTriggerID = nil
        sessions[index].attemptTimes = []
        // No need to retain sensitive tokens once enforcement ends.
        for appIndex in sessions[index].apps.indices { sessions[index].apps[appIndex].tokenData = nil }
        for triggerIndex in sessions[index].triggers.indices { sessions[index].triggers[triggerIndex].returnURL = nil }
    }

    /// Callbacks identify their session, so a late callback cannot shield a replacement session.
    @discardableResult
    public mutating func reachUsageThreshold(sessionID: UUID, at date: Date) -> Bool {
        expire(at: date)
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }),
              sessions[index].mode == .deviceActivity, sessions[index].isActive(at: date),
              sessions[index].triggers.isEmpty else { return false }
        sessions[index].triggers.append(TriggerRecord(timestamp: date, kind: .usageThreshold))
        return true
    }

    /// Counts selected-app attempts, including repeated opens of the SAME app. This is a simulation,
    /// not a distinct-app counter and not a measurement of actual app launches.
    @discardableResult
    public mutating func simulateAttempt(sessionID: UUID, appID: String, at date: Date,
                                         force: Bool = false) -> TriggerRecord? {
        recordAttempt(sessionID: sessionID, appID: appID, mode: .simulated, at: date,
                      force: force, returnURL: nil)
    }

    /// Records an app open relayed by a user-configured Shortcuts automation.
    @discardableResult
    public mutating func recordShortcutAttempt(sessionID: UUID, appID: String,
                                               returnURL: String? = nil, at date: Date) -> TriggerRecord? {
        recordAttempt(sessionID: sessionID, appID: appID, mode: .shortcuts, at: date,
                      force: false, returnURL: ShortcutReturnURL.canonicalString(returnURL))
    }

    /// Background Shortcut entry point. Inactive, expired, and non-Shortcuts sessions are no-ops.
    @discardableResult
    public mutating func recordShortcutOpen(appID: String, returnURL: String? = nil,
                                            at date: Date) -> TriggerRecord? {
        expire(at: date)
        guard let session = activeSession, session.mode == .shortcuts else { return nil }
        return recordShortcutAttempt(sessionID: session.id, appID: appID,
                                     returnURL: returnURL, at: date)
    }

    private mutating func recordAttempt(sessionID: UUID, appID: String, mode: TriggerMode,
                                        at date: Date, force: Bool, returnURL: String?) -> TriggerRecord? {
        expire(at: date)
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }),
              sessions[index].mode == mode, sessions[index].isActive(at: date),
              sessions[index].apps.contains(where: { $0.id == appID }) else { return nil }
        var session = sessions[index]
        // Ignore out-of-order clocks/events rather than turning future timestamps into attempts.
        if let last = session.lastAttemptAt, date < last { return nil }

        // Record outcome evidence before cooldown, Continue exemptions, or a pending intervention
        // suppress normal triggering. This is one binary outcome per Go Back, not an open counter.
        var didRecordReopen = false
        for decisionIndex in session.decisions.indices {
            let decision = session.decisions[decisionIndex]
            guard decision.decision == .goBack, decision.reopenedAt == nil,
                  date > decision.timestamp,
                  let endsAt = decision.reopenObservationEndsAt, date <= endsAt else { continue }
            session.decisions[decisionIndex].reopenedAt = date
            didRecordReopen = true
        }

        // Continue exemptions and pending interventions must not trigger another prompt, but
        // selected-app events still count as follow-up observations for an earlier Go Back.
        guard !session.allowedAppIDs.contains(appID), session.pendingTriggerID == nil else {
            if didRecordReopen { sessions[index] = session }
            return nil
        }
        session.lastAttemptAt = date
        session.attemptTimes.removeAll { date.timeIntervalSince($0) > session.configuration.windowSeconds }
        if let lastDecision = session.decisions.last,
           date.timeIntervalSince(lastDecision.timestamp) < session.configuration.cooldownSeconds, !force {
            session.attemptTimes = []
            sessions[index] = session
            return nil
        }
        session.attemptTimes.append(date)
        guard force || session.attemptTimes.count >= session.configuration.attemptThreshold else {
            sessions[index] = session
            return nil
        }
        let trigger = TriggerRecord(timestamp: date, kind: force ? .manual : .repeatedAttempts,
                                    attemptCount: session.attemptTimes.count, appID: appID,
                                    returnURL: returnURL)
        session.triggers.append(trigger)
        session.pendingTriggerID = trigger.id
        session.attemptTimes = []
        sessions[index] = session
        return trigger
    }

    @discardableResult
    public mutating func decide(sessionID: UUID, appID: String, triggerID: UUID, decision: Decision,
                                at date: Date, requestID: UUID = UUID(),
                                continueReason: ContinueReason? = nil) -> Bool {
        expire(at: date)
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }),
              sessions[index].isActive(at: date),
              sessions[index].apps.contains(where: { $0.id == appID }),
              !sessions[index].allowedAppIDs.contains(appID),
              !sessions[index].decisions.contains(where: { $0.id == requestID }),
              let trigger = sessions[index].triggers.first(where: { $0.id == triggerID }),
              date >= trigger.timestamp else { return false }
        if sessions[index].mode == .simulated {
            guard sessions[index].pendingTriggerID == triggerID, trigger.appID == appID else { return false }
        }
        let reopenObservationEndsAt = decision == .goBack && sessions[index].mode == .shortcuts
            ? date.addingTimeInterval(ReopenObservation.windowSeconds)
            : nil
        sessions[index].decisions.append(DecisionRecord(id: requestID, triggerID: triggerID, appID: appID,
                                                        timestamp: date, decision: decision,
                                                        continueReason: decision == .continue ? continueReason : nil,
                                                        reopenObservationEndsAt: reopenObservationEndsAt))
        if decision == .continue { sessions[index].allowedAppIDs.insert(appID) }
        if let triggerIndex = sessions[index].triggers.firstIndex(where: { $0.id == triggerID }) {
            sessions[index].triggers[triggerIndex].returnURL = nil
        }
        sessions[index].pendingTriggerID = nil
        sessions[index].attemptTimes = []
        return true
    }

    public mutating func rate(sessionID: UUID, usefulness: Int, annoyance: Int) throws {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }), sessions[index].status != .active else {
            throw FocusError.invalidRating
        }
        sessions[index].ratings = try SessionRatings(usefulness: usefulness, annoyance: annoyance)
    }
}
