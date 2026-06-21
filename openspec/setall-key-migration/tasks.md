# setall-key-migration — tasks

## COMPLETED (✅ — as-built, for traceability)
```
[x] 1  auth_config.dart default → publishable key
[x] 2  ai-analyst → auth.getUser(token); deployed --no-verify-jwt
[x] 3  9 internal functions → x-edge-secret guard (send-email + send-welcome-email exempt, D4)
[x] 4  10× config.toml verify_jwt=false
[x] 5  migration 20260601000001 — triggers/crons use x-edge-secret from Vault
[x] 6  committed service_role migration body neutralized
[x] 7  EDGE_SHARED_SECRET + secret key set; Vault edge_shared_secret created (post-rotation)
[x] 8  all 10 functions deployed
[x] 9  Netlify env: SUPABASE_URL + publishable key
[x] 10 legacy anon/service_role disabled in dashboard
[x] 11 git history scrubbed (528 commits, 0 JWTs, force-pushed all branches+tags)
[x] 12 app verified booting + authenticating on device
[x] 13 web rebuilt + redeployed to setall.app with publishable key
```

## OPEN — cleanup backlog (the reason this spec isn't closed)

```
OPEN-1  Secret hygiene after in-chat leak  [YOU — do not paste values in any AI chat]
  1.1 Confirm .env EDGE_SHARED_SECRET == Supabase secret == Vault edge_shared_secret (all the ROTATED value).
      - supabase secrets list (presence only); compare against .env locally; SELECT name,created_at FROM vault.secrets WHERE name='edge_shared_secret' (one row, recent).
  1.2 Confirm the leaked FIRST secret is dead: it was only ever a header value, killed by rotation — verify by calling an internal fn with the old value → expect 403.
  1.3 While here: the FIREBASE_SERVICE_ACCOUNT private key sat in .env that the agent read; .env is gitignored + never committed (verified). If you want belt-and-suspenders, rotate the Firebase service-account key (Firebase console → new private key) and supabase secrets set it.
  -- EXIT: one rotated value everywhere; old values 403/dead.

OPEN-2  Get CI green, then decouple it from this work  [CASCADE for the YAML, YOU for secrets/tags]
  2.1 Confirm release.yml has: Android job, Windows --no-tree-shake-icons, correct Firebase secret name (FIREBASE_SERVICE_ACCOUNT_SETALL_45061), if-guards on artifact downloads.
  2.2 Decide tag hygiene: the force --tags re-pointed 33 tags. Either accept current state or delete stale tags. Cut ONE fresh tag (e.g. v1.6.3) for a clean trigger rather than reusing rewritten ones.
  2.3 One green run across desktop + Android. Treat any remaining failure as a normal CI bug (separate spec), not part of the migration.
  -- EXIT: green release run on a fresh tag.

OPEN-3  Document the two auth-hook exceptions  [CASCADE]
  3.1 Add a comment block in send-email/index.ts and send-welcome-email/index.ts: "No x-edge-secret — Supabase Auth Hook, protected by <mechanism>. Do not add x-edge-secret (breaks auth flow)."
  3.2 Note the exception in ARCHITECTURE.md / security notes so audits skip them.
  -- EXIT: both files annotated.

OPEN-4  Resolve key-name confusion  [decision, then CASCADE]
  4.1 Decide: (a) document that SUPABASE_ANON_KEY now holds the publishable value and SUPABASE_SERVICE_ROLE_KEY holds the secret (reserved-prefix constraint), OR (b) rename non-reserved consumers to *_PUBLISHABLE/*_SECRET where the SUPABASE_ prefix isn't forced.
  4.2 Apply: add a header comment in .env(.example) and auth_config.dart stating the aliasing either way.
  -- EXIT: no one can mistake which value is which.

OPEN-5  Reship every client channel  [mostly YOU]
  5.1 Web — done.
  5.2 iOS — install iOS 26 platform in Xcode (Settings → Components), archive → TestFlight. (Blocker is the platform download, unrelated to keys.)
  5.3 Android — via the new release.yml Android job → Firebase App Distribution (depends OPEN-2).
  5.4 macOS/Windows — via release.yml on the fresh tag (depends OPEN-2).
  5.5 After each: launch → login succeeds (no "Legacy API keys are disabled").
  -- EXIT: all channels on a build with the publishable key.

OPEN-6  Split .env into client vs server (the original intent)  [CASCADE for templates, YOU to populate]
  6.1 Create .env.client.example (SUPABASE_URL, publishable key, 3× GOOGLE_*_CLIENT_ID, 3× FIREBASE_*_API_KEY) — the ONLY file passed to --dart-define-from-file.
  6.2 Create .env.server.example (secret key, RESEND_API_KEY, GROQ_API_KEY, GEMINI_API_KEY?, FIREBASE_SERVICE_ACCOUNT, WELCOME_HOOK_SECRET, EDGE_SHARED_SECRET) — used only by supabase secrets / Netlify, NEVER the Flutter build.
  6.3 Update build/run/CI to use .env.client; keep both gitignored (only *.example committed).
  6.4 Verify no secret name is referenced via String.fromEnvironment anywhere in lib/.
  -- EXIT: a client build cannot read any server secret.

OPEN-7  ✅ RESOLVED (2026-06-21) — Gemini removed completely.
  7.1 The Supabase edge ai-analyst (the only GEMINI_API_KEY caller) was dead code (retired bb8ff50) → DELETED (dir removed).
  7.2 Stale Gemini comments cleaned in netlify/functions/ai-analyst.js, dashboard_screen.dart, voice_input_button.dart; docs/ai-architecture.md rewritten.
  7.3 Provider stance: Groq for existing analyst+voice; OpenAI standard for new AI features. No GEMINI_API_KEY used anywhere in code.
  -- MANUAL (env guardrail): remove GEMINI_API_KEY line from .env.server(.example) + drop from Netlify/Supabase secrets.
```

## Cross-cutting
- Never paste secret values into any AI chat (provider transmission) — generate in terminal, reference by name. (Codify in AGENTS.md.)
- After any `supabase secrets set`, wait for function restart and re-test the full set together (cold-restart desyncs were the main time-sink in the run).
