#!/bin/sh
# HOTFIX-02: Xcode Cloud pre-build hook — generates Flutter/Generated.xcconfig.
# Without this, Xcode Cloud archive fails:
#   "could not find included file 'Flutter/Generated.xcconfig' in search paths"
set -e
echo "--- SetAll: installing Flutter for Xcode Cloud ---"
if [ ! -d "$HOME/flutter" ]; then
  git clone https://github.com/flutter/flutter.git \
    --branch stable --single-branch --depth 1 "$HOME/flutter"
fi
export PATH="$HOME/flutter/bin:$PATH"
flutter --version
flutter pub get
echo "--- Generated.xcconfig created. Proceeding to Xcode build. ---"
