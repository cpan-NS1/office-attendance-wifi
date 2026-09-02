#!/usr/bin/env bash
# build.sh — Build OfficeAttendance.app and package it as a DMG.
#
# Usage:
#   ./build.sh              # Release build (default)
#   ./build.sh --debug      # Debug build
#
# Notarization (release builds only):
#   Set these environment variables before running:
#     APPLE_ID          — your Apple ID email
#     APPLE_TEAM_ID     — your 10-character team ID (e.g. 9N2755GT26)
#     APPLE_APP_PASSWORD — an app-specific password from appleid.apple.com
#   If any of these are unset, notarization is skipped with a warning.

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
SCHEME="OfficeAttendance"
PROJECT="OfficeAttendance.xcodeproj"
CONFIGURATION="Release"
DEVELOPMENT_TEAM="9N2755GT26"
BUILD_DIR="$(pwd)/build"
ARCHIVE_PATH="$BUILD_DIR/$SCHEME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"

# Read current version from build settings as the default
MARKETING_VERSION=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -showBuildSettings 2>/dev/null | awk '/MARKETING_VERSION/{print $3; exit}')
CURRENT_PROJECT_VERSION=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -showBuildSettings 2>/dev/null | awk '/CURRENT_PROJECT_VERSION/{print $3; exit}')

# ── Flags ─────────────────────────────────────────────────────────────────────
for arg in "$@"; do
  case $arg in
    --debug) CONFIGURATION="Debug" ;;
    --version=*)
      if [[ "$CONFIGURATION" == "Debug" ]]; then
        echo "⚠️  --version ignored in debug builds"; else
        MARKETING_VERSION="${arg#--version=}"
      fi ;;
    --build=*)
      if [[ "$CONFIGURATION" == "Debug" ]]; then
        echo "⚠️  --build ignored in debug builds"; else
        CURRENT_PROJECT_VERSION="${arg#--build=}"
      fi ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

# DMG name is resolved after argument parsing so --version= is already applied.
if [[ "$CONFIGURATION" == "Debug" ]]; then
  DMG_NAME="OfficeAttendance-debug.dmg"
else
  DMG_NAME="OfficeAttendance-${MARKETING_VERSION}.dmg"
fi
DMG_PATH="$(pwd)/$DMG_NAME"

echo "▶ Configuration: $CONFIGURATION"

# ── Clean previous outputs ────────────────────────────────────────────────────
echo "▶ Cleaning previous build artifacts..."
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$DMG_PATH"

# ── Archive ───────────────────────────────────────────────────────────────────
echo "▶ Version: $MARKETING_VERSION (build $CURRENT_PROJECT_VERSION)"
echo "▶ Archiving..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  MARKETING_VERSION="$MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$CURRENT_PROJECT_VERSION" \
  | xcpretty || cat /dev/stdin

# ── Export ────────────────────────────────────────────────────────────────────
echo "▶ Exporting..."

# Write a temporary export options plist
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
mkdir -p "$BUILD_DIR"
cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>$DEVELOPMENT_TEAM</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  | xcpretty || cat /dev/stdin

APP_PATH="$EXPORT_PATH/$SCHEME.app"

# ── Package DMG ───────────────────────────────────────────────────────────────
echo "▶ Creating DMG..."

# Build a volume icon (.icns) from the app's 1024×1024 asset
ICON_SRC="$(pwd)/OfficeAttendance/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png"
ICONSET_DIR="$BUILD_DIR/VolumeIcon.iconset"
ICNS_PATH="$BUILD_DIR/VolumeIcon.icns"
mkdir -p "$ICONSET_DIR"
sips -z 16  16  "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16.png"     > /dev/null
sips -z 32  32  "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16@2x.png"  > /dev/null
sips -z 32  32  "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32.png"     > /dev/null
sips -z 64  64  "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32@2x.png"  > /dev/null
sips -z 128 128 "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128.png"   > /dev/null
sips -z 256 256 "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128@2x.png"> /dev/null
sips -z 256 256 "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256.png"   > /dev/null
sips -z 512 512 "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256@2x.png"> /dev/null
sips -z 512 512 "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512.png"   > /dev/null
cp "$ICON_SRC"                    "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"
rm -rf "$ICONSET_DIR"

# Use hdiutil to make a compressed, internet-ready DMG
TMP_DMG="$BUILD_DIR/tmp.dmg"
VOLUME_NAME="Office Attendance"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$APP_PATH" \
  -ov \
  -format UDRW \
  "$TMP_DMG"

# Mount the writable image and set the volume icon
MOUNT_DIR="$(mktemp -d /tmp/dmg-mount-XXXXXX)"
hdiutil attach "$TMP_DMG" -mountpoint "$MOUNT_DIR" -nobrowse -quiet
cp "$ICNS_PATH" "$MOUNT_DIR/.VolumeIcon.icns"
SetFile -a C "$MOUNT_DIR" 2>/dev/null || true   # set custom-icon bit (requires Xcode CLI tools)
hdiutil detach "$MOUNT_DIR" -quiet
rm -rf "$MOUNT_DIR"

hdiutil convert "$TMP_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH"

rm -f "$TMP_DMG"

echo ""
echo "✅ Done! DMG created at: $DMG_PATH"
echo "   App version: $(defaults read "$APP_PATH/Contents/Info" CFBundleShortVersionString)"

# ── Notarize & staple (release only) ─────────────────────────────────────────
if [[ "$CONFIGURATION" == "Release" ]]; then
  if [[ -z "${APPLE_ID:-}" || -z "${APPLE_TEAM_ID:-}" || -z "${APPLE_APP_PASSWORD:-}" ]]; then
    echo ""
    echo "⚠️  Skipping notarization — set APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_PASSWORD to enable."
  else
    echo ""
    echo "▶ Notarizing DMG (this may take a few minutes)..."
    xcrun notarytool submit "$DMG_PATH" \
      --apple-id "$APPLE_ID" \
      --team-id "$APPLE_TEAM_ID" \
      --password "$APPLE_APP_PASSWORD" \
      --wait

    echo "▶ Stapling notarization ticket..."
    xcrun stapler staple "$DMG_PATH"

    echo "▶ Verifying Gatekeeper acceptance..."
    spctl --assess --type open --context context:primary-signature -v "$DMG_PATH"
    echo "✅ Notarization complete — Gatekeeper will accept this DMG."
  fi
fi

# ── Sign DMG for Sparkle & update appcast.xml ─────────────────────────────────
SIGN_UPDATE="$(find ~/Library/Developer/Xcode/DerivedData -name "sign_update" 2>/dev/null | head -1)"
if [[ -n "$SIGN_UPDATE" && "$CONFIGURATION" == "Release" ]]; then
  echo ""
  echo "▶ Signing DMG for Sparkle..."
  # sign_update outputs:  sparkle:edSignature="..." length="..."
  SPARKLE_SIG=$("$SIGN_UPDATE" "$DMG_PATH")
  ED_SIG=$(echo "$SPARKLE_SIG" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
  DMG_SIZE=$(stat -f%z "$DMG_PATH")
  PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
  ENCLOSURE_URL="https://github.com/cpan-NS1/office-attendance-wifi/releases/download/v${MARKETING_VERSION}/${DMG_NAME}"

  APPCAST="$(pwd)/appcast.xml"

  # Build the new <item> block
  NEW_ITEM="    <item>
      <title>Version ${MARKETING_VERSION}</title>
      <sparkle:version>${CURRENT_PROJECT_VERSION}</sparkle:version>
      <sparkle:shortVersionString>${MARKETING_VERSION}</sparkle:shortVersionString>
      <pubDate>${PUB_DATE}</pubDate>
      <enclosure url=\"${ENCLOSURE_URL}\"
                 sparkle:edSignature=\"${ED_SIG}\"
                 length=\"${DMG_SIZE}\"
                 type=\"application/octet-stream\"/>
    </item>"

  # Prepend the new item into the existing appcast.xml (after <channel>)
  # Replace the first occurrence of the opening <item> tag with NEW_ITEM + original <item>
  ESCAPED_ITEM=$(printf '%s\n' "$NEW_ITEM" | sed 's/[\/&]/\\&/g')
  sed -i '' "s|    <item>|${ESCAPED_ITEM}\n    <item>|1" "$APPCAST"

  echo "✅ appcast.xml updated with v${MARKETING_VERSION}."
  echo ""
  echo "── appcast.xml snippet ──────────────────────────────────────────────────"
  echo "$NEW_ITEM"
  echo "─────────────────────────────────────────────────────────────────────────"
else
  [[ "$CONFIGURATION" == "Release" ]] && echo "⚠️  sign_update not found — skipping Sparkle signature. Build Sparkle first."
fi
