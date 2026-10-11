#!/bin/bash
# Builds the files to attach to a GitHub release: the default build (no extras) as .dmg and .zip, plus SHA-256 sums.
#   ./scripts/release.sh 0.1.0        -> dist/release/v0.1.0/
# For a signed and notarized release, set SIGN_ID (see build-app.sh); this script does not notarize.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: release.sh <version>   e.g. release.sh 0.1.0}"
OUT="dist/release/v$VERSION"
rm -rf "$OUT"; mkdir -p "$OUT"

# The public build never bundles the optional extras.
VERSION="$VERSION" ./scripts/build-app.sh --dmg
APP=dist/Clamshell.app

# Sanity checks: this must be the plain build, at the right version, for both Mac architectures.
[[ ! -e "$APP/Contents/Resources/Mascots" ]] || { echo "refusing: extras are bundled in this build"; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$VERSION" ]] || { echo "version mismatch"; exit 1; }
ARCHS="$(lipo -archs "$APP/Contents/MacOS/Clamshell")"
[[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || { echo "not a universal binary: $ARCHS"; exit 1; }
cmp -s "$APP/Contents/Resources/AppIcon.icns" Resources/AppIcon.icns || { echo "icon is not the default one"; exit 1; }

cp dist/Clamshell.dmg "$OUT/Clamshell-$VERSION.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/Clamshell-$VERSION.zip"
(cd "$OUT" && shasum -a 256 Clamshell-"$VERSION".dmg Clamshell-"$VERSION".zip > SHA256SUMS.txt)
echo; echo "Release files in $OUT:"; ls -la "$OUT" | tail -n +2
cat "$OUT/SHA256SUMS.txt"
