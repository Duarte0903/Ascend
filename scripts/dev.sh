#!/bin/bash
# Builds a Debug copy and runs it beside the installed release.
#
# The preview keeps its profiles in "~/Library/Application Support/Ascend Dev",
# never checks for updates, and shows a DEV badge in the sidebar. The copy in
# /Applications is untouched. Run again after a change to relaunch.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

xcodegen generate >/dev/null
xcodebuild -project Ascend.xcodeproj \
           -scheme Ascend \
           -configuration Debug \
           -derivedDataPath build \
           -destination 'platform=macOS' \
           build 2>&1 | grep -E "error:|warning: |BUILD (SUCCEEDED|FAILED)" || true

APP="build/Build/Products/Debug/Ascend.app"
[[ -d "$APP" ]] || { echo "build failed" >&2; exit 1; }
codesign --force --deep --sign - "$APP" 2>/dev/null

# Only the preview instance is quit; the release keeps running.
pkill -f "$PWD/$APP/Contents/MacOS/Ascend" 2>/dev/null || true
open -n --env ASCEND_DEV=1 "$APP"
echo "Dev preview launched from $APP"
