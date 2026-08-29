#!/bin/bash
# Builds the live-resize-patched Libmpv.xcframework that Vendor/MPVKit uses.
#
# MPVKit's Metal/MoltenVK backend cannot resize a live video output
# (https://github.com/mpvkit/MPVKit/issues/3). patches/mpvkit adds drawable-
# size polling to mpv's MoltenVK context so rotation and window resizes work
# without rebuilding the player. This script rebuilds only libmpv from
# source; every other dependency downloads prebuilt from MPVKit's releases.
#
# Takes roughly 30-60 minutes (FFmpeg compiles from source). Requires:
#   brew install meson ninja wget
#
# Usage: ./scripts/build-libmpv.sh [work-dir]

set -euo pipefail

MPVKIT_TAG="0.41.0"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="${1:-$(mktemp -d /tmp/mpvkit-build.XXXX)}"
DEST="$REPO_ROOT/Vendor/MPVKit/Frameworks"

echo "==> Cloning MPVKit $MPVKIT_TAG into $WORK_DIR"
if [ ! -d "$WORK_DIR/.git" ]; then
    git clone --depth 1 --branch "$MPVKIT_TAG" https://github.com/mpvkit/MPVKit.git "$WORK_DIR"
fi

echo "==> Applying local patches"
cp "$REPO_ROOT"/patches/mpvkit/*.patch "$WORK_DIR/Sources/BuildScripts/patch/libmpv/"

# The FFmpeg filter allowlist lives in the build script itself, not in a
# patchable source tree, so it is extended in place (idempotently).
BUILD_MAIN="$WORK_DIR/Sources/BuildScripts/XCFrameworkBuild/main.swift"
if ! grep -q 'enable-filter=acompressor' "$BUILD_MAIN"; then
    sed -i '' 's|"--enable-filter=vflip", "--enable-filter=volume",|"--enable-filter=vflip", "--enable-filter=volume",\
        "--enable-filter=acompressor", "--enable-filter=alimiter",|' "$BUILD_MAIN"
    grep -q 'enable-filter=acompressor' "$BUILD_MAIN" || { echo "error: could not extend the FFmpeg filter list in $BUILD_MAIN" >&2; exit 1; }
fi

# tvOS slices serve the TakeupTV target. The live-resize patch compiles into
# them but is inert on a fixed-size screen (it only polls drawableSize for
# changes); one xcframework keeps both apps on the same mpv/ffmpeg build.
echo "==> Building (ios + tvos + simulators)"
cd "$WORK_DIR"
export PATH="/opt/homebrew/bin:$PATH"
make build platform=ios,isimulator,tvos,tvsimulator

mkdir -p "$DEST"
for NAME in Libmpv Libavfilter; do
    echo "==> Installing $NAME.xcframework into $DEST"
    # libmpv is left unpacked under dist/release/xcframework; the FFmpeg
    # frameworks only exist as release zips.
    XCFRAMEWORK=$(find "$WORK_DIR/dist" -name "$NAME.xcframework" -type d | head -1)
    ZIP="$WORK_DIR/dist/release/$NAME.xcframework.zip"
    rm -rf "$DEST/$NAME.xcframework"
    if [ -n "$XCFRAMEWORK" ]; then
        cp -R "$XCFRAMEWORK" "$DEST/"
    elif [ -f "$ZIP" ]; then
        unzip -q "$ZIP" "$NAME.xcframework/*" -d "$DEST"
    else
        echo "error: $NAME.xcframework not found under $WORK_DIR/dist" >&2
        exit 1
    fi
done

echo "==> Done. Rebuild the app (xcodegen generate && xcodebuild ...) to pick it up."
