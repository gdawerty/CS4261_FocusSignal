# FocusSignal — CS4261 MVP

An iOS study-session prototype with two clearly labeled modes:

- **Demo:** three simulated selected-app attempts within five minutes show an in-app intervention. Productive apps and unselected apps do not count. Includes configurable attempt/window/cooldown settings.
- **Shortcuts prototype:** personal automations call a background App Intent to report selected app aliases. FocusSignal opens only when the configured attempt threshold is reached (default: three reported opens within five minutes). It does not display an overlay on top of, or block, the opened app.
- **Real device:** combined usage of individually selected apps reaches a configurable threshold (default 60 seconds) during a focus session (default 30 minutes). A Device Activity extension applies an Apple Managed Settings shield.

**Go Back** records the choice, closes the attempted app, and keeps the shield applied. On iOS 26.4 and later, **Continue** first asks for a reason through the shield’s submenu, then exempts only that app until the session ends. Older supported OS versions omit Continue rather than allow access without a reason; end the session in FocusSignal to lift the shield. The prototype registers one usage-threshold event per real session; it does not re-arm a five-minute allowance or detect real app switches. The system determines callback and shield timing; a shield may appear over an app already in use.

## Run the demo

1. Open `FocusSignal.xcodeproj` in Xcode 26.4 or newer with an installed iOS 17.4+ simulator. The shared sources use Screen Time authorization APIs introduced in the iOS 26.4 SDK behind availability checks. This implementation was built with Xcode 27.
2. Select the **FocusSignal** scheme and an iPhone **Simulator** destination (for example, iPhone 18 Pro), not a connected physical iPhone, then Run. The simulator demo does not require a development team or Family Controls signing.
3. Tap **Set Up Focus Session**, keep **Demo**, and start.
4. Open **Testing Panel**. Simulate Video app, Social feed, and Forum app. The third attempt opens the intervention.
5. Choose Go Back or Continue. Continue asks for a brief reason before recording the choice. Return and end the session to see the decision and reason counts and save ratings.

**Simulate productive app** verifies that an unselected app has no effect. **Trigger Intervention Now** bypasses the demo attempt threshold/cooldown for a quick presentation. Demo mode never blocks another app.

## Run the Shortcuts prototype on an iPhone

1. In Xcode, choose the **FocusSignalShortcutDemo** scheme and your iPhone. This is a separate app target with no Family Controls or App Group entitlement; select your Personal Team under Signing & Capabilities if Xcode asks. It uses a separate `.shortcutdemo` bundle identifier.
2. Install and open it, tap **Set Up Focus Session**, and start a **Shortcuts** session.
3. In Shortcuts, create a Personal Automation with the **App** trigger for a distracting app and **Is Opened**. Add the **Record FocusSignal App Open** action, set its alias, and optionally set its return URL. Add **If**: if the action result is **true**, add a **URL** action with `focussignal-shortcuts://intervention` and pass that URL to **Open URLs**; if false, do nothing. Set the automation to run immediately / turn off confirmation if offered. Repeat for each distracting app; do not create automations for productive apps. Replace the old unconditional **Open URLs** action in existing automations.
4. With no active session, events return `false` and FocusSignal stays closed. During a session, opens are counted; only the event that reaches the threshold returns `true`. The stable intervention URL opens the pending intervention already saved by the action. Continue asks for a reason, exempts that alias for the session, and, if the automation supplied a usable return URL, opens it. Go Back clears the shared attempt count and normal counting resumes after the configured cooldown. Separately, the first reported open of any selected app within 3 minutes after Go Back is recorded as a reopen, including opens that cooldown suppresses as new triggers. This Shortcut flow adds friction but cannot prevent or block the target app from opening.

This is a proof of concept, not system-level background app monitoring: events are counted only when a user-configured Shortcuts automation runs. FocusSignal does not learn which app opened unless the automation supplies its alias. Instagram's `instagram://app` is an undocumented, best-effort return URL; verify it on the target iPhone. Without a working return URL, Continue still exempts the alias but the user switches back manually. For a quick regression check without automations, the active Shortcuts screen includes **Send sample event (test; opens FocusSignal)**.

## Run real Screen Time on an iPhone

A US Apple account can use the standard token-based Screen Time APIs. This app does not request the region-limited non-tokenized usage-data capability.

1. Use an Apple Developer Program team that can provision **Family Controls (Development)**. A free Personal Team may not support the required capabilities.
2. Create `Config/Local.xcconfig` using `Config/Local.xcconfig.example`. Set your team, a unique bundle prefix, and registered App Group. This local file is ignored by Git.
3. Enable **Family Controls** and the same **App Group** for the app, monitor, shield configuration, and shield action targets/App IDs. Automatic signing must include the capabilities in every device provisioning profile. See [Config/README.md](Config/README.md).
4. Pair your iPhone, enable Developer Mode, select it in Xcode, and Run. No distribution is required for this local development path.
5. Select **Real device**, allow Screen Time access, and choose **individual applications**. Whole categories and websites are rejected to avoid unintentionally shielding productive apps or leaving a category rule active after Continue.
6. Start a 30-minute session with a 60-second threshold. Background FocusSignal and use selected apps. After the system threshold callback, the extension shields the selected apps. Test Go Back (the app closes and remains shielded), each Continue reason (that app is allowed), and session cleanup.

TestFlight/App Store distribution requires Apple's separate Family Controls approval for the app **and each extension**. Device signing, authorization, and enforcement cannot be established by simulator tests alone. Follow [TESTING.md](TESTING.md) for the physical-device acceptance checklist.

## Implementation parts

| Part | Location | Responsibility |
|---|---|---|
| 1. Session rules and persistence | `Sources/FocusSignalCore/` | Selection filtering, triggers, decisions, expiry, metrics, cross-process transactions |
| 2. SwiftUI app | `App/` | Setup, active session, demo intervention, developer panel, results, ratings, history |
| 3. Screen Time integration | `Shared/ScreenTimeRuntime.swift` | Individual authorization checks, token encoding, absolute schedules, registration and cleanup |
| 4. Extensions | `Extensions/` | Threshold callback, shield appearance, Go Back/Continue |
| 5. Shortcuts bridge | `App/`, `Sources/FocusSignalCore/`, `Config/FocusSignalShortcutDemo-Info.plist` | Validated alias URLs, event counting, and a no-Family-Controls app target |
| 6. Verification and configuration | `Tests/`, `UITests/`, `Config/`, `Scripts/` | Regression tests, entitlements, privacy declarations and build settings |

The core package is shared with extensions. `BehaviorTriggerEngine` separates monitoring registration from simulation; the actual Device Activity callbacks run in an extension, not in the main process.

## Tests

```sh
swift test
bash Scripts/check-project.sh
bash Scripts/test-ui.sh
```

`test-ui.sh` selects an installed iPhone simulator. Set `SIMULATOR_UDID` to choose another device. UI tests use a separate local store; their reset flag cannot erase normal app data.

For Desktop/iCloud/File Provider workspaces where Xcode signing reports resource-fork/Finder metadata errors, keep build products outside the synced directory:

```sh
swift test --scratch-path /tmp/focussignal-core-build
FOCUSSIGNAL_DERIVED_DATA=/tmp/focussignal-ios-build bash Scripts/test-ui.sh
```

To compile the device-specific implementation without signing or installing it:

```sh
xcodebuild build -project FocusSignal.xcodeproj -scheme FocusSignal \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/focussignal-device-build CODE_SIGNING_ALLOWED=NO
```

The GitHub Actions workflow runs project validation, core tests, and simulator UI tests on pushes/PRs. An unsigned compile is not physical-device validation.

## Local data and privacy

The app stores up to 50 sessions in a JSON file in the App Group container. Simulator/demo fallback storage uses the app's Application Support container. Neither path is inside this repository. The store serializes complete read/modify/write transactions with a separate `flock` lock file and replaces data atomically. Shield updates run under the same lock so a session-end operation cannot race with an old callback and leave stale restrictions.

The storage directory is excluded from device backups, and on iOS files use protection until the first device unlock after restart. Completed sessions retain random local app aliases, decisions, and ratings; opaque application tokens are discarded. No app content, bundle identifiers, or token bytes are displayed in event logs. No backend, analytics, network client, API keys, or cloud sync are configured.

**Delete All Local Data** removes session history and clears FocusSignal restrictions. Corrupt data is reported and preserved until an explicit reset. This is local prototype storage, not a claim of cryptographic anonymity.

`.gitignore` excludes build products, private signing material, personal configuration, database artifacts, and export directories. Keep `.entitlements`, project files, and example configuration tracked: they declare capabilities and do not contain private signing keys. Never put server secrets into the app binary, even through an ignored config file.

## What the results mean

Results distinguish **trigger episodes** from **recorded decisions** and show the selected reason for Continue. In Shortcut mode, each Go Back decision has a fixed 3-minute follow-up window. A later selected-app event reported by a configured automation is labeled **Reopened (reported)**. If no event arrives, results say **No reopen observed** only after the full window was observable; if the session ends sooner, it says **Incomplete follow-up**. The event log shows the reported reopen time.

This is an observed-event metric, not proof that Go Back stopped use or that the user studied. Automations can be disabled, fail, or omit events, so **No reopen observed** means only that FocusSignal received no qualifying Shortcut event. The initial app open that caused the intervention is before Go Back and does not count. Demo events are simulated; Device Activity provides aggregate usage rather than a per-open event stream, so this follow-up measure is only available in Shortcut mode. A threshold callback likewise does not prove a shield was viewed. More than one Go Back/Continue decision may follow a single usage threshold. Percentages use answered decisions and show no percentage when there are none.

This is a proof of concept for evaluating aggregate distraction during a study session. Delayed friction alone is not commercially unique: one sec also documents delayed interventions and re-interventions. See the [implementation plan](FOCUSSIGNAL_MVP_IMPLEMENTATION_PLAN.md) for context.

## API references

- [Configuring Family Controls](https://developer.apple.com/documentation/xcode/configuring-family-controls)
- [Distribution entitlements](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement)
- [DeviceActivityEvent and past-activity handling](https://developer.apple.com/documentation/deviceactivity/deviceactivityevent)
- [15-minute schedule minimum](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror/intervaltooshort)
- [Shield action responses](https://developer.apple.com/documentation/managedsettings/shieldactionresponse)
- [one sec intervention modes](https://feedback.one-sec.app/en/help/articles/1693386-immediate-vs-delayed-vs-always-ask-which-one-is-the)
