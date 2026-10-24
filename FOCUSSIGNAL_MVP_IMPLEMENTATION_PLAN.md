# FocusSignal MVP Implementation Plan

Implementation note: the MVP source now follows this plan. See `README.md` for setup and `TESTING.md` for automated coverage and physical-device acceptance. The prototype uses a process-locked atomic JSON store, discards tokens when a session ends, and retains at most 50 sessions. Results distinguish trigger episodes from decisions because a threshold callback is not a confirmed shield impression. Device enforcement still needs signed-iPhone validation.

## 1. Executive decision

FocusSignal is feasible as an iOS proof of concept using SwiftUI and Apple's Screen Time frameworks.

The MVP must distinguish between two trigger modes:

1. **Real device trigger:** selected distracting-app usage reaches a time threshold during a focus session.
2. **Simulated pattern trigger:** a developer panel simulates the original rule of three distracting-app opens/switches within five minutes.

Apple's public `DeviceActivity` APIs do not expose a reliable stream of arbitrary app launches or cross-app switches. They monitor selected applications and invoke callbacks when their accumulated foreground activity reaches a configured threshold. Therefore, the real implementation should not claim to detect the exact sequence `TikTok -> Instagram -> Reddit`.

This is a scope adjustment, not a change to the product's purpose. The product remains behavior-triggered friction: FocusSignal waits until distraction has started before interrupting instead of interrupting every app launch.

## 2. MVP hypothesis

> Does behavior-triggered friction after a period of distracting app activity reduce unwanted phone use without unnecessarily interrupting intentional use?

The first real trigger will be:

> During an active focus session, selected distracting apps accumulate 60 seconds of foreground activity, causing FocusSignal to display friction.

The threshold must be configurable so the team can compare 30 seconds, 60 seconds, and 120 seconds in later tests.

## 3. Scope

### In scope

- SwiftUI iOS application.
- Individual Family Controls authorization for self-use.
- `FamilyActivityPicker` selection of distracting apps.
- Focus session setup with a minimum 15-minute monitoring window.
- A first real configuration using a 30-minute session and 60-second usage threshold.
- `DeviceActivityMonitor` extension for the real threshold callback.
- Managed Settings shield configuration and shield action extensions.
- Go Back and Continue decisions.
- Local session and intervention logging through an App Group container.
- End-of-session metrics and ratings.
- Developer/testing panel with simulated trigger controls.
- Unit tests for trigger logic and metric calculations.

### Out of scope for the MVP

- Reliable real-time detection of arbitrary app-switch sequences through `DeviceActivity`.
- Server, accounts, Firebase, analytics SDKs, or cloud synchronization.
- Social features, family syncing, rewards, AI personalization, and cross-device support.
- Reading app content, notifications, messages, or anything the user views inside another app.
- Apple's optional non-tokenized usage-data access.
- App Store/TestFlight distribution unless the Family Controls distribution entitlement has been approved.

## 4. Platform feasibility and constraints

### Family Controls and app selection

The app requests `FamilyControlsMember.individual` authorization because the MVP is for the owner of the device. After authorization, `FamilyActivityPicker` lets the user select applications. The app receives opaque application tokens rather than needing to identify apps by bundle ID.

The app and every Screen Time extension that uses the capability must be configured with the required Family Controls and App Groups entitlements.

### Device Activity

`DeviceActivityEvent` can monitor a set of selected application tokens and invoke `eventDidReachThreshold` after the selected applications accumulate the configured amount of foreground usage.

`DeviceActivitySchedule` is calendar-based and has a minimum monitoring interval of 15 minutes. This means a 30-minute focus session with a 60-second event threshold is valid; a 60-second monitoring schedule is not.

The threshold callback runs in the Device Activity Monitor extension, not as a normal event stream inside the main app. The extension must write a trigger event to shared storage and apply the shield.

### Managed Settings shields

The monitor extension applies a named `ManagedSettingsStore` shield to the selected application tokens. The Shield Configuration extension supplies the custom title, subtitle, and button labels.

The Shield Action extension receives a primary or secondary button action for the token being shielded:

- **Go Back:** log the decision, leave the shield active, and return `.close`.
- **Continue:** log the decision, remove that token from FocusSignal's named shield store, and return `.none`.

There is no built-in Apple response such as `allowForFiveMinutes`. The first MVP should allow Continue through the remainder of the current focus session. A timed cooldown and re-shielding can be added after the core loop is stable.

### US proof of concept

The standard tokenized Family Controls, Device Activity, and Managed Settings path is appropriate for a US development build. The newer `approvedWithDataAccess` authorization is not required for this MVP and should not be used as a dependency.

The proof of concept should be tested on a physical iPhone with development signing. Simulator testing can cover the SwiftUI screens and simulated trigger, but Screen Time behavior should be validated on a real device.

Family Controls distribution approval is a separate requirement for TestFlight or App Store distribution. Direct development testing is the initial target.

## 5. User flow

```text
Home
  -> Focus Setup
  -> Request authorization if needed
  -> Select distracting apps
  -> Configure session and threshold
  -> Start Focus Session
  -> Device Activity monitors selected apps
  -> Usage threshold is reached
  -> Managed Settings shield covers selected apps (including potentially the app already in use)
  -> Go Back or Continue
  -> Decision is logged
  -> End Focus Session
  -> Session Results
```

The developer panel adds a parallel path:

```text
Developer Panel
  -> Simulate distracting-app open
  -> Simulated pattern engine updates timestamp queue
  -> Three events inside five minutes
  -> In-app friction view appears
  -> Decision is logged
```

The simulated path exercises the original repeated-attempt interaction concept. It cannot validate real app-switch detection or prove reduced unwanted usage. It is labeled as simulated in the event data and in the project presentation. Repeated opens of the same selected app count; this is not a distinct-app counter.

## 6. Architecture

```text
SwiftUI App
  -> FocusSessionManager
  -> BehaviorTriggerEngine
       -> SimulatedPatternTrigger
       -> DeviceActivityThresholdTrigger
       -> ShortcutsOpenTrigger (future experiment; not implemented)
  -> SharedStore in App Group
  -> DeviceActivityCenter

DeviceActivityMonitor Extension
  -> reads active session and selected tokens
  -> records threshold event
  -> applies ManagedSettings shield

Shield Configuration Extension
  -> renders FocusSignal shield UI

Shield Action Extension
  -> records Go Back or Continue
  -> keeps or modifies FocusSignal's named shield store
```

The `BehaviorTriggerEngine` protocol should expose operations such as:

```swift
protocol BehaviorTriggerEngine {
    func start(session: FocusSession) throws
    func stop(session: FocusSession) throws
}
```

The simulated engine may expose additional test-only methods such as `recordSimulatedAttempt(at:)`. The real engine should be responsible for configuring monitoring, while its callbacks are handled by the Device Activity Monitor extension.

## 7. Data model

### FocusSession

- `id: UUID`
- `title: String` such as `Studying`
- `startTime: Date`
- `endTime: Date?`
- `plannedDuration: TimeInterval`
- `thresholdSeconds: Int`
- `status: active | completed | cancelled | interrupted`
- selected application tokens or an encoded `FamilyActivitySelection`
- `interventionCount` derived from events rather than independently maintained when possible

### InterventionEvent

- `id: UUID`
- `sessionID: UUID`
- `timestamp: Date`
- `triggerSource: deviceActivity | simulated | shortcuts`
- `triggerType: usageThreshold | repeatedAttempts | manual`
- `interventionNumber: Int`
- `decision: goBack | continue | unresolved`
- `timeSincePreviousIntervention: TimeInterval?`
- optional `continueReason`

Do not use Swift's runtime `hashValue` as a persistent app identifier. If correlating a token is necessary, use a documented encoded-token digest or store only an internal event identifier. The app does not need to learn or display the selected app's identity.

## 8. Local storage, privacy, and secrets

All session data remains on the device in an App Group container shared by the app and extensions. Use a small shared configuration object for the active session and a concurrent-safe local event store for the event log. A SQLite/Core Data/SwiftData store in the App Group is preferable once both the main app and extensions write events; `UserDefaults` should be limited to small non-sensitive configuration values.

The MVP should provide:

- a Reset Session action;
- a Delete All Local Data action;
- no network transmission;
- no third-party analytics;
- no app-content collection;
- minimal retention of event data;
- file protection where supported by the selected storage implementation.

The app does not need API keys for this local-only MVP. Bundle IDs, team IDs, and App Group identifiers are configuration values, not secrets. Private signing keys, certificates, provisioning profiles, backend credentials, and local secret configuration files must not be committed.

The repository should ignore Xcode-generated files, local databases, debug exports, and secret configuration files. `.gitignore` cannot remove a secret that has already been committed; any exposed secret must be rotated and removed from history.

## 9. Milestones

### Milestone 1: Project and app shell

- Create the iOS SwiftUI project.
- Add the main navigation flow.
- Add the App Group and shared target model package/files.
- Add Xcode-specific Git ignores.
- Confirm the project builds on simulator and device.

### Milestone 2: Onboarding and selection

- Request individual Family Controls authorization.
- Handle approved, denied, and not-determined states.
- Present `FamilyActivityPicker`.
- Persist the encoded selection locally.
- Show selected app labels/icons without storing app names in event logs.

### Milestone 3: Session and simulated trigger

- Implement `FocusSession` and `InterventionEvent`.
- Implement the timestamp queue for three simulated attempts within five minutes.
- Add simulated friction UI.
- Add developer controls and unit tests.
- Show session results from local events.

### Milestone 4: Real Device Activity trigger

- Start a 30-minute Device Activity schedule.
- Monitor selected application tokens.
- Use a 60-second threshold.
- Write the extension callback to shared storage.
- Apply a named Managed Settings shield.
- Test authorization denial, app termination, and session cancellation.

### Milestone 5: Shield decisions

- Add Shield Configuration and Shield Action extensions.
- Implement Go Back and Continue.
- Preserve only FocusSignal's own Managed Settings store.
- Allow Continue through session end for the first version.
- Clear the shield when the session ends or is reset.

### Milestone 6: Evaluation and presentation

- Add effectiveness and annoyance ratings.
- Calculate intervention count, Go Back percentage, Continue percentage, and interventions per session.
- Demonstrate simulated repeated-attempt behavior.
- Demonstrate real usage-threshold behavior on an iPhone.
- Document the distinction between measured behavior and simulated behavior.

## 10. Testing plan

### Unit tests

- Timestamp queue removes events outside the five-minute window.
- Exactly three simulated attempts triggers once.
- Cooldown prevents duplicate simulated interventions.
- Session metrics handle zero interventions and incomplete sessions.
- Go Back and Continue counts are derived correctly.

### Device tests

- Authorization approved and denied.
- Empty selection.
- Selection changed between sessions.
- Active session while the app is backgrounded or terminated.
- Threshold reached while a selected app is in use.
- Shield appears when the selected app is accessed.
- Go Back closes the current blocked experience.
- Continue removes only the selected app from FocusSignal's named store.
- Session end clears FocusSignal's shields.
- Authorization revoked and tokens become invalid.

## 11. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Family Controls provisioning fails | Use development signing and verify capabilities before building the full UI. Keep simulated mode runnable without Screen Time. |
| Simulator does not reproduce Screen Time behavior | Use a physical iPhone for Device Activity and shield validation. |
| Exact app switches are unavailable | Keep them simulated or add an optional user-configured Shortcuts/App Intent experiment. |
| Threshold callback timing is system-controlled | Treat threshold timing as approximate and log actual callback timestamps. |
| Multiple extension processes write concurrently | Centralize storage and use a concurrency-safe shared database or atomic file operations. |
| Continue cooldown becomes unreliable | Allow through session end for MVP; implement timed re-shielding later. |
| Authorization revocation invalidates tokens | Detect authorization changes and require a fresh selection. |

## 12. Differentiation for the class project

FocusSignal should not claim that app blocking, delayed friction, or reflective decisions are commercially unique. Brick emphasizes physical separation and NFC activation; one sec offers immediate, delayed, and repeated interventions; Opal offers focus sessions, blocking, reports, and rewards. FocusSignal's contribution here is the particular study-session experiment and its evaluation, not a claim that competitors only interrupt on launch. [one sec intervention modes](https://feedback.one-sec.app/en/help/articles/1693386-immediate-vs-delayed-vs-always-ask-which-one-is-the)

FocusSignal's project contribution is the behavior-triggered experiment:

> Aggregate distracting activity during a focus session, then introduce a measurable interruption and record whether the user chooses Go Back or Continue.

The simulated repeated-switching trigger preserves the original research concept, while the real usage-threshold trigger makes the prototype compatible with Apple's public APIs.

## 13. Definition of done

The MVP is complete when the team can demonstrate both paths:

### Simulated path

```text
Start session
  -> simulate three distracting attempts within five minutes
  -> friction appears
  -> choose Go Back or Continue
  -> event is stored locally
  -> results show the decision
```

### Real-device path

```text
Authorize on a physical iPhone
  -> select apps
  -> start a 30-minute focus session
  -> use selected apps for approximately 60 seconds total
  -> shield is applied
  -> choose Go Back or Continue
  -> event is stored locally
  -> session results show the decision
```

## 14. References

- [Family Controls](https://developer.apple.com/documentation/familycontrols)
- [Configuring Family Controls](https://developer.apple.com/documentation/xcode/configuring-family-controls)
- [Requesting the Family Controls entitlement](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement)
- [FamilyActivityPicker](https://developer.apple.com/documentation/familycontrols/familyactivitypicker)
- [DeviceActivityEvent](https://developer.apple.com/documentation/deviceactivity/deviceactivityevent)
- [DeviceActivityMonitor](https://developer.apple.com/documentation/deviceactivity/deviceactivitymonitor)
- [DeviceActivitySchedule minimum interval](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror/intervaltooshort)
- [Managed Settings](https://developer.apple.com/documentation/managedsettings)
- [ShieldConfiguration](https://developer.apple.com/documentation/managedsettingsui/shieldconfiguration)
- [ShieldActionDelegate](https://developer.apple.com/documentation/managedsettings/shieldactiondelegate)
- [ShieldActionResponse](https://developer.apple.com/documentation/managedsettings/shieldactionresponse)
- [Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- [AuthorizationStatus.approvedWithDataAccess](https://developer.apple.com/documentation/familycontrols/authorizationstatus/approvedwithdataaccess)
