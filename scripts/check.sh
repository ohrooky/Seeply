#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "需要在安裝完整 Xcode 的 Mac 執行。" >&2
    exit 1
fi
xcodebuild -project "$project_dir/Seeply.xcodeproj" -scheme Seeply \
    -destination 'platform=macOS' \
    -derivedDataPath "$project_dir/.build/DerivedData" \
    CODE_SIGNING_ALLOWED=NO test
