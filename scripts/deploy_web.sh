#!/usr/bin/env bash
# deploy_web.sh — Build Flutter web (CanvasKit) and deploy to Firebase Hosting.
#
# Usage:
#   ./scripts/deploy_web.sh              # deploy to production (live channel)
#   ./scripts/deploy_web.sh --preview    # deploy to a 7-day preview channel
#   ./scripts/deploy_web.sh --preview my-branch  # named preview channel

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

PREVIEW=false
CHANNEL="preview"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preview)
      PREVIEW=true
      if [[ $# -gt 1 && "$2" != --* ]]; then
        CHANNEL="$2"; shift
      fi
      ;;
  esac
  shift
done

echo "▶ SetAll Web Deploy"
echo "  Project: $PROJECT_ROOT"
echo "  Mode:    $([ "$PREVIEW" = true ] && echo "preview ($CHANNEL)" || echo "production")"
echo ""

# ── 1. Verify tools ──────────────────────────────────────────────────────────
command -v flutter  >/dev/null 2>&1 || { echo "✗ flutter not found in PATH"; exit 1; }
command -v firebase >/dev/null 2>&1 || { echo "✗ firebase not found. Run: npm install -g firebase-tools"; exit 1; }

# ── 2. Flutter web build ─────────────────────────────────────────────────────
echo "▶ Building Flutter web (CanvasKit, release)…"
cd "$PROJECT_ROOT"
flutter build web \
  --release \
  --web-renderer canvaskit \
  --dart-define=FLUTTER_WEB_CANVASKIT_URL=https://www.gstatic.com/flutter-canvaskit/
echo "✓ Build complete → build/web"
echo ""

# ── 3. Deploy ────────────────────────────────────────────────────────────────
if [ "$PREVIEW" = true ]; then
  echo "▶ Deploying to preview channel: $CHANNEL (expires in 7 days)…"
  firebase hosting:channel:deploy "$CHANNEL" --expires 7d
else
  echo "▶ Deploying to production (live channel)…"
  firebase deploy --only hosting
fi

echo ""
echo "✓ Deploy complete!"
