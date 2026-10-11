#!/bin/bash
# Drives the real app + real hook helper through a work cycle in an isolated home directory
# (nothing under ~/.claude is touched) and leaves PNG snapshots of the menu-bar item in $SNAP.
set -u
cd "$(dirname "$0")/.."
APP="${APP:-dist/Clamshell.app}"
export CLAMSHELL_HOME="${CLAMSHELL_HOME:-$(mktemp -d)/home}"
export CLAMSHELL_NO_INSTALL=1
SNAP="${SNAP:-/tmp/clamshell-snap}"; rm -rf "$SNAP"
HOOK="$APP/Contents/MacOS/clamshell-hook"
mkdir -p "$CLAMSHELL_HOME"
CLAMSHELL_SNAP="$SNAP" "$APP/Contents/MacOS/Clamshell" ${APP_ARGS:-} >/dev/null 2>&1 &
APP_PID=$!
sleep 1.5
send() { printf '{"session_id":"sim","cwd":"/work/demo","tool_name":"%s"}' "${2:-}" | "$HOOK" "$1"; }
send start;            sleep 1
send prompt;           sleep 5
send pre Bash;         sleep 4
send post;             sleep 2
send pre Edit;         sleep 4
send permreq;          sleep 4
send post;             sleep 2
send stop;             sleep 6
kill $APP_PID 2>/dev/null
echo "snapshots: $SNAP ($(ls "$SNAP" | wc -l | tr -d ' ') files)"
ls "$SNAP" | sed -E 's/snap_[0-9]+_//' | uniq -c
