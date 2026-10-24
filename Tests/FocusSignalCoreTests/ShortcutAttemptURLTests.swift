import XCTest
@testable import FocusSignalCore

final class ShortcutAttemptURLTests: XCTestCase {
    func testBuildsAndParsesPerAppAutomationURL() throws {
        let url = try XCTUnwrap(ShortcutAttemptURL.make(appID: "video"))
        XCTAssertEqual(url.absoluteString, "focussignal://attempt?app=video")
        XCTAssertEqual(ShortcutAttemptURL.appID(from: url), "video")

        let personalTeamURL = try XCTUnwrap(ShortcutAttemptURL.make(
            appID: "feed", scheme: ShortcutAttemptURL.shortcutDemoScheme
        ))
        XCTAssertEqual(personalTeamURL.absoluteString, "focussignal-shortcuts://attempt?app=feed")
        XCTAssertEqual(ShortcutAttemptURL.appID(from: personalTeamURL), "feed")
    }

    func testRejectsMalformedAndUntrustedURLs() {
        for raw in [
            "https://attempt?app=video",
            "focussignal-other://attempt?app=video",
            "focussignal://other?app=video",
            "focussignal://attempt",
            "focussignal://attempt?app=video&app=feed",
            "focussignal://user@attempt?app=video",
            "focussignal://attempt/path?app=video",
            "focussignal://attempt?app=video#fragment",
            "focussignal://attempt?app=../video",
            "focussignal://attempt?app="
        ] {
            XCTAssertNil(ShortcutAttemptURL.appID(from: URL(string: raw)!), "Accepted unexpected URL: \(raw)")
        }
        XCTAssertNil(ShortcutAttemptURL.make(appID: "bad/app"))
        XCTAssertNil(ShortcutAttemptURL.make(appID: "video", scheme: "https"))
    }

    func testInterventionURLCarriesOnlyTheExactPendingTriggerIDs() throws {
        let sessionID = UUID()
        let triggerID = UUID()
        let url = try XCTUnwrap(ShortcutInterventionURL.make(sessionID: sessionID, triggerID: triggerID))

        XCTAssertEqual(url.scheme, "focussignal-shortcuts")
        XCTAssertEqual(ShortcutInterventionURL.route(from: url),
                       ShortcutInterventionRoute(sessionID: sessionID, triggerID: triggerID))
        XCTAssertNil(ShortcutAttemptURL.appID(from: url), "An intervention URL must not count another app open")
    }

    func testInterventionURLHasStableBooleanShortcutDestination() throws {
        let url = try XCTUnwrap(ShortcutInterventionURL.make())
        XCTAssertEqual(url.absoluteString, "focussignal-shortcuts://intervention")
        XCTAssertEqual(ShortcutInterventionURL.route(from: url), ShortcutInterventionRoute())
        XCTAssertNil(ShortcutAttemptURL.appID(from: url), "Opening an intervention must not count another app open")
    }

    func testInterventionURLRejectsMalformedAndDuplicateParameters() {
        for raw in [
            "focussignal-shortcuts://attempt?session=00000000-0000-0000-0000-000000000001&trigger=00000000-0000-0000-0000-000000000002",
            "focussignal-shortcuts://intervention?session=bad&trigger=00000000-0000-0000-0000-000000000002",
            "focussignal-shortcuts://intervention?session=00000000-0000-0000-0000-000000000001&trigger=00000000-0000-0000-0000-000000000002&trigger=00000000-0000-0000-0000-000000000003",
            "focussignal-shortcuts://intervention/path?session=00000000-0000-0000-0000-000000000001&trigger=00000000-0000-0000-0000-000000000002"
        ] {
            XCTAssertNil(ShortcutInterventionURL.route(from: URL(string: raw)!))
        }
    }

    func testReturnURLValidationAcceptsInstagramCandidateAndRejectsFocusSignalLoop() {
        XCTAssertEqual(ShortcutReturnURL.canonicalString("instagram://app"), "instagram://app")
        XCTAssertEqual(ShortcutReturnURL.canonicalString("https://www.instagram.com/"),
                       "https://www.instagram.com/")
        XCTAssertNil(ShortcutReturnURL.canonicalString("focussignal-shortcuts://intervention"))
        XCTAssertNil(ShortcutReturnURL.canonicalString("javascript:alert(1)"))
        XCTAssertNil(ShortcutReturnURL.canonicalString("https:///missing-host"))
        XCTAssertNil(ShortcutReturnURL.canonicalString(String(repeating: "a", count: 2_049)))
    }
}
