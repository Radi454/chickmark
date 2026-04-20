# Quickstart: Phase 4 — BMK Screen + Settings + Home Screen + Logo

**Branch**: `005-bmk-settings-home-logo` | **Date**: 2026-04-18

---

## Prerequisites

- Flutter SDK ≥ 3.10.7 with Dart 3
- Dependencies already installed: `shared_preferences ^2.3.2`, `connectivity_plus ^6.1.0`
- No new packages required

---

## Implementation Order

Implement in this order to avoid broken intermediate states:

```
1. DB migration v3  →  2. BMK models  →  3. BMK seeds
4. BmkProvider      →  5. BmkScreen
6. SettingsProvider →  7. SettingsScreen
8. HomeScreen       →  9. Logo widget
10. Register SettingsProvider in app.dart MultiProvider
```

---

## 1. DB Migration (database_helper.dart)

Bump version from `2` to `3`. In `_onUpgrade`:

```dart
if (oldVersion < 3) {
  // Redesign bmk_breeds
  await db.execute('DROP TABLE IF EXISTS bmk_breeds');
  await db.execute('''CREATE TABLE bmk_breeds (
    id TEXT PRIMARY KEY, breed TEXT NOT NULL, ageWeek INTEGER NOT NULL,
    hatchabilityPct REAL, fertilityPct REAL, hofPct REAL,
    productionPct REAL, eggWeightG REAL, chickWeightG REAL
  )''');
  // Redesign bmk_egg_breakout
  await db.execute('DROP TABLE IF EXISTS bmk_egg_breakout');
  await db.execute('''CREATE TABLE bmk_egg_breakout (
    id TEXT PRIMARY KEY, ageWeek INTEGER NOT NULL UNIQUE,
    infertilePct REAL, early24hPct REAL, early48hPct REAL,
    bloodRingPct REAL, blackEyePct REAL, midDeadPct REAL,
    lateDeadPct REAL, pippedInternalPct REAL, pippedExternalPct REAL,
    explodedPct REAL, mushyPct REAL, contamPct REAL,
    cullPct REAL, seeperPct REAL, otherPct REAL
  )''');
  // Re-seed
  for (final seed in kBmkBreedSeeds) {
    await db.insert('bmk_breeds', seed, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
  for (final seed in kBmkEggBreakoutSeeds) {
    await db.insert('bmk_egg_breakout', seed, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}
```

Also update `_onCreate` to use the new DDL (for fresh installs at v3).

---

## 2. BMK Screen — Key Widget Structure

```
BmkScreen (StatelessWidget)
  └── GradientAppBar("BMK")
      └── SingleChildScrollView
          ├── Section 1: Breed Benchmarks
          │   ├── HorizontalBreedChips (Ross308 | Arbo | Avian | Cobb500 | Hubbard | IR)
          │   ├── AgeDropdown (ages from DB for selected breed)
          │   └── BmkBreedCard (6 metric tiles: label + value)
          └── Section 2: Egg Breakout BMK
              ├── EbTypeFilterRow (🥚 Fresh | 🔍 Candled | 🐣 Residue)
              ├── AgeDropdown (25-65 weeks)
              └── EbParameterGrid (filtered by type, each = card with name + value%)
```

---

## 3. Settings Screen — Key Widget Structure

```
SettingsScreen (StatelessWidget)
  └── GradientAppBar("Settings")
      └── ListView
          ├── Section: Account
          │   ├── AvatarCircle (initials from fullName)
          │   ├── FullName (display only)
          │   ├── Email (display only)
          │   └── RoleBadge (Admin/Auditor/Customer)
          ├── Section: Preferences
          │   ├── TempUnitToggle → AppProvider.setTempUnit()
          │   ├── NumberField: Pasgar Sample Size → SettingsProvider
          │   ├── NumberField: Weights Sample Size → SettingsProvider
          │   ├── NumberField: Tray Size → SettingsProvider
          │   └── NumberField: Storage Days → SettingsProvider
          ├── Section: Sync
          │   ├── ConnectionStatus (ConnectivityResult from connectivity_plus)
          │   ├── LastSynced timestamp
          │   └── SyncNowButton
          └── Section: App
              ├── AppVersion (from package_info_plus or hardcoded string)
              └── SignOutButton (red, confirmation dialog)
```

---

## 4. Home Screen — Key Widget Structure

```
HomeScreen (StatelessWidget/Consumer)
  └── GradientAppBar("ChickMark")
      └── Column
          ├── StatsRow
          │   ├── StatCard("Customers", count)
          │   ├── StatCard("Active Audits", count)
          │   └── StatCard("Total Audits", count)
          ├── ActionButtonsRow
          │   ├── OutlinedButton "+ New Customer" → AddCustomerSheet
          │   └── ElevatedButton "+ New Audit" → AuditTypeSelectionScreen
          ├── FilterChipsRow (horizontal scroll)
          │   └── All | Chick Quality | Hatch Analysis | Egg Storage | Setter Optimizing | Hatcher Optimizing
          └── Expanded ListView (max 20 items, newest first)
              └── AuditListCard per audit
                  ├── AgeBadge (orange pill)
                  ├── CustomerName (bold)
                  ├── Flock · Breed · Date (subtitle)
                  ├── AuditType · SetterID/HatcherID
                  └── StatusBadge
```

Data source: `Consumer<CustomersProvider>` — uses `allAudits` getter (sorted by createdAt desc, filtered by selected type).

---

## 5. Logo — CustomPainter Structure

Replace `_buildFallbackLogo()` with:

```dart
Widget _buildLogo(double size) {
  return CustomPaint(
    size: Size(size, size * 1.2),  // taller than wide (egg is tall oval)
    painter: ChickMarkPainter(),
  );
}
```

`ChickMarkPainter` draws (all in `#F65C00` stroke, no fill):
- Tall oval: egg body (center-bottom of canvas)
- Bold `✓` checkmark inside oval
- Small circle: chick head (upper right of egg top)
- Eye dot inside head
- Beak (small triangle pointing right)
- Comb (3 small upward curves on head top)
- Wing (arc with feather detail lines)
- Tail feathers (3 lines, upper left)
- Legs (2 lines down from egg bottom) with toe branches

All coordinates expressed as fractions of `size` so the logo scales perfectly.

---

## 6. Provider Registration (app.dart)

Add `SettingsProvider` and `BmkProvider` to MultiProvider in `app.dart`:

```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => AppProvider()),
    ChangeNotifierProvider(create: (_) => AuthProvider()),
    ChangeNotifierProvider(create: (_) => CustomersProvider()),
    ChangeNotifierProvider(create: (_) => SettingsProvider()),  // NEW
    ChangeNotifierProvider(create: (_) => BmkProvider()),       // NEW
  ],
  ...
)
```

---

## 7. Flutter analyze Gate

Run before PR:
```bash
flutter analyze
flutter test
```

Both must pass with zero errors. Warnings require `// ignore: <reason>` inline comments.
