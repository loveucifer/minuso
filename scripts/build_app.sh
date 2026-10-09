#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release --triple arm64-apple-macosx14.0 --build-path "$ROOT/.build/arm64"
swift build -c release --triple x86_64-apple-macosx14.0 --build-path "$ROOT/.build/x86_64"
ICON_SOURCE="$ROOT/Icon Exports/Untitled Exports"
swift scripts/make_icon.swift "$ICON_SOURCE/Untitled-macOS-Default-1024x1024@1x.png" "$ROOT/.build/Minuso.icns"

APP="$ROOT/.build/Minuso.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/AppIcons"
lipo -create \
    "$ROOT/.build/arm64/arm64-apple-macosx/release/Minuso" \
    "$ROOT/.build/x86_64/x86_64-apple-macosx/release/Minuso" \
    -output "$APP/Contents/MacOS/Minuso"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/Minuso.entitlements" "$APP/Contents/Minuso.entitlements"
cp "$ROOT/.build/Minuso.icns" "$APP/Contents/Resources/Minuso.icns"
cp "$ICON_SOURCE"/Untitled-macOS-*.png "$APP/Contents/Resources/AppIcons/"
codesign --force --deep --sign - --entitlements "$ROOT/Resources/Minuso.entitlements" "$APP"
printf 'Built %s\n' "$APP"
