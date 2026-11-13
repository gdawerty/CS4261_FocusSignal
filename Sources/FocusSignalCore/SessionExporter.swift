import Foundation

/// Produces a spreadsheet-friendly, one-row-per-intervention CSV from local session records.
public enum SessionCSVExporter {
    private static let columns = [
        "row_type", "participant_code", "session_id", "session_mode", "condition",
        "session_start", "session_end", "session_duration_seconds", "session_ended_early",
        "intervention_count", "trigger_index", "trigger_id", "trigger_time", "attempt_count",
        "reported_intent", "decision", "continue_reason", "go_back_rate", "continue_rate",
        "intentional_intervention_count", "distracting_intervention_count", "false_positive_rate",
        "reopen_within_3m", "reopened_at", "reopen_rate", "usefulness", "annoyance"
    ]

    public static func csv(sessions: [FocusSession], asOf date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var rows = [columns]

        for session in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            let metrics = SessionMetrics(session: session, asOf: date)
            let triggers = session.triggers.sorted {
                $0.timestamp == $1.timestamp ? $0.id.uuidString < $1.id.uuidString : $0.timestamp < $1.timestamp
            }
            let end = session.endedAt.map(formatter.string(from:)) ?? ""
            let duration = metrics.sessionDurationSeconds.map { String(Int($0.rounded())) } ?? ""
            let endedEarly = session.endedAt.map { String($0 < session.scheduledEnd) } ?? ""
            let condition = session.experimentCondition?.rawValue
                ?? (session.mode == .shortcuts ? "legacy_unassigned" : "not_applicable")

            if triggers.isEmpty {
                rows.append(makeRow(
                    rowType: "session_without_interventions", session: session, condition: condition,
                    formatter: formatter, end: end, duration: duration, endedEarly: endedEarly,
                    interventionCount: metrics.triggerCount, metrics: metrics, date: date
                ))
                continue
            }

            for (offset, trigger) in triggers.enumerated() {
                let decision = session.decisions.first { $0.triggerID == trigger.id }
                rows.append(makeRow(
                    rowType: "intervention", session: session, condition: condition,
                    formatter: formatter, end: end, duration: duration, endedEarly: endedEarly,
                    interventionCount: metrics.triggerCount, triggerIndex: offset + 1,
                    trigger: trigger, decision: decision, metrics: metrics, date: date
                ))
            }
        }

        return rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    private static func makeRow(rowType: String, session: FocusSession, condition: String,
                                formatter: ISO8601DateFormatter, end: String, duration: String,
                                endedEarly: String, interventionCount: Int, triggerIndex: Int? = nil,
                                trigger: TriggerRecord? = nil, decision: DecisionRecord? = nil,
                                metrics: SessionMetrics, date: Date) -> [String] {
        let reopenStatus: String
        if let decision, decision.decision == .goBack,
           let observationEndsAt = decision.reopenObservationEndsAt {
            if decision.reopenedAt != nil {
                reopenStatus = "reopened"
            } else if (session.endedAt ?? date) >= observationEndsAt {
                reopenStatus = "no_reopen_observed"
            } else {
                reopenStatus = "incomplete"
            }
        } else {
            reopenStatus = ""
        }

        let participantCode = session.participantCode ?? ""
        let sessionMode = session.mode.rawValue
        let start = formatter.string(from: session.startedAt)
        let interventionCountValue = String(interventionCount)
        let triggerIndexValue = triggerIndex.map { String($0) } ?? ""
        let triggerID = trigger.map { $0.id.uuidString } ?? ""
        let triggerTime = trigger.map { formatter.string(from: $0.timestamp) } ?? ""
        let attemptCount = trigger?.attemptCount.map { String($0) } ?? ""
        let reportedIntent = trigger?.reportedIntent?.rawValue ?? ""
        let decisionValue = decision?.decision.rawValue ?? ""
        let continueReason = decision?.continueReason?.rawValue ?? ""
        let goBackRate = metrics.goBackFraction.map { String($0) } ?? ""
        let continueRate = metrics.continueFraction.map { String($0) } ?? ""
        let intentionalCount = String(metrics.intentionalInterventionCount)
        let distractingCount = String(metrics.distractingInterventionCount)
        let falsePositiveRate = metrics.falsePositiveRate.map { String($0) } ?? ""
        let reopenedAt = decision?.reopenedAt.map { formatter.string(from: $0) } ?? ""
        let reopenRate = metrics.reopenRate.map { String($0) } ?? ""
        let usefulness = session.ratings.map { String($0.usefulness) } ?? ""
        let annoyance = session.ratings.map { String($0.annoyance) } ?? ""

        let row: [String] = [
            rowType,
            participantCode,
            session.id.uuidString,
            sessionMode,
            condition,
            start,
            end,
            duration,
            endedEarly,
            interventionCountValue,
            triggerIndexValue,
            triggerID,
            triggerTime,
            attemptCount,
            reportedIntent,
            decisionValue,
            continueReason,
            goBackRate,
            continueRate,
            intentionalCount,
            distractingCount,
            falsePositiveRate,
            reopenStatus,
            reopenedAt,
            reopenRate,
            usefulness,
            annoyance
        ]
        return row
    }

    private static func escape(_ value: String) -> String {
        let needsFormulaProtection = value.first.map { "=+-@\t\r".contains($0) } ?? false
        let safeValue = needsFormulaProtection ? "'" + value : value
        guard safeValue.contains(",") || safeValue.contains("\"") || safeValue.contains("\n") || safeValue.contains("\r") else {
            return safeValue
        }
        return "\"" + safeValue.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
