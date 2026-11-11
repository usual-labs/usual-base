#!/bin/sh
# Formatting, BaseKit's tests and an unsigned app build. `scripts/check.sh --fast` skips the build.
set -eu
cd "$(dirname "$0")/.."

swift format lint --strict --recursive App Packages/BaseKit/Sources Packages/BaseKit/Tests Packages/BaseKit/Package.swift
swift test --package-path Packages/BaseKit
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/review -p 'test_*.py'

if [ "${1:-}" != "--fast" ]; then
    xcodebuild build -quiet -project UsualBase.xcodeproj -scheme UsualBase \
        -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO
fi
