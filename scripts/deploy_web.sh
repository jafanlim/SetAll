#!/usr/bin/env bash
# deploy_web.sh — Build Flutter web + static pages and deploy to Netlify.
#
# Usage:
#   ./scripts/deploy_web.sh              # deploy to production
#   ./scripts/deploy_web.sh --draft      # deploy a draft (preview URL only)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

DRAFT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --draft) DRAFT=true ;;
  esac
  shift
done

echo "▶ SetAll Web Deploy (Netlify)"
echo "  Project: $PROJECT_ROOT"
echo "  Mode:    $([ "$DRAFT" = true ] && echo "draft preview" || echo "production")"
echo ""

# ── 1. Verify tools ──────────────────────────────────────────────────────────
command -v flutter >/dev/null 2>&1 || { echo "✗ flutter not found in PATH"; exit 1; }
command -v netlify >/dev/null 2>&1 || { echo "✗ netlify not found. Run: npm install -g netlify-cli"; exit 1; }

# ── 2. Generate static Tailwind CSS ──────────────────────────────────────────
echo "▶ Building Tailwind CSS…"
cd "$PROJECT_ROOT"
npx tailwindcss -c web/tailwind.config.js -i web/tailwind-input.css -o web/styles.css --minify
echo "✓ web/styles.css generated ($(wc -c < web/styles.css) bytes)"
echo ""

# ── 3. Flutter web build ─────────────────────────────────────────────────────
echo "▶ Building Flutter web (release)…"
flutter build web --release --no-tree-shake-icons
echo "✓ Build complete → build/web"
echo ""

# ── 4. Copy static pages into build ──────────────────────────────────────────
echo "▶ Copying static pages…"
cp web/app.html            build/web/app.html
cp "new website/landing page.html" build/web/index.html
cp web/login.html          build/web/login.html
cp web/portal.html         build/web/portal.html
cp web/support.html        build/web/support.html
cp web/privacy.html        build/web/privacy.html
cp web/terms.html          build/web/terms.html
cp web/download.html       build/web/download.html
cp web/reset-password.html build/web/reset-password.html
cp web/insights.html       build/web/insights.html
cp web/styles.css          build/web/styles.css
cp web/_redirects          build/web/_redirects
cp web/robots.txt          build/web/robots.txt
cp web/sitemap.xml         build/web/sitemap.xml
echo "✓ Static pages copied"
echo ""

# ── 5. Deploy ────────────────────────────────────────────────────────────────
if [ "$DRAFT" = true ]; then
  echo "▶ Deploying draft to Netlify (preview URL only)…"
  netlify deploy --dir=build/web
else
  echo "▶ Deploying to Netlify production…"
  netlify deploy --prod --dir=build/web
fi

echo ""
echo "✓ Deploy complete!"
