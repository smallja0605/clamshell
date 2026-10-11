#!/bin/bash
# Builds dist/Clamshell.app (universal: arm64 + x86_64).
#   ./scripts/build-app.sh            ad-hoc signed, runs on this Mac
#   SIGN_ID="Developer ID Application: …" ./scripts/build-app.sh      signed for distribution
#   ./scripts/build-app.sh --dmg      also produce dist/Clamshell.dmg
#   ./scripts/build-app.sh --with-extras   also bundle the optional mascot packs from extras/ (see extras/README.md)
set -euo pipefail
cd "$(dirname "$0")/.."

DMG=0; EXTRAS=0
for arg in "$@"; do
  case "$arg" in
    --dmg) DMG=1 ;;
    --with-extras) EXTRAS=1 ;;
    *) echo "unknown option: $arg"; exit 2 ;;
  esac
done

VERSION="${VERSION:-0.1.0}"
APP="dist/Clamshell.app"
BUNDLE_ID="io.github.smallja0605.clamshell"

echo "Compiling release build (arm64 + x86_64)…"
swift build -c release --arch arm64 --arch x86_64 2>&1 | grep -v "x86_64 architecture is deprecated" || true
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path 2>/dev/null)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Clamshell" "$BIN/clamshell-hook" "$APP/Contents/MacOS/"
cp -R Resources/Sprites "$APP/Contents/Resources/Sprites"
rm -f "$APP/Contents/Resources/Sprites/preview.png"
cp -R Resources/Sounds "$APP/Contents/Resources/Sounds"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
DMG_BG=""
if [[ $EXTRAS == 1 ]]; then
  # an extra may bring its own app icon and installer background (extras/<name>/brand/); the last one found wins
  for brand in extras/*/brand; do
    [[ -f "$brand/AppIcon.icns" ]] && cp "$brand/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns" && echo "Icon from: $brand"
    [[ -f "$brand/dmg-background.tiff" ]] && DMG_BG="$brand/dmg-background.tiff"
  done
  mkdir -p "$APP/Contents/Resources/Mascots"
  for pack in extras/*/*.clamshellmascot; do
    [[ -d "$pack" ]] && cp -R "$pack" "$APP/Contents/Resources/Mascots/" && echo "Bundled extra: $(basename "$pack")"
  done
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Clamshell</string>
  <key>CFBundleDisplayName</key><string>Clamshell</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>Clamshell</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 smallja0605</string>
  <key>UTExportedTypeDeclarations</key>
  <array><dict>
    <key>UTTypeIdentifier</key><string>io.github.smallja0605.clamshell.mascot</string>
    <key>UTTypeDescription</key><string>Clamshell Mascot</string>
    <key>UTTypeConformsTo</key><array><string>com.apple.package</string><string>public.composite-content</string></array>
    <key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>clamshellmascot</string></array></dict>
  </dict></array>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Clamshell Mascot</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Owner</string>
      <key>LSItemContentTypes</key><array><string>io.github.smallja0605.clamshell.mascot</string></array>
    </dict>
    <dict>
      <key>CFBundleTypeName</key><string>GIF image</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key><array><string>com.compuserve.gif</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

xattr -cr "$APP"
if [[ -n "${SIGN_ID:-}" ]]; then
  echo "Signing with: $SIGN_ID"
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP/Contents/MacOS/clamshell-hook"
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
else
  echo "No SIGN_ID set — ad-hoc signing (fine for local use)."
  codesign --force --sign - "$APP/Contents/MacOS/clamshell-hook" >/dev/null
  codesign --force --sign - "$APP" >/dev/null
fi
echo "Built $APP"

if [[ $DMG == 1 ]]; then
  DMG_BACKGROUND="$DMG_BG" scripts/make-dmg.sh "$APP" dist/Clamshell.dmg
fi
