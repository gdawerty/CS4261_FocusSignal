# FocusSignal regression and device validation

## Automated coverage

The core tests run as a local Swift package, independently of iOS entitlements. They cover:

- only selected app attempts count; productive apps remain ignored;
- three attempts (including repeats of one app), sliding-window boundaries, stale timestamps and cooldown;
- duplicate triggers and repeated decision request IDs;
- a single Continue exempts only its target app for the current session;
- mode separation, expired/cancelled sessions, stale callbacks and new session isolation;
- no all-app monitoring through an empty selection;
- full-date schedule construction across midnight and the 15-minute minimum;
- zero-decision metrics, per-decision denominators and rating validation;
- persistence across store instances, rollback, corruption preservation and explicit reset;
- concurrent transactions retaining every decision.

UI tests exercise full demo sessions, unselected productive events, Go Back and Continue, session and exemption restoration across app relaunch, zero-decision results, and saving ratings. They do not simulate successful Family Controls authorization or claim to test real shielding.

```sh
swift test
bash Scripts/check-project.sh
bash Scripts/test-ui.sh
```

## Physical-iPhone acceptance

Record the iOS version, device model, app build, signing setup and actual callback/decision times when testing. Do not publish private tokens or signing information in a test report.

| Test | Expected result |
|---|---|
| Deny Screen Time authorization | Real session cannot start; Demo still works |
| Allow individual authorization | Picker opens; owner can select individual apps |
| Empty selection | Start is disabled; no all-app event is registered |
| Category or website selection | Start is disabled with an explanatory message |
| Use selected app before starting | Prior activity is excluded (`includesPastActivity: false`) |
| Use unselected ChatGPT/Docs | No threshold based on those apps; they remain unshielded |
| Use selected app A, then B to cross the combined threshold | One trigger episode recorded; selected apps shielded after callback |
| Keep selected app in foreground when threshold crosses | Verify actual mid-use shield behavior; do not require an exact-second deadline |
| Go Back | Choice persists, blocked experience closes, selected app remains shielded |
| Continue for app A | Only A exempted; other selected apps remain shielded |
| Reopen A later in the same session | A remains exempt; no promise of a five-minute re-lock |
| End/cancel while shield active | FocusSignal named store cleared; session invalidated and monitoring stopped |
| End old session, immediately start another | Late callbacks from old session cannot shield or clear new session |
| Session ends with FocusSignal terminated | Monitor's end callback cleans up when iOS invokes it; main app also reconciles on next foreground |
| Lock phone through scheduled end | Check cleanup on next device use; end callbacks are not exact wall-clock alarms |
| Reboot and unlock | Verify persisted session state and monitoring recovery; no indefinite stale shield |
| Revoke permission mid-session | Main app interrupts session on refresh; reauthorization requires fresh selection |
| Overlapping restrictions from another app/Screen Time | Continue removes only FocusSignal restrictions; it cannot override another provider |
| Start near midnight | Session uses full calendar dates and ends on the intended date |
| Delete All Local Data | History cleared, monitors stopped, FocusSignal shields removed |

If iOS doesn't deliver expected threshold callbacks, capture the observable result and keep the Demo path available. A simulator build cannot establish device callback reliability. Do not mark the real-device acceptance tests passed until someone runs them on the signed phone.
