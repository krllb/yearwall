#!/bin/bash
# Builds Yearwall.app.
#
#     Scripts/make-app.sh [debug|release] [--universal]
#
# `swift run` is enough for development, but a real bundle is needed for
# "Launch at Login" (SMAppService.mainApp), the icon and updates.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
APP="build/Yearwall.app"
FLAGS=(-c "$CONFIG")
if [[ "${2:-}" == "--universal" ]]; then
    FLAGS+=(--arch arm64 --arch x86_64)
fi

swift build "${FLAGS[@]}"
BINARY="$(swift build "${FLAGS[@]}" --show-bin-path)/Yearwall"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Yearwall"
cp Sources/Yearwall/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature: SMAppService refuses to register an unsigned bundle.
codesign --force --sign - --identifier com.krllb.Yearwall "$APP"

echo "built $APP"
echo "run it with: open $APP"
