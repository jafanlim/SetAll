#!/bin/sh
# Sets up the build/ symlink to /tmp to avoid iCloud Drive interference.
# The project lives in ~/Documents (iCloud-synced). iCloud adds com.apple.FinderInfo
# to framework directories, which causes codesign to fail.
# By symlinking build/ → /tmp/setall_flutter_build, build artifacts stay outside iCloud.
#
# Run this once after cloning, and again after each system reboot (since /tmp is cleared).
#
# Usage: sh ios/scripts/setup_build_dir.sh

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_LINK="$PROJECT_DIR/build"
BUILD_TARGET="/tmp/setall_flutter_build"

mkdir -p "$BUILD_TARGET"

if [ -L "$BUILD_LINK" ]; then
  echo "Symlink already exists: $BUILD_LINK -> $(readlink "$BUILD_LINK")"
elif [ -d "$BUILD_LINK" ]; then
  echo "Moving existing build/ to $BUILD_TARGET ..."
  cp -a "$BUILD_LINK/." "$BUILD_TARGET/" 2>/dev/null || true
  rm -rf "$BUILD_LINK"
  ln -s "$BUILD_TARGET" "$BUILD_LINK"
  echo "Done."
else
  ln -s "$BUILD_TARGET" "$BUILD_LINK"
  echo "Created: $BUILD_LINK -> $BUILD_TARGET"
fi
