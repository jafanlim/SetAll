# Makefile for SetAll AI Workflow

.PHONY: bundle prompt test local-db build-web deploy-web deploy-preview

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

# 5. Build Flutter web (release, JS renderer default in Flutter 3.22+)
build-web:
	flutter build web --release --no-tree-shake-icons
	cp build/web/index.html build/web/app.html
	cp web/landing.html build/web/index.html
	cp web/download.html build/web/download.html
	cp web/robots.txt build/web/robots.txt
	cp web/sitemap.xml build/web/sitemap.xml
	@grep -q 'flutter_bootstrap' build/web/app.html || (echo "ERROR: app.html missing flutter_bootstrap — build step order is wrong!" && exit 1)
	@grep -q 'flutter_bootstrap' build/web/index.html && (echo "ERROR: index.html has flutter_bootstrap — landing page copy failed!" && exit 1) || true
	@echo "✓ build/web: app.html=Flutter, index.html=Landing"

# 6. Build and deploy to Firebase Hosting (production channel)
deploy-web: build-web
	firebase deploy --only hosting

# 7. Deploy to a preview channel (non-destructive — creates a temporary URL)
#    Usage: make deploy-preview channel=my-feature
deploy-preview: build-web
	firebase hosting:channel:deploy $(or $(channel),preview) --expires 7d
