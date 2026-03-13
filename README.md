# SetAll

A high-end cost-sharing app (Splitwise-style) built with **Flutter**, **Riverpod**, and **Supabase**.

## Architecture

- **Clean Architecture**: `domain/` (entities), `data/` (models, repositories), `features/` (presentation).
- **State**: Riverpod (providers in each feature).
- **Routing**: go_router.
- **Money**: `decimal` for precise splits; `intl` for formatting.

## Setup

1. **Flutter**
   ```bash
   flutter pub get
   flutter run
   ```

2. **iOS on a physical device (free Apple ID, 2026)**  
   - **Xcode “handshake” first**  
     - Open **`ios/Runner.xcworkspace`** in Xcode (double‑click the file).  
     - Select the blue **Runner** project in the left sidebar → **Signing & Capabilities**.  
     - Check **Automatically manage signing**.  
     - **Team**: Add your free Apple ID if needed.  
     - **Bundle Identifier** is set to `com.jafa.setall.app` (unique for signing).  
   - **Trust the developer on iPhone**  
     - After the first install: **Settings → General → VPN & Device Management** → your Apple ID under “Developer App” → **Trust**.  
   - **If the app crashes (JIT / debug blocked on iOS 26)**  
     - Run in **Profile** mode instead of Debug (no Hot Reload, but runs on device):  
       ```bash
       flutter run --profile
       ```  
   - **Codesign “detritus” error** (macOS Sequoia/Tahoe): run `./scripts/fix_ios_codesign.sh`, then `flutter run` again. If it still fails, **build and run from Xcode** (open `ios/Runner.xcworkspace`, select your iPhone, press Run).

3. **Supabase**
   - Create a project at [supabase.com](https://supabase.com).
   - Run the SQL migrations in `supabase/migrations/` in order (Dashboard → SQL Editor).
   - In `lib/main.dart`, set:
     - `_supabaseUrl` = your project URL
     - `_supabaseAnonKey` = your anon/public key

## Project layout

```
lib/
├── app.dart                 # MaterialApp + router
├── main.dart                # Supabase init + ProviderScope
├── core/
│   ├── router/app_router.dart
│   ├── theme/setall_theme.dart   # Dark Material 3 theme
│   └── utils/split_engine.dart   # Even / custom split logic
├── data/models/             # Profile, Group, Expense, Split (fromJson/toJson)
├── domain/entities/         # Same entities (pure Dart)
└── features/
    ├── dashboard/           # Dashboard screen + balance summary
    └── expenses/            # Add expense (currency, split type)
supabase/migrations/         # SQL: profiles, groups, expenses, splits
```

## Split engine

- **Even split**: `SplitEngine.splitEven(total, participantIds)` → total / N with remainder on first.
- **Custom split**: `SplitEngine.splitCustom(total, participantIds, weights: [...])` or fixed `amountsOwed`.

## Security & Transparency

SetAll is open source. We believe transparency builds trust — especially in a fintech app that handles real money between real people.

### Client-Side API Keys

This repository contains Firebase/GCP API keys in `lib/main.dart` and platform config files. **This is intentional and safe** for the following reasons:

| Key | Restriction | Why it's safe |
|-----|-------------|---------------|
| Android | SHA-1 fingerprint + `com.setall.setall` package | Useless without our release keystore |
| iOS | Bundle ID `com.jafa.setall.app` | Only works with App Store/TestFlight signed builds |
| Web | HTTP referrer `https://setall.app/*` | Rejected from any other origin |

This is the same model used by Firebase's own documentation and all major apps shipping Firebase. The keys are designed to be client-facing.

> **Note:** `google-services.json`, `GoogleService-Info.plist`, and `lib/firebase_options.dart` are in `.gitignore` and are never committed. Share them via a secure channel (1Password, CI/CD secrets, team vault).

### Auditing the Logic

We welcome security audits. If you find a vulnerability, please open a private GitHub Security Advisory rather than a public issue.

### Supply Chain

- All dependencies are pinned in `pubspec.lock`
- CI/CD via GitHub Actions — see `.github/workflows/`
- Supabase Row Level Security policies are in `supabase/migrations/`

## License

MIT — see [LICENSE](LICENSE).
