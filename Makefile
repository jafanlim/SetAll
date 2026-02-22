# Makefile for SetAll AI Workflow

.PHONY: bundle prompt test local-db

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
