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

## License

Private / your choice.
