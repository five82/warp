#!/bin/bash
# Headless remote control for the Warp simulator, backed by the
# WarpTVDriver XCUIRemote test (see WarpTVDriver/RemoteDriver.swift).
#
#   scripts/tv-driver.sh start [app launch args]   # launches the app under the driver
#   scripts/tv-driver.sh send down down select     # remote presses, in order
#   scripts/tv-driver.sh stop                      # ends the driver run
#
# `start` blocks until the app is up (first run compiles the driver bundle, so
# allow a few minutes); screenshots still come from `simctl io`. The driver
# self-terminates after 30 minutes as a backstop.
set -euo pipefail

DIR=/tmp/warp-tv-driver
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode-beta.app}
DEST='platform=tvOS Simulator,name=Apple TV 4K (3rd generation)'
cd "$(dirname "$0")/.."

case "${1:-}" in
start)
  shift
  rm -rf "$DIR"
  mkdir -p "$DIR"
  TEST_RUNNER_DRIVER_APP_ARGS="${*:-}" xcodebuild test \
    -project Warp.xcodeproj -scheme WarpTVDriver \
    -destination "$DEST" -derivedDataPath DerivedDataTV \
    -only-testing:WarpTVDriver/RemoteDriver/testDrive \
    >"$DIR/xcodebuild.log" 2>&1 &
  echo $! >"$DIR/xcodebuild.pid"
  for _ in $(seq 1 300); do
    if [ -f "$DIR/ready" ]; then
      echo "driver ready"
      exit 0
    fi
    if ! kill -0 "$(cat "$DIR/xcodebuild.pid")" 2>/dev/null; then
      echo "driver exited early; see $DIR/xcodebuild.log" >&2
      exit 1
    fi
    sleep 1
  done
  echo "driver did not come up; see $DIR/xcodebuild.log" >&2
  exit 1
  ;;
send)
  shift
  [ -f "$DIR/ready" ] || { echo "driver not running; start it first" >&2; exit 1; }
  echo "$*" >"$DIR/cmd.tmp"
  mv "$DIR/cmd.tmp" "$DIR/cmd"
  # Wait for the driver to consume the command so sends can be sequenced.
  for _ in $(seq 1 150); do
    [ -f "$DIR/cmd" ] || exit 0
    sleep 0.2
  done
  echo "command not consumed; is the driver still running?" >&2
  exit 1
  ;;
stop)
  if [ -d "$DIR" ]; then
    echo quit >"$DIR/cmd.tmp" && mv "$DIR/cmd.tmp" "$DIR/cmd"
    [ -f "$DIR/xcodebuild.pid" ] && wait_pid=$(cat "$DIR/xcodebuild.pid") || wait_pid=""
    for _ in $(seq 1 30); do
      [ -n "$wait_pid" ] && kill -0 "$wait_pid" 2>/dev/null || break
      sleep 1
    done
    rm -f "$DIR/ready"
  fi
  ;;
*)
  echo "usage: $0 start [app launch args] | send <presses> | stop" >&2
  echo "presses: up down left right select menu playpause" >&2
  exit 1
  ;;
esac
