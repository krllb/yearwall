#!/bin/bash
# Builds Yearwall.app.
#
# `swift run` is enough for development, but two things need a real bundle:
# "Launch at Login" (SMAppService.mainApp) and a stable bundle identifier.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
APP="build/Yearwall.app"

swift build -c "$CONFIG"
BINARY="$(swift build -c "$CONFIG" --show-bin-path)/Yearwall"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Yearwall"
cp Sources/Yearwall/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature: SMAppService refuses to register an unsigned bundle.
codesign --force --sign - --identifier com.krllb.Yearwall "$APP"

echo "built $APP"
echo "run it with: open $APP"
