#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/SnowVibe.app"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
MODULE_CACHE="$PROJECT_DIR/.build/module-cache"
ARM_BINARY="$BUILD_DIR/SnowVibe-arm64"
INTEL_BINARY="$BUILD_DIR/SnowVibe-x86_64"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$MODULE_CACHE"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" swiftc \
  -sdk "$SDK_PATH" \
  -target arm64-apple-macos13.0 \
  -O \
  -framework AppKit \
  -framework QuartzCore \
  "$PROJECT_DIR"/src/*.swift \
  -o "$ARM_BINARY"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" swiftc \
  -sdk "$SDK_PATH" \
  -target x86_64-apple-macos13.0 \
  -O \
  -framework AppKit \
  -framework QuartzCore \
  "$PROJECT_DIR"/src/*.swift \
  -o "$INTEL_BINARY"

lipo -create "$ARM_BINARY" "$INTEL_BINARY" -output "$APP_DIR/Contents/MacOS/SnowVibe"

cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/assets/SnowVibe.icns" "$APP_DIR/Contents/Resources/SnowVibe.icns"
codesign --force --deep --sign - "$APP_DIR"

codesign --verify --deep --strict "$APP_DIR"
lipo "$APP_DIR/Contents/MacOS/SnowVibe" -verify_arch arm64
lipo "$APP_DIR/Contents/MacOS/SnowVibe" -verify_arch x86_64

ditto -c -k --keepParent "$APP_DIR" "$BUILD_DIR/SnowVibe-macOS.zip"
echo "$APP_DIR"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Info.plist")"
BUILD_VOLUME_NAME="SnowVibe Setup $VERSION $$"
IMAGE_DIR="$(mktemp -d "$BUILD_DIR/dmg.XXXXXX")"
MOUNT_DIR=""
ATTACH_DEVICE=""
RW_DMG="$BUILD_DIR/SnowVibe-$VERSION-rw.dmg"
FINAL_DMG="$BUILD_DIR/SnowVibe-$VERSION.dmg"
cleanup() {
  if [[ -n "$ATTACH_DEVICE" && "$ATTACH_DEVICE" == /dev/disk* ]]; then
    hdiutil detach "$ATTACH_DEVICE" >/dev/null 2>&1 || true
  fi
  if [[ "$IMAGE_DIR" == "$BUILD_DIR"/dmg.* && -d "$IMAGE_DIR" ]]; then
    rm -rf -- "$IMAGE_DIR"
  fi
  rm -f -- "$RW_DMG"
}
trap cleanup EXIT
ditto "$APP_DIR" "$IMAGE_DIR/SnowVibe.app"
ln -s /Applications "$IMAGE_DIR/Applications"
mkdir -p "$IMAGE_DIR/.background"
cp "$PROJECT_DIR/assets/dmg-background.png" "$IMAGE_DIR/.background/background.png"

rm -f -- "$RW_DMG" "$FINAL_DMG"
hdiutil create -volname "$BUILD_VOLUME_NAME" -srcfolder "$IMAGE_DIR" -ov -format UDRW "$RW_DMG"
ATTACH_OUTPUT="$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen)"
print -r -- "$ATTACH_OUTPUT"
ATTACH_DEVICE="$(print -r -- "$ATTACH_OUTPUT" | awk 'NR == 1 { print $1 }')"
MOUNT_DIR="$(print -r -- "$ATTACH_OUTPUT" | awk -F '\t' '$3 ~ /^\/Volumes\// { print $3; exit }')"
if [[ -z "$ATTACH_DEVICE" || "$ATTACH_DEVICE" != /dev/disk* || -z "$MOUNT_DIR" || ! -d "$MOUNT_DIR" ]]; then
  echo "Не удалось определить точку монтирования DMG" >&2
  exit 1
fi

osascript <<APPLESCRIPT
set backgroundFile to POSIX file "$MOUNT_DIR/.background/background.png" as alias
tell application "Finder"
    tell disk "$BUILD_VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set bounds of container window to {180, 120, 880, 560}
        set viewOptions to icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 14
        set label position of viewOptions to bottom
        set background picture of viewOptions to backgroundFile
        set position of item "SnowVibe.app" of container window to {132, 207}
        set position of item "Applications" of container window to {568, 207}
        update without registering applications
        delay 3
        close container window
    end tell
end tell
APPLESCRIPT

sync
diskutil renameVolume "$MOUNT_DIR" "SnowVibe"
hdiutil detach "$ATTACH_DEVICE"
ATTACH_DEVICE=""
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG"
hdiutil verify "$FINAL_DMG"

RELEASE_DIR="$PROJECT_DIR/../Releases"
mkdir -p "$RELEASE_DIR"
cp "$BUILD_DIR/SnowVibe-macOS.zip" "$RELEASE_DIR/SnowVibe-$VERSION-macOS-universal.zip"
cp "$FINAL_DMG" "$RELEASE_DIR/SnowVibe-$VERSION-macOS-universal.dmg"
echo "Релизы: $RELEASE_DIR"
