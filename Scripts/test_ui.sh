#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Artifacts
result="Artifacts/UITests-$(date +%Y%m%d-%H%M%S).xcresult"
xcodebuild -project MiraiLedger.xcodeproj -scheme MiraiLedger \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .derivedData -parallel-testing-enabled NO \
  -resultBundlePath "$result" CODE_SIGNING_ALLOWED=NO test > Artifacts/ui-tests.log 2>&1
tail -10 Artifacts/ui-tests.log
