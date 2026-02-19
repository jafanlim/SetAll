#!/usr/bin/env bash
# Build iOS from command line and save full log so we can inspect failures.
# Run from project root: ./scripts/build_ios_and_save_log.sh
# Log is written to: build_log_ios.txt

set -e
PROJ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJ_ROOT"
LOG_FILE="${1:-$PROJ_ROOT/build_log_ios.txt}"
WORKSPACE="$PROJ_ROOT/ios/Runner.xcworkspace"

echo "Building iOS (Runner workspace, Debug, generic device)..."
echo "Log will be saved to: $LOG_FILE"
echo ""

# Build for generic iOS device (arm64) so we don't need a connected device
xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme Runner \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -quiet \
  2>&1 | tee "$LOG_FILE"

echo ""
echo "Build finished. Full log saved to: $LOG_FILE"
