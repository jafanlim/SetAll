#!/usr/bin/env bash
# scripts/bump_version.sh
#
# Auto-increments the build number (+N) in pubspec.yaml.
# Optionally bumps the semantic version (MAJOR.MINOR.PATCH) via --patch / --minor / --major.
#
# Usage:
#   ./scripts/bump_version.sh           # bumps build number only:  1.4.1+15 → 1.4.1+16
#   ./scripts/bump_version.sh --patch   # bumps patch + build:      1.4.1+15 → 1.4.2+16
#   ./scripts/bump_version.sh --minor   # bumps minor + build:      1.4.1+15 → 1.5.0+16
#   ./scripts/bump_version.sh --major   # bumps major + build:      1.4.1+15 → 2.0.0+16
#
# Writes the result back into pubspec.yaml and prints the new version.

set -euo pipefail

PUBSPEC="pubspec.yaml"

# ── Read current version ──────────────────────────────────────────────────
current=$(grep '^version:' "$PUBSPEC" | sed 's/version: *//')
semver="${current%+*}"   # e.g. 1.4.1
build="${current##*+}"   # e.g. 15

IFS='.' read -r major minor patch <<< "$semver"

# ── Apply bump type ───────────────────────────────────────────────────────
bump="${1:-}"
case "$bump" in
  --major)
    major=$((major + 1)); minor=0; patch=0 ;;
  --minor)
    minor=$((minor + 1)); patch=0 ;;
  --patch)
    patch=$((patch + 1)) ;;
  "")
    ;;  # build-only bump
  *)
    echo "Unknown flag: $bump" >&2
    echo "Usage: $0 [--patch|--minor|--major]" >&2
    exit 1 ;;
esac

new_build=$((build + 1))
new_version="${major}.${minor}.${patch}+${new_build}"

# ── Write back ────────────────────────────────────────────────────────────
# Use sed with a temp file (works on both macOS BSD sed and GNU sed)
sed "s/^version: .*/version: ${new_version}/" "$PUBSPEC" > "${PUBSPEC}.tmp"
mv "${PUBSPEC}.tmp" "$PUBSPEC"

echo "✓ Version bumped: ${current} → ${new_version}"
