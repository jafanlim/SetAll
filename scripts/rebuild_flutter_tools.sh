#!/usr/bin/env bash
# Rebuild Flutter tools snapshot after patching native_assets code
# This is required for the codesign fixes to take effect

set -e

echo "Rebuilding Flutter tools snapshot..."
FLUTTER_ROOT="/opt/homebrew/share/flutter"
SNAPSHOT_PATH="$FLUTTER_ROOT/bin/cache/flutter_tools.snapshot"

if [ ! -d "$FLUTTER_ROOT" ]; then
  echo "Error: Flutter not found at $FLUTTER_ROOT"
  exit 1
fi

# Remove old snapshot
if [ -f "$SNAPSHOT_PATH" ]; then
  echo "Removing old snapshot..."
  rm -f "$SNAPSHOT_PATH"
fi

# Rebuild by running flutter --version
echo "Rebuilding snapshot (this may take a moment)..."
cd "$FLUTTER_ROOT"
flutter --version > /dev/null 2>&1

if [ -f "$SNAPSHOT_PATH" ]; then
  echo "✓ Flutter tools snapshot rebuilt successfully"
else
  echo "✗ Failed to rebuild snapshot"
  exit 1
fi

echo ""
echo "Next steps:"
echo "1. Clean your project: flutter clean"
echo "2. Build from Xcode (open ios/Runner.xcworkspace)"
echo "3. The codesign fix should now work for paths with spaces"
