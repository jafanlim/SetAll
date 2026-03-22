#!/bin/sh
# SetAll — Xcode Cloud pre-build hook
# Generates Flutter/Generated.xcconfig AND CocoaPods xcfilelists before Xcode builds.
# Without flutter pub get: "could not find included file Flutter/Generated.xcconfig"
# Without pod install: "Unable to load contents of file list: Pods-Runner-*.xcfilelist"
set -e

echo "--- SetAll: installing Flutter ---"
if [ ! -d "$HOME/flutter" ]; then
  git clone https://github.com/flutter/flutter.git \
    --branch stable --single-branch --depth 1 "$HOME/flutter"
fi
export PATH="$HOME/flutter/bin:$PATH"

echo "--- Flutter version ---"
flutter --version

echo "--- flutter pub get ---"
flutter pub get

echo "--- pod install ---"
cd ios
pod install --repo-update
cd ..

echo "--- Pre-build complete ---"
