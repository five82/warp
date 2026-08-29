#!/bin/bash
# Unattended channel-flip measurement on the physical Apple TV.
#
#   scripts/device-surf.sh [flips] [start-channel]
#
# Builds, installs, and launches Warp with -surf, then prints every
# warp.tune / warp.surface / warp.display line the run produced.
#
# The box must be AWAKE: a sleeping Apple TV refuses foreground app launches
# and nothing on the network can wake it. Press a button on the remote first.
#
# scripts/mock-loom.py must already be running on this Mac.
set -euo pipefail

FLIPS=${1:-12}
CHANNEL=${2:-1}
UDID=35085BEA-A61D-54EA-A44D-EABC64DC0EDF
SERVER=${WARP_SERVER:-http://10.100.90.134:8098}
LOG=/tmp/warp-device-console.log

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode-beta.app}
cd "$(dirname "$0")/.."

xcodebuild -project Warp.xcodeproj -scheme Warp \
  -destination 'platform=tvOS,name=Living Room Apple TV' \
  -derivedDataPath DerivedDataTVDevice -allowProvisioningUpdates build >/dev/null

xcrun devicectl device install app --device "$UDID" \
  DerivedDataTVDevice/Build/Products/Debug-appletvos/Warp.app >/dev/null

# The run lasts 8 s per flip plus a 6 s settle; --console blocks until the app
# exits, so it is killed on a timer rather than waited on.
RUNTIME=$(( FLIPS * 8 + 25 ))
rm -f "$LOG"
# '--' matters: devicectl otherwise parses '-server' as one of its own options.
xcrun devicectl device process launch --terminate-existing --console --device "$UDID" -- \
  xyz.five82.warp -server "$SERVER" -channel "$CHANNEL" -surf "$FLIPS" >"$LOG" 2>&1 &
CONSOLE_PID=$!
sleep "$RUNTIME"
kill "$CONSOLE_PID" 2>/dev/null || true

echo "--- $LOG ---"
grep -aoE 'warp\.(tune|surface|display|surf)[^"]{0,120}' "$LOG" || {
  echo "no measurements captured; check $LOG (is the box awake?)" >&2
  exit 1
}
