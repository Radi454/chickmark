# Quickstart: Phase 1 — Foundation, Architecture & Design System

**Date**: 2026-04-18
**Branch**: `002-foundation-architecture-design`

---

## Prerequisites

| Tool | Version | Check |
|------|---------|-------|
| Flutter SDK | ^3.10.7 | `flutter --version` |
| Dart | ^3.0 (bundled) | `dart --version` |
| Xcode | 15+ | `xcode-select -p` |
| iOS Simulator | iOS 17 | Open via Xcode → Devices & Simulators |
| CocoaPods | 1.14+ | `pod --version` |

---

## 1. Clone and install dependencies

```bash
cd "/Users/ibrahimradi/Claude/Apps/Hatchery app flutter/hatchaudit"
flutter pub get
cd ios && pod install && cd ..
```

---

## 2. Configure Supabase credentials

Create `lib/core/constants/supabase_config.dart` (gitignored):

```dart
// lib/core/constants/supabase_config.dart
// DO NOT COMMIT — listed in .gitignore
class SupabaseConfig {
  static const String url = 'YOUR_SUPABASE_URL';
  static const String anonKey = 'YOUR_SUPABASE_ANON_KEY';
}
```

Add to `.gitignore`:
```
lib/core/constants/supabase_config.dart
```

If Supabase credentials are not yet available, the app will run in fully offline
mode: the `SupabaseService` sets `isAvailable = false` and all auth calls return
an offline error. Login via cached token still works if a prior session exists.

---

## 3. Run the app

```bash
# iOS Simulator
flutter run -d "iPhone 16"    # adjust to your available simulator name

# List available simulators
flutter devices
```

---

## 4. Run unit tests

```bash
flutter test test/utils/
```

All tests in `test/utils/` MUST pass before implementation of any UI that depends
on the calculation utilities.

Expected test files:
- `test/utils/calculation_utils_test.dart`
- `test/utils/temp_converter_test.dart`
- `test/utils/date_utils_test.dart`

---

## 5. Run static analysis

```bash
flutter analyze
```

Expected output: `No issues found!`

Zero errors required before any PR is opened (Constitution §Quality Standards).

---

## 6. Verify database creation

On first launch, open the app in the simulator. The SQLite database is created at
`<app documents>/hatchaudit.db`. Verify all 8 tables exist:

```bash
# Find the simulator app container
xcrun simctl get_app_container booted com.chickmark.hatchaudit data

# Open with any SQLite browser (e.g., DB Browser for SQLite)
# Expected tables:
# users, customers, flocks, audits,
# bmk_breeds, bmk_egg_breakout, troubleshooting, photos
```

---

## 7. Validate auth flow

1. Launch app → Login screen appears with ChickMark logo.
2. Tap **Create Account** → Register screen with strength indicator.
3. Register a new account → Pending Approval screen shows.
4. (Seed admin account) Approve the account in Supabase dashboard.
5. Log in → Home screen with 6-tab bottom nav bar appears.
6. Kill app, enable Airplane Mode, relaunch → Offline login succeeds.

---

## 8. Validate design system

Open each Phase 1 screen and confirm:

| Check | Expected |
|-------|----------|
| Header gradient | #F65C00 → #ff8c42, left to right |
| Page background | #f0f2f5 |
| Cards | White, 14px radius, subtle shadow |
| Primary buttons | #F65C00 fill, 12px radius |
| Active nav tab | #F65C00 icon + label |
| Logo wordmark | "CHICKMARK" in Georgia serif, #F65C00 |

---

## Key files reference

| File | Purpose |
|------|---------|
| `lib/core/constants/app_colors.dart` | All colour constants |
| `lib/core/theme/app_theme.dart` | ThemeData factory |
| `lib/core/utils/calculation_utils.dart` | All formula implementations |
| `lib/data/database/database_helper.dart` | Schema creation + migrations |
| `lib/features/auth/providers/auth_provider.dart` | Auth state machine |
| `lib/providers/app_provider.dart` | Global state (user, temp unit) |
| `lib/widgets/temp_toggle.dart` | [°C/°F] toggle |
| `lib/widgets/section_card.dart` | Standard card with green-tab support |
