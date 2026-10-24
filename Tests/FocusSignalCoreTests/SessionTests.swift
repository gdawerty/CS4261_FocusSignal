import XCTest
@testable import FocusSignalCore

final class SessionTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let apps = [SelectedApp(id: "video", tokenData: Data([1])), SelectedApp(id: "feed", tokenData: Data([2]))]

    func makeSession(mode: TriggerMode = .simulated, config: SessionConfiguration = .init()) throws -> SessionDatabase {
        var state = SessionDatabase()
        try state.start(title: "Studying", mode: mode, configuration: config, apps: apps, at: now)
        return state
    }

    func testThreeSelectedAttemptsTriggerAndProductiveAppsAreIgnored() throws {
        var state = try makeSession()
        let id = try XCTUnwrap(state.activeSession?.id)
        XCTAssertNil(state.simulateAttempt(sessionID: id, appID: "docs", at: now))
        XCTAssertNil(state.simulateAttempt(sessionID: id, appID: "video", at: now))
        XCTAssertNil(state.simulateAttempt(sessionID: id, appID: "chatgpt", at: now.addingTimeInterval(1)))
        XCTAssertNil(state.simulateAttempt(sessionID: id, appID: "feed", at: now.addingTimeInterval(2)))
        let trigger = state.simulateAttempt(sessionID: id, appID: "video", at: now.addingTimeInterval(3))
        XCTAssertEqual(trigger?.attemptCount, 3)
        XCTAssertEqual(trigger?.kind, .repeatedAttempts)
        XCTAssertNil(state.simulateAttempt(sessionID: id, appID: "feed", at: now.addingTimeInterval(4)))
        XCTAssertEqual(state.activeSession?.triggers.count, 1)
    }

    func testWindowBoundaryAndOldAttemptsExpire() throws {
        var state = try makeSession()
        let id = try XCTUnwrap(state.activeSession?.id)
        _ = state.simulateAttempt(sessionID: id, appID: "video", at: now)
        _ = state.simulateAttempt(sessionID: id, appID: "video", at: now.addingTimeInterval(1))
        XCTAssertNil(state.simulateAttempt(sessionID: id, appID: "video", at: now.addingTimeInterval(301.01)))
        XCTAssertEqual(state.activeSession?.attemptTimes.count, 1)
        _ = state.simulateAttempt(sessionID: id, appID: "video", at: now.addingTimeInterval(400))
        XCTAssertNotNil(state.simulateAttempt(sessionID: id, appID: "video", at: now.addingTimeInterval(601.01)))
    }

    func testShortcutAppOpensTriggerOnlyForSelectedAliasesAndContinueExemptsOneAlias() throws {
        var state = SessionDatabase()
        try state.start(title: "Studying", mode: .shortcuts, configuration: .init(),
                        apps: [SelectedApp(id: "video"), SelectedApp(id: "feed"), SelectedApp(id: "forum")], at: now)
        let id = try XCTUnwrap(state.activeSession?.id)
        XCTAssertNil(state.simulateAttempt(sessionID: id, appID: "video", at: now))
        XCTAssertNil(state.recordShortcutAttempt(sessionID: id, appID: "productive", at: now))
        XCTAssertNil(state.recordShortcutAttempt(sessionID: id, appID: "video", at: now))
        XCTAssertNil(state.recordShortcutAttempt(sessionID: id, appID: "feed", at: now.addingTimeInterval(30)))
        let trigger = try XCTUnwrap(state.recordShortcutAttempt(sessionID: id, appID: "forum", at: now.addingTimeInterval(60)))
        XCTAssertEqual(trigger.attemptCount, 3)
        XCTAssertEqual(trigger.appID, "forum")

        XCTAssertTrue(state.decide(sessionID: id, appID: "forum", triggerID: trigger.id,
                                   decision: .continue, at: now.addingTimeInterval(61)))
        XCTAssertNil(state.recordShortcutAttempt(sessionID: id, appID: "forum", at: now.addingTimeInterval(62)))
        XCTAssertNil(state.recordShortcutAttempt(sessionID: id, appID: "video", at: now.addingTimeInterval(122)))
        XCTAssertNil(state.recordShortcutAttempt(sessionID: id, appID: "feed", at: now.addingTimeInterval(123)))
        XCTAssertNotNil(state.recordShortcutAttempt(sessionID: id, appID: "video", at: now.addingTimeInterval(124)))
    }

    func testShortcutBackgroundEventIsNoOpWithoutActiveShortcutSession() throws {
        var state = SessionDatabase()
        XCTAssertNil(state.recordShortcutOpen(appID: "feed", returnURL: "instagram://app", at: now))
        XCTAssertNil(state.activeSession)

        try state.start(title: "Not a Shortcut session", mode: .simulated, configuration: .init(),
                        apps: [SelectedApp(id: "feed")], at: now)
        XCTAssertNil(state.recordShortcutOpen(appID: "feed", returnURL: "instagram://app",
                                              at: now.addingTimeInterval(1)))
    }

    func testShortcutGoBackResetsAllAliasesThenCooldownAllowsNormalCounting() throws {
        var state = SessionDatabase()
        let configuration = SessionConfiguration(attemptThreshold: 3, windowSeconds: 300, cooldownSeconds: 60)
        try state.start(title: "Studying", mode: .shortcuts, configuration: configuration,
                        apps: [SelectedApp(id: "feed"), SelectedApp(id: "video")], at: now)
        let id = try XCTUnwrap(state.activeSession?.id)

        XCTAssertNil(state.recordShortcutOpen(appID: "feed", at: now))
        XCTAssertNil(state.recordShortcutOpen(appID: "video", at: now.addingTimeInterval(1)))
        let firstTrigger = try XCTUnwrap(state.recordShortcutOpen(appID: "feed", at: now.addingTimeInterval(2)))
        XCTAssertTrue(state.decide(sessionID: id, appID: "feed", triggerID: firstTrigger.id,
                                   decision: .goBack, at: now.addingTimeInterval(3)))
        XCTAssertTrue(state.activeSession?.attemptTimes.isEmpty == true)

        for seconds in [4.0, 30, 62.9] {
            XCTAssertNil(state.recordShortcutOpen(appID: "video", at: now.addingTimeInterval(seconds)))
            XCTAssertTrue(state.activeSession?.attemptTimes.isEmpty == true)
        }
        XCTAssertNil(state.recordShortcutOpen(appID: "feed", at: now.addingTimeInterval(63)))
        XCTAssertEqual(state.activeSession?.attemptTimes.count, 1)
        XCTAssertNil(state.recordShortcutOpen(appID: "video", at: now.addingTimeInterval(64)))
        let secondTrigger = try XCTUnwrap(state.recordShortcutOpen(appID: "feed", at: now.addingTimeInterval(65)))
        XCTAssertEqual(secondTrigger.attemptCount, 3)
        XCTAssertEqual(state.activeSession?.triggers.count, 2)
    }

    func testShortcutGoBackTracksFirstSelectedAppReopenDuringCooldown() throws {
        var state = SessionDatabase()
        try state.start(title: "Studying", mode: .shortcuts,
                        configuration: .init(attemptThreshold: 1, cooldownSeconds: 60),
                        apps: [SelectedApp(id: "feed"), SelectedApp(id: "video")], at: now)
        let id = try XCTUnwrap(state.activeSession?.id)
        let trigger = try XCTUnwrap(state.recordShortcutOpen(appID: "feed", at: now))
        XCTAssertTrue(state.decide(sessionID: id, appID: "feed", triggerID: trigger.id,
                                   decision: .goBack, at: now.addingTimeInterval(1)))

        let goBack = try XCTUnwrap(state.activeSession?.decisions.first)
        XCTAssertEqual(goBack.reopenObservationEndsAt,
                       now.addingTimeInterval(1 + ReopenObservation.windowSeconds))
        // This event is suppressed as a new trigger by cooldown, but is still outcome evidence.
        XCTAssertNil(state.recordShortcutOpen(appID: "video", at: now.addingTimeInterval(30)))
        XCTAssertEqual(state.activeSession?.decisions.first?.reopenedAt, now.addingTimeInterval(30))
        XCTAssertEqual(state.activeSession?.triggers.count, 1)
        XCTAssertTrue(state.activeSession?.attemptTimes.isEmpty == true)

        let restored = try JSONDecoder().decode(SessionDatabase.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored.activeSession?.decisions.first?.reopenedAt, now.addingTimeInterval(30))
        state.end(sessionID: id, at: now.addingTimeInterval(181))
        let metrics = SessionMetrics(session: try XCTUnwrap(state.sessions.first))
        XCTAssertEqual(metrics.trackedGoBackCount, 1)
        XCTAssertEqual(metrics.reopenedAfterGoBackCount, 1)
        XCTAssertEqual(metrics.noReopenObservedCount, 0)
        XCTAssertEqual(metrics.incompleteFollowUpCount, 0)
    }

    func testShortcutGoBackFollowUpDistinguishesNoReopenFromIncompleteAndIgnoresLateOpen() throws {
        func stateAfterGoBack() throws -> (SessionDatabase, UUID) {
            var state = SessionDatabase()
            try state.start(title: "Studying", mode: .shortcuts,
                            configuration: .init(attemptThreshold: 1, cooldownSeconds: 0),
                            apps: [SelectedApp(id: "feed")], at: now)
            let id = try XCTUnwrap(state.activeSession?.id)
            let trigger = try XCTUnwrap(state.recordShortcutOpen(appID: "feed", at: now))
            XCTAssertTrue(state.decide(sessionID: id, appID: "feed", triggerID: trigger.id,
                                       decision: .goBack, at: now.addingTimeInterval(1)))
            return (state, id)
        }

        var completed = try stateAfterGoBack()
        completed.0.end(sessionID: completed.1, at: now.addingTimeInterval(181))
        var metrics = SessionMetrics(session: try XCTUnwrap(completed.0.sessions.first))
        XCTAssertEqual(metrics.noReopenObservedCount, 1)
        XCTAssertEqual(metrics.incompleteFollowUpCount, 0)

        var incomplete = try stateAfterGoBack()
        incomplete.0.end(sessionID: incomplete.1, at: now.addingTimeInterval(60))
        // Even when viewed later, observation ceased when the session ended.
        metrics = SessionMetrics(session: try XCTUnwrap(incomplete.0.sessions.first),
                                 asOf: now.addingTimeInterval(600))
        XCTAssertEqual(metrics.noReopenObservedCount, 0)
        XCTAssertEqual(metrics.incompleteFollowUpCount, 1)

        var late = try stateAfterGoBack()
        XCTAssertNotNil(late.0.recordShortcutOpen(appID: "feed", at: now.addingTimeInterval(182)))
        late.0.end(sessionID: late.1, at: now.addingTimeInterval(183))
        metrics = SessionMetrics(session: try XCTUnwrap(late.0.sessions.first))
        XCTAssertEqual(metrics.reopenedAfterGoBackCount, 0)
        XCTAssertEqual(metrics.noReopenObservedCount, 1)
    }

    func testShortcutContinueSuppressesFutureInterventionsAndClearsReturnURL() throws {
        var state = SessionDatabase()
        try state.start(title: "Studying", mode: .shortcuts,
                        configuration: .init(attemptThreshold: 1, cooldownSeconds: 0),
                        apps: [SelectedApp(id: "feed"), SelectedApp(id: "video")], at: now)
        let id = try XCTUnwrap(state.activeSession?.id)
        let trigger = try XCTUnwrap(state.recordShortcutOpen(appID: "feed", returnURL: "instagram://app", at: now))
        XCTAssertEqual(trigger.returnURL, "instagram://app")

        XCTAssertTrue(state.decide(sessionID: id, appID: "feed", triggerID: trigger.id,
                                   decision: .continue, at: now.addingTimeInterval(1)))
        XCTAssertNil(state.activeSession?.triggers.first?.returnURL)
        XCTAssertNil(state.recordShortcutOpen(appID: "feed", returnURL: "instagram://app",
                                              at: now.addingTimeInterval(2)))
        XCTAssertNotNil(state.recordShortcutOpen(appID: "video", at: now.addingTimeInterval(3)))
    }

    func testExpiredShortcutSessionDoesNotReturnAnIntervention() throws {
        var state = SessionDatabase()
        let session = try state.start(title: "Short session", mode: .shortcuts,
                                      configuration: .init(durationMinutes: 15, attemptThreshold: 1),
                                      apps: [SelectedApp(id: "feed")], at: now)
        XCTAssertNil(state.recordShortcutOpen(appID: "feed", at: session.scheduledEnd))
        XCTAssertNil(state.activeSession)
        XCTAssertTrue(state.sessions[0].triggers.isEmpty)
    }

    func testCooldownAndDoubleDecision() throws {
        var state = try makeSession()
        let id = try XCTUnwrap(state.activeSession?.id)
        let trigger = try XCTUnwrap(state.simulateAttempt(sessionID: id, appID: "video", at: now, force: true))
        XCTAssertTrue(state.decide(sessionID: id, appID: "video", triggerID: trigger.id, decision: .goBack, at: now))
        XCTAssertFalse(state.decide(sessionID: id, appID: "video", triggerID: trigger.id, decision: .continue, at: now))
        for seconds in [1.0, 2, 59.9] {
            XCTAssertNil(state.simulateAttempt(sessionID: id, appID: "video", at: now.addingTimeInterval(seconds)))
        }
        XCTAssertEqual(state.activeSession?.attemptTimes.count, 0)
        for seconds in [60.0, 61] {
            XCTAssertNil(state.simulateAttempt(sessionID: id, appID: "video", at: now.addingTimeInterval(seconds)))
        }
        XCTAssertNotNil(state.simulateAttempt(sessionID: id, appID: "video", at: now.addingTimeInterval(62)))
        XCTAssertEqual(state.activeSession?.decisions.count, 1)
    }

    func testContinueExemptsOnlyChosenAppAndDoesNotLeakToNextSession() throws {
        var state = try makeSession(mode: .deviceActivity)
        let id = try XCTUnwrap(state.activeSession?.id)
        XCTAssertTrue(state.activeSession!.shieldedAppIDs(at: now).isEmpty)
        XCTAssertTrue(state.reachUsageThreshold(sessionID: id, at: now.addingTimeInterval(60)))
        let trigger = try XCTUnwrap(state.activeSession?.triggers.first)
        XCTAssertEqual(state.activeSession!.shieldedAppIDs(at: now.addingTimeInterval(60)), ["video", "feed"])
        XCTAssertTrue(state.decide(sessionID: id, appID: "video", triggerID: trigger.id, decision: .continue, at: now.addingTimeInterval(61)))
        XCTAssertEqual(state.activeSession!.shieldedAppIDs(at: now.addingTimeInterval(62)), ["feed"])
        XCTAssertTrue(state.decide(sessionID: id, appID: "feed", triggerID: trigger.id, decision: .goBack, at: now.addingTimeInterval(63)))
        XCTAssertEqual(state.activeSession!.shieldedAppIDs(at: now.addingTimeInterval(64)), ["feed"])
        state.end(sessionID: id, at: now.addingTimeInterval(65))
        XCTAssertTrue(state.sessions[0].apps.allSatisfy { $0.tokenData == nil })
        XCTAssertTrue(state.sessions[0].shieldedAppIDs(at: now.addingTimeInterval(66)).isEmpty)
        let next = try state.start(title: "Next", mode: .deviceActivity, configuration: .init(), apps: apps, at: now.addingTimeInterval(70))
        XCTAssertTrue(next.allowedAppIDs.isEmpty)
        XCTAssertFalse(state.reachUsageThreshold(sessionID: id, at: now.addingTimeInterval(71)))
        XCTAssertTrue(state.reachUsageThreshold(sessionID: next.id, at: now.addingTimeInterval(130)))
        XCTAssertEqual(state.activeSession!.shieldedAppIDs(at: now.addingTimeInterval(130)), ["video", "feed"])
    }

    func testDuplicateThresholdAndUnknownAppDecisionAreIgnored() throws {
        var state = try makeSession(mode: .deviceActivity)
        let id = try XCTUnwrap(state.activeSession?.id)
        XCTAssertTrue(state.reachUsageThreshold(sessionID: id, at: now))
        XCTAssertFalse(state.reachUsageThreshold(sessionID: id, at: now))
        let trigger = try XCTUnwrap(state.activeSession?.triggers.first)
        XCTAssertFalse(state.decide(sessionID: id, appID: "docs", triggerID: trigger.id, decision: .continue, at: now))
        let request = UUID()
        XCTAssertTrue(state.decide(sessionID: id, appID: "video", triggerID: trigger.id, decision: .goBack, at: now, requestID: request))
        XCTAssertFalse(state.decide(sessionID: id, appID: "video", triggerID: trigger.id, decision: .goBack, at: now, requestID: request))
        XCTAssertEqual(state.activeSession?.decisions.count, 1)
    }

    func testExpiredSessionCannotShieldOrAcceptDecision() throws {
        var state = try makeSession(mode: .deviceActivity)
        let session = try XCTUnwrap(state.activeSession)
        _ = state.reachUsageThreshold(sessionID: session.id, at: now)
        let trigger = try XCTUnwrap(state.activeSession?.triggers.first)
        XCTAssertTrue(state.activeSession!.shieldedAppIDs(at: session.scheduledEnd).isEmpty)
        XCTAssertFalse(state.decide(sessionID: session.id, appID: "video", triggerID: trigger.id, decision: .continue, at: session.scheduledEnd))
        XCTAssertNil(state.activeSession)
        XCTAssertEqual(state.sessions[0].endedAt, session.scheduledEnd)
        XCTAssertFalse(state.reachUsageThreshold(sessionID: session.id, at: session.scheduledEnd.addingTimeInterval(10)))
    }

    func testCancellationAndStaleEndCannotAffectNewSession() throws {
        var state = try makeSession(mode: .deviceActivity)
        let old = try XCTUnwrap(state.activeSession)
        state.end(sessionID: old.id, status: .cancelled, at: now.addingTimeInterval(1))
        let next = try state.start(title: "Next", mode: .deviceActivity, configuration: .init(), apps: apps, at: now.addingTimeInterval(2))
        state.end(sessionID: old.id, at: now.addingTimeInterval(3))
        XCTAssertEqual(state.activeSession?.id, next.id)
        XCTAssertFalse(state.reachUsageThreshold(sessionID: old.id, at: now.addingTimeInterval(4)))
    }

    func testInvalidConfigurationSelectionAndSecondSessionRejected() throws {
        var state = SessionDatabase()
        XCTAssertThrowsError(try state.start(title: "", mode: .simulated, configuration: .init(), apps: [], at: now))
        for config in [SessionConfiguration(durationMinutes: 14), .init(usageThresholdSeconds: 0), .init(attemptThreshold: 0), .init(windowSeconds: -1), .init(cooldownSeconds: -1)] {
            XCTAssertThrowsError(try state.start(title: "", mode: .simulated, configuration: config, apps: apps, at: now))
        }
        try state.start(title: "  ", mode: .simulated, configuration: .init(), apps: apps, at: now)
        XCTAssertEqual(state.activeSession?.title, "Studying")
        XCTAssertThrowsError(try state.start(title: "Next", mode: .simulated, configuration: .init(), apps: apps, at: now))
    }

    func testMetricsDistinguishTriggersFromAnswersAndRatingsValidate() throws {
        var state = try makeSession(mode: .deviceActivity)
        let id = try XCTUnwrap(state.activeSession?.id)
        XCTAssertNil(SessionMetrics(session: state.activeSession!).goBackFraction)
        _ = state.reachUsageThreshold(sessionID: id, at: now)
        let trigger = try XCTUnwrap(state.activeSession?.triggers.first)
        _ = state.decide(sessionID: id, appID: "video", triggerID: trigger.id, decision: .goBack, at: now)
        _ = state.decide(sessionID: id, appID: "video", triggerID: trigger.id, decision: .continue,
                         at: now, continueReason: .takingBreak)
        let metrics = SessionMetrics(session: state.activeSession!)
        XCTAssertEqual(metrics.triggerCount, 1)
        XCTAssertEqual(metrics.decisionCount, 2)
        XCTAssertEqual(metrics.goBackFraction, 0.5)
        XCTAssertEqual(metrics.continueFraction, 0.5)
        XCTAssertEqual(metrics.continueReasonCounts[.takingBreak], 1)
        XCTAssertFalse(metrics.reopenTrackingAvailable)
        XCTAssertEqual(metrics.trackedGoBackCount, 0)
        XCTAssertThrowsError(try state.rate(sessionID: id, usefulness: 5, annoyance: 1))
        state.end(sessionID: id, at: now)
        XCTAssertThrowsError(try state.rate(sessionID: id, usefulness: 0, annoyance: 1))
        try state.rate(sessionID: id, usefulness: 5, annoyance: 1)
        XCTAssertEqual(state.sessions[0].ratings?.usefulness, 5)
    }

    func testContinueReasonIsStoredAndGoBackDoesNotRecordAReason() throws {
        var state = try makeSession()
        let id = try XCTUnwrap(state.activeSession?.id)
        let first = try XCTUnwrap(state.simulateAttempt(sessionID: id, appID: "video", at: now, force: true))
        XCTAssertTrue(state.decide(sessionID: id, appID: "video", triggerID: first.id,
                                   decision: .continue, at: now, continueReason: .needSomething))
        let second = try XCTUnwrap(state.simulateAttempt(sessionID: id, appID: "feed",
                                                         at: now.addingTimeInterval(1), force: true))
        XCTAssertTrue(state.decide(sessionID: id, appID: "feed", triggerID: second.id,
                                   decision: .goBack, at: now.addingTimeInterval(1), continueReason: .browsing))

        let restored = try JSONDecoder().decode(SessionDatabase.self, from: JSONEncoder().encode(state))
        let decisions = try XCTUnwrap(restored.sessions.first?.decisions)
        XCTAssertEqual(decisions[0].continueReason, .needSomething)
        XCTAssertNil(decisions[1].continueReason)
    }

    func testLegacyDecisionWithoutReopenFieldsStillDecodes() throws {
        let legacy = #"{"id":"00000000-0000-0000-0000-000000000001","triggerID":"00000000-0000-0000-0000-000000000002","appID":"feed","timestamp":1800000000,"decision":"goBack"}"#
        let decoded = try JSONDecoder().decode(DecisionRecord.self, from: Data(legacy.utf8))
        XCTAssertNil(decoded.continueReason)
        XCTAssertNil(decoded.reopenObservationEndsAt)
        XCTAssertNil(decoded.reopenedAt)
    }

    func testSimulationCannotSpoofDeviceModeAndClockGoingBackIsIgnored() throws {
        var real = try makeSession(mode: .deviceActivity)
        let id = real.activeSession!.id
        XCTAssertNil(real.simulateAttempt(sessionID: id, appID: "video", at: now, force: true))
        var demo = try makeSession()
        let demoID = demo.activeSession!.id
        XCTAssertFalse(demo.reachUsageThreshold(sessionID: demoID, at: now))
        _ = demo.simulateAttempt(sessionID: demoID, appID: "video", at: now.addingTimeInterval(10))
        _ = demo.simulateAttempt(sessionID: demoID, appID: "video", at: now.addingTimeInterval(5))
        XCTAssertEqual(demo.activeSession?.attemptTimes.count, 1)
    }
}
