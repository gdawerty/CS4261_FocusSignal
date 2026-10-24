import Foundation
import Darwin

/// Small prototype store. Every read/modify/write is covered by an advisory process lock,
/// including applying the derived shield after a commit. Atomic replacement alone does NOT
/// protect read/modify/write transactions; flock prevents lost updates from extension processes.
public final class LocalStore {
    public let directory: URL
    private var dataURL: URL { directory.appendingPathComponent("sessions.json") }
    private var lockURL: URL { directory.appendingPathComponent("sessions.lock") }

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                             ofItemAtPath: directory.path)
        #endif
    }

    public func read() throws -> SessionDatabase { try locked { try readUnlocked() } }

    /// afterCommit runs under the same lock to prevent a late extension write from reapplying
    /// a shield after the main app has ended the session. Never call DeviceActivityCenter here:
    /// its system callbacks may themselves need this lock.
    @discardableResult
    public func transaction<T>(_ update: (inout SessionDatabase) throws -> T,
                               afterCommit: (SessionDatabase) throws -> Void = { _ in }) throws -> T {
        try locked {
            var database = try readUnlocked()
            let previous = database
            let result = try update(&database)
            if database != previous { try writeUnlocked(database) }
            try afterCommit(database)
            return result
        }
    }

    /// Explicit reset also recovers from corrupt/unsupported data. Keep the lock file in place:
    /// unlinking it while another process waits would create two independent locks.
    public func reset(afterCommit: (SessionDatabase) throws -> Void = { _ in }) throws {
        try locked {
            let empty = SessionDatabase()
            try writeUnlocked(empty)
            try afterCommit(empty)
        }
    }

    private func readUnlocked() throws -> SessionDatabase {
        guard FileManager.default.fileExists(atPath: dataURL.path) else { return SessionDatabase() }
        let bytes = try Data(contentsOf: dataURL)
        let state: SessionDatabase
        do { state = try JSONDecoder().decode(SessionDatabase.self, from: bytes) }
        catch { throw FocusError.corruptStore }
        guard state.schemaVersion == 1 else { throw FocusError.unsupportedVersion }
        return state
    }

    private func writeUnlocked(_ state: SessionDatabase) throws {
        let bytes = try JSONEncoder().encode(state)
        #if os(iOS)
        try bytes.write(to: dataURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try bytes.write(to: dataURL, options: .atomic)
        #endif
    }

    private func locked<T>(_ operation: () throws -> T) throws -> T {
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw FocusError.lockFailed }
        defer { close(descriptor) }
        // Avoid holding an extension indefinitely. Contention normally lasts only milliseconds.
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard (errno == EWOULDBLOCK || errno == EINTR), ProcessInfo.processInfo.systemUptime < deadline else {
                throw FocusError.lockFailed
            }
            usleep(5_000)
        }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }
}
