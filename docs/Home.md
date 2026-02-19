# SetAll — Developer Wiki

> A Splitwise-style expense sharing app with offline-first architecture, multi-currency support, and biometric authentication.

---

## Pages

| Page | Description |
|------|-------------|
| [Architecture](Architecture.md) | Clean architecture layers, patterns, data flow |
| [Database Schema](Database-Schema.md) | SQLite schema, migrations, Supabase tables |
| [Currency System](Currency-System.md) | Exchange rate infrastructure, offline caching, multi-currency balance |
| [Features](Features.md) | All app features with usage notes |
| [Screens](Screens.md) | Screen-by-screen breakdown |
| [Supabase Setup](Supabase-Setup.md) | Supabase config, Edge Functions, RLS policies |
| [Changelog](Changelog.md) | Version history and update log |

---

## Quick Start

```bash
flutter pub get
flutter run
```

**Requirements:**
- Flutter SDK
- Supabase project (see [Supabase Setup](Supabase-Setup.md))
- iOS: Xcode 15+ for biometric/Face ID entitlements
