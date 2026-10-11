#!/bin/bash
# Turns a folder of snapshots (written by scripts/simulate.sh with CLAMSHELL_SNAP=<dir>) into an animated preview GIF.
# The item is drawn right-aligned on a dark bar, like in the menu bar, where it grows leftwards. Plays at 2x speed.
#   tools/make_preview.sh <snapshot-dir> <output.gif>
# Needs ImageMagick.
set -euo pipefail
SNAPS="${1:?snapshot dir}"; OUT="${2:?output gif}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FILES=($(ls "$SNAPS"/snap_*.png | awk 'NR % 2 == 1'))
MAXW=0; MAXH=0
for f in "${FILES[@]}"; do
  read -r w h < <(magick identify -format '%w %h\n' "$f")
  (( w > MAXW )) && MAXW=$w; (( h > MAXH )) && MAXH=$h
done
CW=$((MAXW + 64)); CH=$((MAXH + 28))
i=0
for f in "${FILES[@]}"; do
  magick -size "${CW}x${CH}" xc:'#1d2147' "$f" -gravity East -geometry +28+0 -composite "$TMP/$(printf %04d $i).png"
  i=$((i + 1))
done
# hold the last frame for a moment before looping
magick -delay 10 -loop 0 "$TMP"/*.png \( +clone -set delay 120 \) +swap +delete -dither None -colors 64 -layers Optimize "$OUT" 2>/dev/null \
  || magick -delay 10 -loop 0 "$TMP"/*.png -dither None -colors 64 -layers Optimize "$OUT"
echo "wrote $OUT (${#FILES[@]} frames, ${CW}x${CH})"
