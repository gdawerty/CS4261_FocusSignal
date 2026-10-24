# FocusSignal Xcode configuration

Open `FocusSignal.xcodeproj` and select the shared `FocusSignal` scheme. The project format requires Xcode 16 or newer for synchronized source folders. Current app/shared sources reference iOS 26.4 APIs behind availability checks, so use Xcode 26.4 or newer to compile them. Deployment starts at iOS 17.4 and Swift uses language mode 5.

The root `Package.swift` must expose the local `FocusSignalCore` library. All four shipping targets link that library directly. The package remains responsible for its own unit tests (`swift test`).

| Target | Automatically included source folders | Bundle identifier |
| --- | --- | --- |
| FocusSignal | App, Shared | `$(FOCUSSIGNAL_BUNDLE_PREFIX)` |
| FocusSignalMonitor | Extensions/Monitor, Shared | `$(FOCUSSIGNAL_BUNDLE_PREFIX).monitor` |
| FocusSignalShieldConfiguration | Extensions/ShieldConfiguration | `$(FOCUSSIGNAL_BUNDLE_PREFIX).shieldconfiguration` |
| FocusSignalShieldAction | Extensions/ShieldAction, Shared | `$(FOCUSSIGNAL_BUNDLE_PREFIX).shieldaction` |
| FocusSignalUITests | UITests | `$(FOCUSSIGNAL_BUNDLE_PREFIX).uitests` |
| FocusSignalShortcutDemo | App, Shared | `$(FOCUSSIGNAL_BUNDLE_PREFIX).shortcutdemo` |

The Screen Time app depends on and embeds all three extensions. The UI test target depends on that app and is included in its scheme's Test action. The separate FocusSignalShortcutDemo target reuses the app/shared sources, registers the `focussignal-shortcuts` URL scheme, and intentionally has no Family Controls entitlement, App Group entitlement, or extension dependencies. It is intended for the Shortcuts proof of concept and personal-team device signing. New Swift files inside the source folders are discovered by Xcode without regenerating the project.

## Signing and local overrides

`Shared.xcconfig` defines the default prefix `edu.gatech.focussignal` and App Group `group.edu.gatech.focussignal`. It optionally includes the ignored `Local.xcconfig`; copy the tracked `Local.xcconfig.example` to that filename and supply your team, unique prefix, and corresponding App Group for physical-device signing. These overrides apply to Debug and Release.

Each app/extension target uses the same `FocusSignal.entitlements` on `iphoneos`, with Family Controls and the configured App Group. Register the app and all three extension identifiers with those capabilities for device provisioning. Simulator builds have an empty `CODE_SIGN_ENTITLEMENTS`, so demo/UI testing does not need a development team or App Group signing. Simulator builds use ad hoc signing by default; the CI test command explicitly disables signing.

The FocusSignalShortcutDemo target has `CODE_SIGN_ENTITLEMENTS` empty for both simulator and iPhone builds. It never requests Screen Time authorization, registers Device Activity monitoring, or accesses the App Group; `FocusSignalBuildFlavor=shortcuts` makes its runtime use ordinary app-local storage. This is the target to try with a Personal Team when the Family Controls profiles for the standard app/extensions are unavailable.

`FocusSignalAppGroup` is expanded from `$(FOCUSSIGNAL_APP_GROUP)` in the app, monitor, and action Info.plists. The shield configuration target has no Shared source membership. Extension points and principal-class naming match the installed Xcode templates:

| Extension | Extension point | Principal class |
| --- | --- | --- |
| Monitor | `com.apple.deviceactivity.monitor-extension` | `$(PRODUCT_MODULE_NAME).FocusMonitor` |
| Shield configuration | `com.apple.ManagedSettingsUI.shield-configuration-service` | `$(PRODUCT_MODULE_NAME).FocusShieldConfiguration` |
| Shield action | `com.apple.ManagedSettings.shield-action-service` | `$(PRODUCT_MODULE_NAME).FocusShieldAction` |

The app supports iPhone and iPad, uses the system-generated launch screen, allows portrait on iPhone, and all four orientations on iPad.

## Privacy manifest

`PrivacyInfo.xcprivacy` is copied into the app and each extension. It declares no tracking or collected data. It includes system boot time reason `35F9.1` because the local core store uses `ProcessInfo.systemUptime` to bound lock wait time. This matches Apple's [elapsed-time/timer reason](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons). No UserDefaults or analytics use is declared. Update the manifest if implementation introduces additional required-reason APIs or collected data. Apple's [data collection definition](https://developer.apple.com/app-store/app-privacy-details/) concerns transmitting data off-device.

## Verification

Run from the repository root:

```sh
bash Scripts/check-project.sh
swift test
xcodebuild build -project FocusSignal.xcodeproj -scheme FocusSignal \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
bash Scripts/test-ui.sh
```

To select a specific simulator, set `SIMULATOR_UDID` before running `Scripts/test-ui.sh`. Optional script arguments pass through to `xcodebuild`, for example `-only-testing:FocusSignalUITests`. `FOCUSSIGNAL_DERIVED_DATA` overrides the default `DerivedData` output folder.

For a physical-device build after configuring signing:

```sh
xcodebuild build -project FocusSignal.xcodeproj -scheme FocusSignal \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates
```

The GitHub Actions workflow uses `macos-26`, validates the configuration, tests the core package, and builds all products while running UI tests on an available iPhone simulator. This [runner image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md) includes a sufficiently recent SDK for the guarded iOS 26.4 APIs. Screen Time enforcement itself must be verified on a provisioned physical device.
