#!/bin/bash
# Regenerates the installer window's artwork (1x + 2x in one TIFF). Output is committed, so a normal build needs none of this.
#   tools/make_dmg_assets.sh                      -> design/dmg/background.tiff        (the original crab)
#   tools/make_dmg_assets.sh --gif crab.gif       -> extras/claude-crab/brand/dmg-background.tiff  (artwork cropped from a GIF frame)
# Needs python3 and the macOS swift/sips/tiffutil (plus ImageMagick for --gif).
set -euo pipefail
cd "$(dirname "$0")/.."
GIF=""; FRAME=20; OUT="design/dmg/background.tiff"; SCALE=0.6; TEXT1="移動檔案"; TEXT2="1分30秒"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gif) GIF="$2"; shift 2 ;;
    --frame) FRAME="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --scale) SCALE="$2"; shift 2 ;;
    *) TEXT1="$1"; TEXT2="${2:-$TEXT2}"; shift 2 ;;
  esac
done
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
if [[ -n "$GIF" ]]; then
  magick "${GIF}[${FRAME}]" -trim +repage "$TMP/crab.png"
  [[ "$OUT" == "design/dmg/background.tiff" ]] && OUT="extras/claude-crab/brand/dmg-background.tiff"
  SCALE=0.4      # that artwork has 10px pixels; 0.4 makes them 4pt
else
  python3 tools/make_sprites.py --export-large "$TMP/crab.png" 5
fi
swift tools/make_dmg_background.swift "$TMP" "$TMP/crab.png" "$TMP/crab.png" "$TEXT1" "$TEXT2" "$SCALE"
sips -s format tiff "$TMP/bg.png" --out "$TMP/bg.tiff" >/dev/null
sips -s format tiff "$TMP/bg@2x.png" --out "$TMP/bg2.tiff" >/dev/null
mkdir -p "$(dirname "$OUT")"
tiffutil -cat "$TMP/bg.tiff" "$TMP/bg2.tiff" -out "$OUT" 2>/dev/null
echo "wrote $OUT"
