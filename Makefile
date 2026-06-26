# Makefile for SetAll AI Workflow

.PHONY: bundle prompt test local-db tailwind build-web deploy-web bump bump-patch bump-minor bump-major

# 1. Bundles the current state of critical files
bundle:
	npx repomix --include "lib/data/models/*.dart,lib/core/services/*.dart,lib/data/repositories/*.dart,supabase/migrations/*.sql" --output ai_context.txt

# 2. Feeds the bundle AND your prompt to Gemini CLI
# Usage: make prompt msg="Fix the BalanceService to use universal_usd_amount"
prompt: bundle
	cat SYSTEM_INSTRUCTIONS.md PROJECT_LEDGER.md ai_context.txt | gemini-cli --prompt "$(msg)"

# 3. The Math Guard
test:
	flutter test test/core/services/balance_service_test.dart

# 4. Start local Supabase sandbox
local-db:
	supabase start

# 5. Generate static Tailwind CSS for portal + insights (replaces CDN)
tailwind:
	npx tailwindcss -c web/tailwind.config.js -i web/tailwind-input.css -o web/styles.css --minify
	@echo "✓ web/styles.css generated ($$(wc -c < web/styles.css) bytes)"

# 6. Build Flutter web (release, JS renderer default in Flutter 3.22+)
build-web: tailwind
	flutter build web --release --no-tree-shake-icons --dart-define-from-file=.env.client
	@if grep -rq 'your-project' build/web; then \
	  echo "ERROR: build/web contains the 'your-project' placeholder — .env.client is not filled with real values (SUPABASE_URL/keys). Refusing to ship: a placeholder Supabase URL breaks ALL auth."; \
	  exit 1; \
	fi
	cp web/app.html        build/web/app.html
	cp "new website/landing page.html" build/web/index.html
	cp web/login.html      build/web/login.html
	cp web/portal.html     build/web/portal.html
	cp web/support.html    build/web/support.html
	cp web/privacy.html    build/web/privacy.html
	cp web/terms.html           build/web/terms.html
	cp web/download.html        build/web/download.html
	cp web/reset-password.html  build/web/reset-password.html
	cp web/insights.html        build/web/insights.html
	cp web/styles.css            build/web/styles.css
	cp web/_redirects           build/web/_redirects
	cp web/robots.txt           build/web/robots.txt
	cp web/sitemap.xml          build/web/sitemap.xml
	@grep -q 'flutter_bootstrap' build/web/app.html || (echo "ERROR: app.html missing flutter_bootstrap — build step order is wrong!" && exit 1)
	@grep -q 'flutter_bootstrap' build/web/index.html && (echo "ERROR: index.html has flutter_bootstrap — landing page copy failed!" && exit 1) || true
	@echo "✓ build/web ready: app.html=Flutter, index.html=Landing, all static pages copied"
	@for page in login portal support privacy terms download reset-password insights; do \
	  grep -q "setall.app/$$page" web/sitemap.xml || echo "WARN: /$$page is not in sitemap.xml"; \
	done
	@echo "✓ sitemap check complete"

# 7. Build and deploy to Netlify production
#    Requires: npm install -g netlify-cli && netlify login
deploy-web: bump build-web
	netlify deploy --prod --dir=build/web
	git add pubspec.yaml
	git commit -m "chore: bump build number to $$(grep '^version:' pubspec.yaml | sed 's/version: *//')"
	git push origin main

# 8. Version bump helpers (build number only, or semantic bump)
bump:
	@bash scripts/bump_version.sh

bump-patch:
	@bash scripts/bump_version.sh --patch

bump-minor:
	@bash scripts/bump_version.sh --minor

bump-major:
	@bash scripts/bump_version.sh --major
