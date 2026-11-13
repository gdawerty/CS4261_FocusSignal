import XCTest
@testable import FocusSignalCore

final class SessionExporterTests: XCTestCase {
    func testCSVExportsInterventionsMetricsAndSessionMetadata() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var database = SessionDatabase()
        try database.start(title: "Study", mode: .shortcuts, configuration: .init(),
                           experimentCondition: .everyOpen, participantCode: "P,01",
                           apps: [SelectedApp(id: "feed")], at: start)
        let sessionID = try XCTUnwrap(database.activeSession?.id)
        let trigger = try XCTUnwrap(database.recordShortcutOpen(appID: "feed", at: start))
        XCTAssertTrue(database.reportIntent(sessionID: sessionID, triggerID: trigger.id,
                                            intent: .intentional, at: start.addingTimeInterval(0.5)))
        XCTAssertTrue(database.decide(sessionID: sessionID, appID: "feed", triggerID: trigger.id,
                                      decision: .goBack, at: start.addingTimeInterval(1)))
        database.end(sessionID: sessionID, at: start.addingTimeInterval(181))
        try database.rate(sessionID: sessionID, usefulness: 5, annoyance: 2)

        let csv = SessionCSVExporter.csv(sessions: database.sessions)
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("reported_intent"))
        XCTAssertTrue(lines[0].contains("false_positive_rate"))
        XCTAssertTrue(lines[0].contains("session_ended_early"))
        XCTAssertTrue(lines[1].contains("\"P,01\""))
        XCTAssertTrue(lines[1].contains("everyOpen"))
        XCTAssertTrue(lines[1].contains("intentional"))
        XCTAssertTrue(lines[1].contains("goBack"))
        XCTAssertTrue(lines[1].contains("no_reopen_observed"))
        XCTAssertTrue(lines[1].contains("true"))
        XCTAssertTrue(lines[1].contains("1.0"))
        XCTAssertTrue(lines[1].hasSuffix(",5,2"))
    }

    func testCSVIncludesSessionsWithoutInterventionsAndProtectsFormulaCells() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var database = SessionDatabase()
        try database.start(title: "Study", mode: .shortcuts, configuration: .init(),
                           experimentCondition: .behaviorTriggered, participantCode: "=1+1",
                           apps: [SelectedApp(id: "feed")], at: date)
        let id = try XCTUnwrap(database.activeSession?.id)
        database.end(sessionID: id, at: date.addingTimeInterval(15))

        let csv = SessionCSVExporter.csv(sessions: database.sessions)
        XCTAssertTrue(csv.contains("session_without_interventions"))
        XCTAssertTrue(csv.contains("'=1+1"))
    }
}
