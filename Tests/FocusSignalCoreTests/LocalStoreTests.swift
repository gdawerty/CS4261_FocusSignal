import XCTest
@testable import FocusSignalCore

final class LocalStoreTests: XCTestCase {
    var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("FocusSignalTests-\(UUID())")
    }
    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    func testPersistsAcrossStoreInstancesAndResetKeepsLock() throws {
        let first = try LocalStore(directory: directory)
        let session = try first.transaction {
            try $0.start(title: "Test", mode: .simulated, configuration: .init(), apps: [.init(id: "a")], at: Date())
        }
        let second = try LocalStore(directory: directory)
        XCTAssertEqual(try second.read().activeSession?.id, session.id)
        try second.reset()
        XCTAssertTrue(try first.read().sessions.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("sessions.lock").path))
    }

    func testFailedMutationDoesNotCommit() throws {
        let store = try LocalStore(directory: directory)
        XCTAssertThrowsError(try store.transaction { database in
            database.schemaVersion = 999
            throw FocusError.invalidConfiguration
        })
        XCTAssertEqual(try store.read().schemaVersion, 1)
    }

    func testCorruptAndFutureDataArePreservedUntilExplicitReset() throws {
        let store = try LocalStore(directory: directory)
        let path = directory.appendingPathComponent("sessions.json")
        let corrupt = Data("not valid json".utf8)
        try corrupt.write(to: path)
        XCTAssertThrowsError(try store.read()) { XCTAssertEqual($0 as? FocusError, .corruptStore) }
        XCTAssertThrowsError(try store.transaction { $0.expire(at: Date()) })
        XCTAssertEqual(try Data(contentsOf: path), corrupt)
        try store.reset()
        var future = SessionDatabase()
        future.schemaVersion = 2
        try JSONEncoder().encode(future).write(to: path)
        XCTAssertThrowsError(try store.read()) { XCTAssertEqual($0 as? FocusError, .unsupportedVersion) }
        try store.reset()
        XCTAssertEqual(try store.read().schemaVersion, 1)
    }

    func testConcurrentWritersDoNotLoseDecisions() throws {
        let store = try LocalStore(directory: directory)
        let now = Date()
        let session = try store.transaction { state in
            let s = try state.start(title: "Concurrent", mode: .deviceActivity, configuration: .init(), apps: [.init(id: "a")], at: now)
            _ = state.reachUsageThreshold(sessionID: s.id, at: now)
            return state.activeSession!
        }
        let trigger = try XCTUnwrap(session.triggers.first)
        let errors = ThreadSafeErrors()
        DispatchQueue.concurrentPerform(iterations: 60) { _ in
            do {
                // Each writer has its own descriptor, as the app and extensions do.
                let writer = try LocalStore(directory: directory)
                try writer.transaction { state in
                    XCTAssertTrue(state.decide(sessionID: session.id, appID: "a", triggerID: trigger.id, decision: .goBack, at: now))
                }
            } catch { errors.append(error) }
        }
        XCTAssertEqual(errors.count, 0)
        XCTAssertEqual(try store.read().activeSession?.decisions.count, 60)
    }

    func testAfterCommitSeesPersistedState() throws {
        let store = try LocalStore(directory: directory)
        var applied: UUID?
        let session = try store.transaction({ state in
            try state.start(title: "Test", mode: .simulated, configuration: .init(), apps: [.init(id: "a")], at: Date())
        }, afterCommit: { state in applied = state.activeSession?.id })
        XCTAssertEqual(applied, session.id)
        XCTAssertEqual(try store.read().activeSession?.id, applied)
    }
}

private final class ThreadSafeErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Error] = []
    func append(_ error: Error) { lock.lock(); defer { lock.unlock() }; values.append(error) }
    var count: Int { lock.lock(); defer { lock.unlock() }; return values.count }
}
