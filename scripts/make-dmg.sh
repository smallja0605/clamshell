#!/bin/bash
# Builds a styled installer image: night-beach artwork, the app and an Applications shortcut laid out on it.
#   scripts/make-dmg.sh dist/Clamshell.app dist/Clamshell.dmg
# Uses Finder (AppleScript) to store the window layout, so the first run may ask for permission to control Finder.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:?usage: make-dmg.sh <Clamshell.app> <output.dmg>}"
OUT="${2:?usage: make-dmg.sh <Clamshell.app> <output.dmg>}"
VOL="Clamshell"
BG="${DMG_BACKGROUND:-design/dmg/background.tiff}"
[[ -f "$BG" ]] || { echo "missing $BG — run tools/make_dmg_assets.sh"; exit 1; }

# Window geometry (points). Must match tools/make_dmg_background.swift.
WIN_W=660; WIN_H=400; WIN_X=200; WIN_Y=120
# Finder's window bounds include its chrome: the title bar (~31pt) plus the path bar (~29pt) when the viewer has it on.
# Reserving both keeps the top WIN_H points always visible; the artwork is taller (440) so nothing is left blank below.
CHROME=60
ICON_SIZE=110; APP_X=150; APPS_X=510; ICON_Y=200

# An image of the same name that is still mounted would make Finder address the wrong disk.
for d in /Volumes/"$VOL" /Volumes/"$VOL "[0-9]*; do
  [[ -d "$d" ]] && hdiutil detach "$d" -quiet 2>/dev/null || true
done

WORK="$(mktemp -d)"; RW="$WORK/rw.dmg"
trap 'hdiutil detach "/Volumes/$VOL" -quiet -force 2>/dev/null || true; rm -rf "$WORK"' EXIT

hdiutil create -size 64m -fs HFS+ -volname "$VOL" -ov "$RW" >/dev/null
hdiutil attach "$RW" -noverify -noautoopen -mountpoint "/Volumes/$VOL" >/dev/null

cp -R "$APP" "/Volumes/$VOL/"
ln -s /Applications "/Volumes/$VOL/Applications"
mkdir "/Volumes/$VOL/.background"
cp "$BG" "/Volumes/$VOL/.background/background.tiff"
cp "$APP/Contents/Resources/AppIcon.icns" "/Volumes/$VOL/.VolumeIcon.icns"
SetFile -a C "/Volumes/$VOL" 2>/dev/null || true

APP_NAME="$(basename "$APP")"
osascript <<OSA
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {$WIN_X, $WIN_Y, $((WIN_X + WIN_W)), $((WIN_Y + WIN_H + CHROME))}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to $ICON_SIZE
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "$APP_NAME" of container window to {$APP_X, $ICON_Y}
    set position of item "Applications" of container window to {$APPS_X, $ICON_Y}
    update without registering applications
    delay 1
    close
    open
    delay 2
    close
  end tell
end tell
OSA

sync; sleep 1
if [[ -n "${DMG_DEBUG:-}" ]]; then python3 -c "
import re;d=open('/Volumes/$VOL/.DS_Store','rb').read();print('DS_Store bounds before detach:',[m.group().decode() for m in re.finditer(rb'\{\{[-0-9 ,]+\}, ?\{[-0-9 ,]+\}\}',d)])"; fi
hdiutil detach "/Volumes/$VOL" -quiet || { sleep 2; hdiutil detach "/Volumes/$VOL" -quiet -force; }
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
echo "Built $OUT"
