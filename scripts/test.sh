#!/bin/bash
# Runs the full test suite, filtering out unrelated macOS system logging noise.
set -uo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

xcodegen generate >/dev/null
xcodebuild -project Ascend.xcodeproj \
           -scheme Ascend \
           -destination 'platform=macOS' \
           test 2>&1 \
  | grep -E "^/.*(error|warning): |^✘|^✔ Test run|Test .* recorded an issue|\*\* TEST (SUCCEEDED|FAILED)"
