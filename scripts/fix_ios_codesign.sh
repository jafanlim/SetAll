#!/usr/bin/env bash
# Fixes iOS codesign failure: "resource fork, Finder information, or similar detritus not allowed"
# (caused by com.apple.provenance on macOS Sequoia when copying Flutter frameworks)
#
# Run once before `flutter run` when building for a physical iOS device:
#   chmod +x scripts/fix_ios_codesign.sh
#   ./scripts/fix_ios_codesign.sh
# Then: flutter clean && flutter run

set -e
cd "$(dirname "$0")/.."

echo "Stripping extended attributes from project..."
xattr -cr . 2>/dev/null || true

echo "Stripping extended attributes from Flutter SDK cache (may ask for password)..."
for FLUTTER_ROOT in "/opt/homebrew/share/flutter" "$HOME/development/flutter" "$HOME/flutter"; do
  if [ -d "$FLUTTER_ROOT" ]; then
    if sudo xattr -cr "$FLUTTER_ROOT" 2>/dev/null; then
      echo "Stripped: $FLUTTER_ROOT"
      break
    fi
  fi
done

echo "Cleaning build..."
flutter clean
flutter pub get

echo "Done. Run: flutter run"
