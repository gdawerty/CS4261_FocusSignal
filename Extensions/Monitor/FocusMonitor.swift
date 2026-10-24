import DeviceActivity
import os

final class FocusMonitor: DeviceActivityMonitor {
    private let logger = Logger(subsystem: "FocusSignal", category: "Monitor")

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        do { try ScreenTimeRuntime(forExtension: true).handleThreshold(activity: activity, event: event) }
        catch { logger.error("Threshold handling failed; no app tokens or session data logged.") }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        do { try ScreenTimeRuntime(forExtension: true).handleIntervalEnd(activity: activity) }
        catch { logger.error("Session cleanup failed; retry by opening FocusSignal.") }
    }
}
