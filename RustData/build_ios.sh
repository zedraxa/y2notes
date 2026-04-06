#!/usr/bin/env bash
# build_ios.sh — Cross-compile libY2Data.a for iOS (arm64)
#
# Prerequisites:
#   rustup target add aarch64-apple-ios
#   rustup target add aarch64-apple-ios-sim    # for simulator
#
# Usage:
#   ./build_ios.sh              # default: release build for device
#   ./build_ios.sh sim          # release build for simulator
#   ./build_ios.sh universal    # lipo-merge device + simulator

set -euo pipefail
cd "$(dirname "$0")"

PROFILE="release"
CARGO_FLAGS="--release"

DEVICE_TARGET="aarch64-apple-ios"
SIM_TARGET="aarch64-apple-ios-sim"

OUT_DIR="target/ios"
LIB_NAME="liby2data.a"

build_target() {
    local target="$1"
    echo "▸ Building for $target ($PROFILE)"
    cargo build $CARGO_FLAGS --target "$target"
}

copy_lib() {
    local target="$1"
    local dest="$2"
    mkdir -p "$(dirname "$dest")"
    cp "target/$target/$PROFILE/$LIB_NAME" "$dest"
    echo "  → $dest"
}

case "${1:-device}" in
    device)
        build_target "$DEVICE_TARGET"
        copy_lib "$DEVICE_TARGET" "$OUT_DIR/device/$LIB_NAME"
        ;;
    sim)
        build_target "$SIM_TARGET"
        copy_lib "$SIM_TARGET" "$OUT_DIR/simulator/$LIB_NAME"
        ;;
    universal)
        build_target "$DEVICE_TARGET"
        build_target "$SIM_TARGET"
        copy_lib "$DEVICE_TARGET" "$OUT_DIR/device/$LIB_NAME"
        copy_lib "$SIM_TARGET"   "$OUT_DIR/simulator/$LIB_NAME"

        mkdir -p "$OUT_DIR/universal"
        xcrun lipo -create \
            "$OUT_DIR/device/$LIB_NAME" \
            "$OUT_DIR/simulator/$LIB_NAME" \
            -output "$OUT_DIR/universal/$LIB_NAME"
        echo "  → $OUT_DIR/universal/$LIB_NAME (fat binary)"
        ;;
    *)
        echo "Usage: $0 {device|sim|universal}"
        exit 1
        ;;
esac

echo "✔ Done.  Header: include/y2data.h"
