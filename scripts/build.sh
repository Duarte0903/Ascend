#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

xcodegen generate
xcodebuild -project Ascend.xcodeproj \
           -scheme Ascend \
           -configuration Release \
           -derivedDataPath build \
           -destination 'platform=macOS' \
           build | tail -5

APP="build/Build/Products/Release/Ascend.app"
codesign --force --deep --sign - "$APP"
echo "Built and ad-hoc signed: $APP"
