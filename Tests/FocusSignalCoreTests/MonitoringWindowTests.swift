import XCTest
@testable import FocusSignalCore

final class MonitoringWindowTests: XCTestCase {
    func testCrossMidnightUsesFullDateAndIncludesExactMinimum() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 23, minute: 55, second: 12))!
        var database = SessionDatabase()
        let session = try database.start(title: "Night", mode: .deviceActivity, configuration: .init(durationMinutes: 15), apps: [.init(id: "a")], at: now)
        let window = try MonitoringWindow(session: session, calendar: calendar)
        XCTAssertEqual(window.start.day, 21)
        XCTAssertEqual(window.end.day, 22)
        XCTAssertEqual(window.end.hour, 0)
        XCTAssertEqual(window.end.minute, 10)
        XCTAssertEqual(calendar.date(from: window.end)!.timeIntervalSince(calendar.date(from: window.start)!), 900)
        XCTAssertEqual(window.start.timeZone, calendar.timeZone)
    }

    func testEmptySelectionCannotBecomeAnAllAppsMonitor() throws {
        var database = SessionDatabase()
        var session = try database.start(title: "Test", mode: .deviceActivity, configuration: .init(), apps: [.init(id: "a")], at: Date())
        session.apps = []
        XCTAssertThrowsError(try MonitoringWindow(session: session))
    }

    func testPersistenceRetainsContinueExemptionAndPendingDemo() throws {
        var database = SessionDatabase()
        let now = Date()
        let session = try database.start(title: "Test", mode: .simulated, configuration: .init(cooldownSeconds: 0), apps: [.init(id: "a"), .init(id: "b")], at: now)
        let first = try XCTUnwrap(database.simulateAttempt(sessionID: session.id, appID: "a", at: now, force: true))
        XCTAssertTrue(database.decide(sessionID: session.id, appID: "a", triggerID: first.id, decision: .continue, at: now))
        _ = database.simulateAttempt(sessionID: session.id, appID: "b", at: now, force: true)
        var restored = try JSONDecoder().decode(SessionDatabase.self, from: JSONEncoder().encode(database))
        XCTAssertEqual(restored.activeSession?.allowedAppIDs, ["a"])
        XCTAssertEqual(restored.activeSession?.pendingTrigger?.appID, "b")
        let second = try XCTUnwrap(restored.activeSession?.pendingTrigger)
        XCTAssertFalse(restored.decide(sessionID: session.id, appID: "a", triggerID: second.id, decision: .continue, at: now))
        XCTAssertTrue(restored.decide(sessionID: session.id, appID: "b", triggerID: second.id, decision: .goBack, at: now))
    }
}
