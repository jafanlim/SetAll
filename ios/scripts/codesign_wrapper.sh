#!/bin/sh
# Codesign wrapper for macOS Sequoia/Tahoe.
# iCloud Drive (project in ~/Documents) adds com.apple.FinderInfo to framework
# directories, causing codesign to fail with "resource fork / detritus not allowed".
# This wrapper strips FinderInfo from the target and its .framework container before signing.

last=""
for a in "$@"; do last="$a"; done

if [ -n "$last" ]; then
  xattr -d com.apple.FinderInfo "$last" 2>/dev/null || true
  parent=$(dirname "$last")
  case "$parent" in
    *.framework) xattr -d com.apple.FinderInfo "$parent" 2>/dev/null || true;;
  esac
  case "$last" in
    *.framework) xattr -d com.apple.FinderInfo "$last" 2>/dev/null || true;;
  esac
fi

exec /usr/bin/codesign "$@"
