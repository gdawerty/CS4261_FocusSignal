import Foundation

/// Absolute calendar endpoints keep a session from accidentally recurring tomorrow or crossing
/// midnight incorrectly. Tests exercise this without needing Screen Time permission.
public struct MonitoringWindow {
    public let start: DateComponents
    public let end: DateComponents

    public init(session: FocusSession, calendar: Calendar = .current) throws {
        guard session.mode == .deviceActivity, !session.apps.isEmpty,
              session.scheduledEnd.timeIntervalSince(session.startedAt) >= 900 else {
            throw FocusError.invalidConfiguration
        }
        func components(_ date: Date) -> DateComponents {
            var result = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            result.calendar = calendar
            result.timeZone = calendar.timeZone
            return result
        }
        start = components(session.startedAt)
        end = components(session.scheduledEnd)
    }
}
