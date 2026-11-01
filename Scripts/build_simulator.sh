#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Artifacts
xcodebuild -project MiraiLedger.xcodeproj -scheme MiraiLedger \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .derivedData CODE_SIGNING_ALLOWED=NO build > Artifacts/build.log 2>&1
tail -5 Artifacts/build.log
