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

# 5. Build Flutter web (release, CanvasKit renderer for best fidelity)
build-web:
	flutter build web --release --no-tree-shake-icons
	cp build/web/index.html build/web/app.html
	cp web/landing.html build/web/index.html
	cp web/robots.txt build/web/robots.txt
	cp web/sitemap.xml build/web/sitemap.xml

# 6. Build and deploy to Firebase Hosting (production channel)
deploy-web: build-web
	firebase deploy --only hosting

# 7. Deploy to a preview channel (non-destructive — creates a temporary URL)
#    Usage: make deploy-preview channel=my-feature
deploy-preview: build-web
	firebase hosting:channel:deploy $(or $(channel),preview) --expires 7d
