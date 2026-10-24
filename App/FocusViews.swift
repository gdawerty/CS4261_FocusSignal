import SwiftUI
import Combine
import FamilyControls
import FocusSignalCore

struct FocusRootView: View {
    @ObservedObject var model: SessionViewModel
    @Environment(\.scenePhase) private var scenePhase
    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            if let session = model.active {
                ActiveSessionView(model: model, session: session)
            } else if let session = model.results {
                SessionResultsView(model: model, session: session)
            } else {
                HomeView(model: model)
            }
        }
        .onReceive(refresh) { _ in
            if scenePhase == .active { model.refresh() }
        }
        .sheet(item: Binding(get: { model.active?.pendingTrigger }, set: { _ in })) { trigger in
            FrictionView(model: model, trigger: trigger).interactiveDismissDisabled()
        }
        .onOpenURL { _ = model.handleExternalURL($0) }
        .alert("FocusSignal", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

private struct HomeView: View {
    @ObservedObject var model: SessionViewModel
    @State private var showingSetup = false
    @State private var deleting = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "scope").font(.system(size: 44)).foregroundStyle(.indigo).accessibilityHidden(true)
                    Text("Make room for focus.").font(.largeTitle.bold())
                    Text("Choose the apps that distract you. Get a moment to reconsider when their usage adds up during your study session.")
                        .foregroundStyle(.secondary)
                    Button("Set Up Focus Session") { showingSetup = true }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .accessibilityIdentifier("setupSession").disabled(!model.isReady)
                }.padding(.vertical, 12)
            }
            Section("Your data") {
                Label("Stored only on this device", systemImage: "lock.shield")
                Text("No account, analytics, or cloud sync. Up to 50 sessions are retained; app-selection tokens are removed when a session ends.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !model.database.sessions.isEmpty {
                Section("Recent sessions") {
                    ForEach(model.database.sessions.reversed()) { session in
                        Button { model.presentedResultsID = session.id } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.title).foregroundStyle(.primary)
                                Text("\(session.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(session.mode == .simulated ? "Demo" : session.mode == .shortcuts ? "Shortcuts" : "Device")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section {
                Button("Delete All Local Data", role: .destructive) { deleting = true }
                    .accessibilityIdentifier("deleteAllData")
            }
        }
        .navigationTitle("FocusSignal")
        .sheet(isPresented: $showingSetup) {
            NavigationStack { FocusSetupView(model: model) }
        }
        .confirmationDialog("Delete all sessions and ratings?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete All Data", role: .destructive) { model.deleteAll() }
        } message: { Text("This cannot be undone. Any FocusSignal restrictions will be removed.") }
    }
}

private struct FocusSetupView: View {
    @ObservedObject var model: SessionViewModel
    @ObservedObject private var authorization = AuthorizationCenter.shared
    @Environment(\.dismiss) private var dismiss
    @State private var title = "Studying"
    @State private var mode = ScreenTimeRuntime.isShortcutDemoBuild ? TriggerMode.shortcuts : .simulated
    @State private var configuration = SessionConfiguration()
    @State private var selection = FamilyActivitySelection(includeEntireCategory: false)
    @State private var demoAppIDs = Set(SessionViewModel.demoApps.map(\.id))
    @State private var picking = false
    var body: some View {
        Form {
            Section("Session") {
                TextField("What are you focusing on?", text: $title).accessibilityIdentifier("sessionTitle")
                if model.isShortcutDemoBuild {
                    Label("Shortcuts app-open prototype", systemImage: "arrowshape.turn.up.right")
                        .accessibilityIdentifier("sessionMode")
                } else {
                    Picker("Mode", selection: $mode) {
                        Text("Demo").tag(TriggerMode.simulated)
                        Text("Shortcuts").tag(TriggerMode.shortcuts)
                        Text("Real device").tag(TriggerMode.deviceActivity)
                    }.pickerStyle(.segmented).accessibilityIdentifier("sessionMode")
                }
                Picker("Session length", selection: $configuration.durationMinutes) {
                    ForEach([15, 30, 45, 60, 90, 120], id: \.self) { Text("\($0) minutes").tag($0) }
                }
            }
            if mode == .shortcuts {
                Section("Shortcuts app-open automations") {
                    Text("Make one App → Is Opened automation per distracting app. Add Record FocusSignal App Open and set that app’s alias and optional return URL. If its result is true, open focussignal-shortcuts://intervention; if false, do nothing. No active session, Continue, and cooldown events return false, so FocusSignal stays closed.")
                    ForEach(SessionViewModel.demoApps, id: \.id) { app in
                        Toggle(app.name, isOn: Binding(get: { demoAppIDs.contains(app.id) }, set: {
                            if $0 { demoAppIDs.insert(app.id) } else { demoAppIDs.remove(app.id) }
                        }))
                        if demoAppIDs.contains(app.id) {
                            Text("Use alias: \(app.id)").font(.caption.monospaced())
                        }
                    }
                    Text("Optional Instagram return URL to try: instagram://app. This is an undocumented app link; verify it on your iPhone. Leave Return URL blank to switch back manually.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Stepper("Trigger after \(configuration.attemptThreshold) opens", value: $configuration.attemptThreshold, in: 2...10)
                    Picker("Look-back window", selection: $configuration.windowSeconds) {
                        Text("1 minute").tag(60.0)
                        Text("5 minutes").tag(300.0)
                        Text("10 minutes").tag(600.0)
                    }
                    Picker("Cooldown after a decision", selection: $configuration.cooldownSeconds) {
                        Text("None").tag(0.0)
                        Text("30 seconds").tag(30.0)
                        Text("60 seconds").tag(60.0)
                    }
                }
            } else if mode == .simulated {
                Section {
                    Text("Demo uses pretend app-open events. It does not track or block other apps.")
                    ForEach(SessionViewModel.demoApps, id: \.id) { app in
                        Toggle(app.name, isOn: Binding(get: { demoAppIDs.contains(app.id) }, set: {
                            if $0 { demoAppIDs.insert(app.id) } else { demoAppIDs.remove(app.id) }
                        }))
                    }
                    Stepper("Trigger after \(configuration.attemptThreshold) attempts", value: $configuration.attemptThreshold, in: 2...10)
                    Picker("Look-back window", selection: $configuration.windowSeconds) {
                        Text("1 minute").tag(60.0)
                        Text("5 minutes").tag(300.0)
                        Text("10 minutes").tag(600.0)
                    }
                    Picker("Cooldown after a decision", selection: $configuration.cooldownSeconds) {
                        Text("None (demo)").tag(0.0)
                        Text("30 seconds").tag(30.0)
                        Text("60 seconds").tag(60.0)
                    }
                } header: { Text("Simulated distracting apps") }
            } else {
                Section("Screen Time access") {
                    if !model.canMonitor {
                        Text("Real mode requires a physical iPhone, Family Controls signing, and an App Group. Demo mode works here without those.")
                    }
                    Label(ScreenTimeRuntime.authorized ? "Access allowed" : "Access needed", systemImage: ScreenTimeRuntime.authorized ? "checkmark.shield" : "hand.raised")
                    Button(model.isAuthorizing ? "Requesting access…" : "Allow Screen Time Access") { Task { await model.authorize() } }
                        .disabled(!model.canMonitor || model.isAuthorizing)
                    Button("Choose Distracting Apps (\(selection.applicationTokens.count))") { picking = true }
                        .disabled(!model.canMonitor || !ScreenTimeRuntime.authorized)
                    if !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty {
                        Text("Remove entire categories and websites. This version supports individual apps only.").foregroundStyle(.red)
                    }
                    ForEach(Array(selection.applicationTokens), id: \.self) { Label($0) }
                }
                Section {
                    Picker("Combined usage threshold", selection: $configuration.usageThresholdSeconds) {
                        Text("30 seconds").tag(30)
                        Text("60 seconds").tag(60)
                        Text("2 minutes").tag(120)
                    }
                    Text("Only selected apps count. Productive apps you leave unselected remain available. Usage before this session is excluded.")
                    Text("One usage threshold is armed for this session. iOS controls the callback and shield timing.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("When to intervene") }
            }
            Section {
                Text(mode == .shortcuts
                     ? "Continue ignores this app alias for the rest of the session. Go Back records your choice; FocusSignal stays open and does not block the other app."
                     : "Continue allows the chosen app for the rest of this session. Go Back leaves the shield in place.")
                    .font(.footnote)
                Button("Start Focus Session") {
                    if model.start(title: title, mode: mode, configuration: configuration, selection: selection, demoAppIDs: demoAppIDs) { dismiss() }
                }.accessibilityIdentifier("startFocusSession")
                    .disabled(mode == .simulated || mode == .shortcuts
                              ? demoAppIDs.isEmpty
                              : (!model.canMonitor || !ScreenTimeRuntime.authorized || selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty))
            }
        }
        .navigationTitle("Set up focus")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .familyActivityPicker(isPresented: $picking, selection: $selection)
    }
}

private struct ActiveSessionView: View {
    @ObservedObject var model: SessionViewModel
    let session: FocusSession
    @State private var cancelling = false
    private var shortcutURLScheme: String {
        model.isShortcutDemoBuild ? ShortcutAttemptURL.shortcutDemoScheme : ShortcutAttemptURL.scheme
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label(session.mode == .simulated ? "Demo session" : session.mode == .shortcuts ? "Shortcuts session" : "Real-device session", systemImage: "circle.dotted")
                        .foregroundStyle(.indigo)
                    Text(session.title).font(.largeTitle.bold()).accessibilityIdentifier("activeSession")
                    Text(timerInterval: session.startedAt...session.scheduledEnd, countsDown: true)
                        .font(.system(size: 42, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("remaining").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical)
            }
            Section("Intervention") {
                if session.mode == .simulated {
                    Text("\(session.configuration.attemptThreshold) selected-app attempts within \(Int(session.configuration.windowSeconds / 60)) minutes")
                    Text("Use the Testing Panel to simulate app opens.").foregroundStyle(.secondary)
                    NavigationLink("Testing Panel") { DeveloperPanel(model: model) }.accessibilityIdentifier("testingPanel")
                } else if session.mode == .shortcuts {
                    Text("\(session.configuration.attemptThreshold) selected app opens within \(Int(session.configuration.windowSeconds / 60)) minutes")
                    Text("The background Shortcut action counts opens without showing FocusSignal. It returns true only at the threshold; the automation then opens the pending intervention. This app does not observe other apps directly or block them.")
                        .font(.footnote).foregroundStyle(.secondary)
                    ForEach(session.apps, id: \.id) { app in
                        Text("Shortcut alias: \(app.id)").font(.caption.monospaced())
                    }
                    if let app = session.apps.first, let url = ShortcutAttemptURL.make(appID: app.id, scheme: shortcutURLScheme) {
                        Link("Send sample event (test; opens FocusSignal)", destination: url)
                            .accessibilityIdentifier("shortcutTestLink")
                    }
                    Text(model.demoFeedback).font(.footnote).accessibilityIdentifier("shortcutFeedback")
                } else {
                    Text(session.triggers.isEmpty ? "Waiting for \(session.configuration.usageThresholdSeconds) seconds of selected-app usage." : "Usage threshold reached. Selected apps are shielded unless you chose Continue.")
                    Text("\(session.apps.count) apps selected · \(session.allowedAppIDs.count) allowed for this session")
                    Text("FocusSignal does not receive a live usage timer or count app opens. A shield can appear while an app is in use; timing is managed by iOS.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                LabeledContent("Trigger episodes", value: "\(session.triggers.count)")
                LabeledContent("Recorded decisions", value: "\(session.decisions.count)")
                NavigationLink("View Event Log") { EventLogView(session: session) }
            }
            Section {
                Button("End Session") { model.end() }.accessibilityIdentifier("endSession")
                Button("Cancel Session", role: .destructive) { cancelling = true }
            }
        }
        .navigationTitle("Focus in progress")
        .confirmationDialog("Cancel this session?", isPresented: $cancelling, titleVisibility: .visible) {
            Button("Cancel Session", role: .destructive) { model.end(cancelled: true) }
        } message: { Text("Your decisions will be kept and FocusSignal’s restrictions removed.") }
    }
}

private struct DeveloperPanel: View {
    @ObservedObject var model: SessionViewModel
    @State private var resetting = false
    var body: some View {
        List {
            Section {
                Text("These buttons generate test events only. They do not open or observe other apps.")
                if let session = model.active {
                    Text("Rule: \(session.configuration.attemptThreshold) attempts / \(Int(session.configuration.windowSeconds)) seconds; cooldown \(Int(session.configuration.cooldownSeconds)) seconds")
                        .font(.footnote).foregroundStyle(.secondary)
                    ForEach(SessionViewModel.demoApps, id: \.id) { app in
                        Button("Simulate \(app.name)") { model.attempt(appID: app.id) }
                            .accessibilityIdentifier("simulate.\(app.id)")
                    }
                    Button("Simulate productive app (ignored)") { model.attempt(appID: "productive") }
                        .accessibilityIdentifier("simulate.productive")
                    Button("Trigger Intervention Now") {
                        if let app = session.apps.first(where: { !session.allowedAppIDs.contains($0.id) }) { model.attempt(appID: app.id, force: true) }
                    }.disabled(session.apps.allSatisfy { session.allowedAppIDs.contains($0.id) })
                        .accessibilityIdentifier("triggerNow")
                    Text("Attempts in current window: \(session.attemptTimes.count)").accessibilityIdentifier("attemptCount")
                    Text("Trigger episodes: \(session.triggers.count)").accessibilityIdentifier("triggerCount")
                    Text(model.demoFeedback).font(.footnote).accessibilityIdentifier("demoFeedback")
                    NavigationLink("View Event Log") { EventLogView(session: session) }
                }
            } header: { Text("Demo controls") }
            Section {
                Text("To change thresholds, cancel this session and start a new one. Each session keeps the rule used for its results.").font(.footnote)
                Button("Reset Session", role: .destructive) { resetting = true }
            }
        }
        .navigationTitle("Testing Panel")
        .confirmationDialog("Reset the current session?", isPresented: $resetting, titleVisibility: .visible) {
            Button("Reset Session", role: .destructive) { model.end(cancelled: true) }
        } message: { Text("This ends the session and keeps its test results.") }
    }
}

private struct FrictionView: View {
    @ObservedObject var model: SessionViewModel
    let trigger: TriggerRecord
    @State private var choosingContinueReason = false
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "scope").font(.system(size: 58)).foregroundStyle(.indigo).accessibilityHidden(true)
            Text(choosingContinueReason ? "Why do you want to continue?" : "Back to your focus?")
                .font(.largeTitle.bold()).multilineTextAlignment(.center).accessibilityIdentifier("frictionTitle")
            Text(choosingContinueReason
                 ? "Choose a reason before FocusSignal returns you to the app."
                 : model.active?.mode == .shortcuts
                    ? "Shortcuts reported repeated opens of a selected distracting app. Do you want to pause or continue?"
                    : "You’ve reached the simulated distraction threshold. Do you want to keep going?")
                .multilineTextAlignment(.center)
            Text(model.active?.mode == .shortcuts ? "Shortcuts event · no other app is blocked" : "Demo intervention · no other app is blocked")
                .font(.caption).foregroundStyle(.secondary)
            if choosingContinueReason {
                ForEach(ContinueReason.allCases, id: \.self) { reason in
                    Button(reason.title) { model.decide(.continue, trigger: trigger, continueReason: reason) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .accessibilityIdentifier("continueReason.\(reason.rawValue)")
                }
                Button("Back to choices") { choosingContinueReason = false }
                    .buttonStyle(.bordered).accessibilityIdentifier("continueReason.cancel")
            } else {
                Button("Go Back") { model.decide(.goBack, trigger: trigger) }
                    .buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("friction.goBack")
                Button("Continue") { choosingContinueReason = true }
                    .buttonStyle(.bordered).controlSize(.large).accessibilityIdentifier("friction.continue")
            }
            Text(model.active?.mode == .shortcuts
                 ? "Continue ignores this app alias until the session ends and returns using the configured app link, if available."
                 : "Continue allows this demo app until the session ends.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(28)
    }
}

private struct SessionResultsView: View {
    @ObservedObject var model: SessionViewModel
    let session: FocusSession
    @State private var usefulness = 3
    @State private var annoyance = 3
    private var metrics: SessionMetrics { .init(session: session) }
    func percentage(_ fraction: Double?) -> String { fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "—" }
    var body: some View {
        List {
            Section {
                Text(session.title).font(.title.bold())
                Text("\(session.mode == .simulated ? "Demo" : session.mode == .shortcuts ? "Shortcuts" : "Device") · \(session.status.rawValue.capitalized)")
                Text("These results measure your choices, not whether you returned to studying.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Session results") {
                LabeledContent("Trigger episodes", value: "\(metrics.triggerCount)").accessibilityIdentifier("results.triggers")
                LabeledContent("Go Back", value: "\(metrics.goBackCount) (\(percentage(metrics.goBackFraction)))").accessibilityIdentifier("results.goBack")
                LabeledContent("Continue", value: "\(metrics.continueCount) (\(percentage(metrics.continueFraction)))").accessibilityIdentifier("results.continue")
                Text("Percentages use recorded decisions. A shield being applied is not counted as a confirmed view. Multiple decisions may follow one usage threshold.")
                    .font(.footnote).foregroundStyle(.secondary)
                NavigationLink("View Event Log") { EventLogView(session: session) }
            }
            if metrics.continueCount > 0 {
                Section("Continue reasons") {
                    ForEach(ContinueReason.allCases, id: \.self) { reason in
                        LabeledContent(reason.title, value: "\(metrics.continueReasonCounts[reason, default: 0])")
                    }
                }
            }
            Section("After Go Back · 3-minute follow-up") {
                if metrics.reopenTrackingAvailable {
                    if metrics.trackedGoBackCount == 0 {
                        Text(metrics.goBackCount == 0
                             ? "No Shortcut Go Back decisions were recorded."
                             : "No follow-up data is available for this session’s Go Back decisions.")
                    } else {
                        if metrics.trackedGoBackCount < metrics.goBackCount {
                            Text("Follow-up was recorded for \(metrics.trackedGoBackCount) of \(metrics.goBackCount) Go Back decisions; older decisions may not include it.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        LabeledContent("Go Back decisions tracked", value: "\(metrics.trackedGoBackCount)")
                        LabeledContent("Reopened (reported)", value: "\(metrics.reopenedAfterGoBackCount)")
                            .accessibilityIdentifier("results.reopened")
                        LabeledContent("No reopen observed", value: "\(metrics.noReopenObservedCount)")
                            .accessibilityIdentifier("results.noReopen")
                        LabeledContent("Incomplete follow-up", value: "\(metrics.incompleteFollowUpCount)")
                            .accessibilityIdentifier("results.incomplete")
                    }
                    Text("A reopen means a Shortcut automation reported any selected-app open within 3 minutes after Go Back. “No reopen observed” is not proof the person stayed away: an automation may be disabled, fail to run, or the session may stop observing.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if session.mode == .simulated {
                    Text("Demo events are simulated, so they cannot verify real social-app opens after Go Back.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Device Activity reports aggregate usage, not each app open, so this mode cannot measure a 3-minute reopen after Go Back.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Your feedback · 1 low, 5 high") {
                Picker("Usefulness", selection: $usefulness) { ForEach(1...5, id: \.self) { Text("\($0)").tag($0) } }
                Picker("Annoyance", selection: $annoyance) { ForEach(1...5, id: \.self) { Text("\($0)").tag($0) } }
                Button(session.ratings == nil ? "Save Ratings" : "Update Ratings") { model.rate(sessionID: session.id, usefulness: usefulness, annoyance: annoyance) }
                    .accessibilityIdentifier("saveRatings")
                if session.ratings != nil { Text("Ratings saved on this device.").accessibilityIdentifier("ratingsSaved") }
            }
            Button("Done") { model.presentedResultsID = nil }.accessibilityIdentifier("resultsDone")
        }
        .navigationTitle("Session results")
        .onAppear {
            usefulness = session.ratings?.usefulness ?? 3
            annoyance = session.ratings?.annoyance ?? 3
        }
    }
}

private struct EventLogView: View {
    let session: FocusSession
    var body: some View {
        List {
            Section("Source") {
                Text(session.mode == .simulated ? "Simulated test events" : session.mode == .shortcuts ? "Shortcuts app-open URLs and button decisions" : "Device Activity and shield button callbacks")
            }
            Section("Triggers") {
                if session.triggers.isEmpty { Text("No trigger events yet.") }
                ForEach(session.triggers) { trigger in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(trigger.kind == .usageThreshold ? "Usage threshold reached" : trigger.kind == .manual ? "Manual demo trigger" : "Repeated simulated attempts")
                        Text(trigger.timestamp.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Decisions") {
                if session.decisions.isEmpty { Text("No decisions recorded.") }
                ForEach(session.decisions) { decision in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(decision.decision == .goBack ? "Go Back" : "Continue\(decision.continueReason.map { " · \($0.title)" } ?? "")")
                        Text(decision.timestamp.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(.secondary)
                        if let endsAt = decision.reopenObservationEndsAt {
                            if let reopenedAt = decision.reopenedAt {
                                Text("Selected app reopened (reported) at \(reopenedAt.formatted(date: .omitted, time: .standard))")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else if (session.endedAt ?? Date()) >= endsAt {
                                Text("No reopen observed within 3 minutes")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Follow-up incomplete")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }.navigationTitle("Event log")
    }
}
