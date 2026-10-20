#!/bin/zsh
# Builds DayList.app into ./build. Needs only the Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/DayList.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macos14.0" \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/DayList"

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"
