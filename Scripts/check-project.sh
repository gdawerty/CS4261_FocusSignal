#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

for path in Config/*.plist Config/*.entitlements Config/*.xcprivacy FocusSignal.xcodeproj/project.pbxproj; do
    plutil -lint "$path"
done
xmllint --noout FocusSignal.xcodeproj/xcshareddata/xcschemes/FocusSignal.xcscheme
xmllint --noout FocusSignal.xcodeproj/project.xcworkspace/contents.xcworkspacedata

if [[ ! -f Package.swift ]]; then
    printf '%s\n' "Missing root Package.swift; FocusSignalCore must be available before resolving the project." >&2
    exit 1
fi

xcodebuild -list -project FocusSignal.xcodeproj
