SetAll: Gemini CLI Implementation Map

This map defines the rigid loop between your local tools and the Gemini CLI. Do not deviate from this loop.

Phase 1: The Context Pipeline (repomix + Makefile)



Phase 2: The AI Development Loop (How you actually work now)

When you encounter a bug or need a feature, follow this exact sequence:

Step 1: Local Sandbox (Supabase Docker)

Never let Gemini write a migration that you push directly to production.

Run make local-db.

Tell Gemini to write the SQL: make prompt msg="Write a migration to add X"

Gemini gives you the code. Run supabase migration new add_x. Paste the code.

Run supabase db push --local (tests it on Docker). If it fails, feed the error back.

Step 2: The Code Generation

Write your exact instructions.

Run: make prompt msg="Refactor ExpenseModel and SplitModel to map to universal_usd_amount. Only output the changed code."

The Makefile automatically packages your models and sends them to Gemini so it has 100% accurate context.

Step 3: The Math Guard & Logger Feedback

If Gemini's code fails, do not say "it didn't work."

Run make test (The Math Guard).

If it fails, copy the structured output from your Flutter logger or the test failure.

Feed it back: make prompt msg="The math test failed. Here is the stack trace: [PASTE TRACE]. Fix the decimal conversion."

Phase 3: Implementing the Tools (Action List)

Install Repomix: npm install -g repomix

Setup Logger: Add logger: ^1.4.0 to pubspec.yaml. Replace all print() statements with logger.e("Error message") or logger.i("Info").

Write the Test: Create test/core/services/balance_service_test.dart. You must write a test that inputs 100 GEL and expects 37.00 USD.