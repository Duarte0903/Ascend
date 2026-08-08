#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
rm -rf "/Applications/Finance Tracker.app"
cp -R build/Build/Products/Release/FinanceTracker.app "/Applications/Finance Tracker.app"
echo "Installed to /Applications/Finance Tracker.app"
