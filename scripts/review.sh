#!/bin/sh
# Build an isolated local review app, then serve its sample window in a browser.
set -eu
umask 077
cd "$(dirname "$0")/.."

xcodebuild build -quiet -project UsualBase.xcodeproj -scheme UsualBase \
    -configuration Debug -destination 'generic/platform=macOS' \
    -derivedDataPath build/DerivedData-review \
    PRODUCT_BUNDLE_IDENTIFIER=dev.usualbase.review.UsualBase \
    CODE_SIGN_ENTITLEMENTS= CODE_SIGN_IDENTITY=-

exec python3 scripts/review/server.py \
    --app build/DerivedData-review/Build/Products/Debug/UsualBase.app
