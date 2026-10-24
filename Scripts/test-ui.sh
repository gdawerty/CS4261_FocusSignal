#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Select an installed iPhone without coupling CI to a particular runtime/name.
# Override SIMULATOR_UDID to choose an iPad or a specific runtime.
simulator_id="${SIMULATOR_UDID:-}"
if [[ -z "$simulator_id" ]]; then
    simulator_id="$(xcrun simctl list devices available --json | python3 -c '
import json
import sys

devices = [
    device
    for runtime, entries in json.load(sys.stdin)["devices"].items()
    if ".iOS-" in runtime
    for device in entries
    if device.get("isAvailable") and device["name"].startswith("iPhone")
]
devices.sort(key=lambda device: device.get("state") != "Booted")
if not devices:
    sys.exit("No available iPhone simulator. Install an iOS simulator runtime in Xcode.")
print(devices[0]["udid"])
')"
fi

xcodebuild test \
    -project FocusSignal.xcodeproj \
    -scheme FocusSignal \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$simulator_id" \
    -derivedDataPath "${FOCUSSIGNAL_DERIVED_DATA:-DerivedData}" \
    -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=NO \
    "$@"
