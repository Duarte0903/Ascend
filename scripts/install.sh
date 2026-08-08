#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
rm -rf "/Applications/Ascend.app"
cp -R build/Build/Products/Release/Ascend.app "/Applications/Ascend.app"
echo "Installed to /Applications/Ascend.app"
