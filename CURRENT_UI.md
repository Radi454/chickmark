# Current UI Design System
> Source-of-truth derived from code. Overrides any conflicting claims in APP_SPEC.md.
> Last updated: 2026-04-25

---

## 1. Color Palette
**File**: `lib/core/constants/app_colors.dart`

| Token | Hex | Usage |
|---|---|---|
| `primary` | `#1769D8` | Buttons, icons, focused borders, selected chips/nav items |
| `primaryLight` | `#079FE0` | Gradient start |
| `primaryDark` | `#193FC2` | Gradient end, activeText |
| `background` | `#F5F8FC` | Scaffold background |
| `cardBackground` | `#FFFFFF` | Card fill |
| `ageBadgeBg` | `#EAF4FF` | Info chips, age badges, TempToggle track |
| `completedBg` | `#E8F5E9` | Completed/synced badge background |
| `completedText` | `#388E3C` | Completed/synced badge text, saved section border |
| `activeBg` | `#E8F2FF` | Active/in-progress badge background, selected nav item bg |
| `activeText` | `#193FC2` | Active badge text |
| `infoBg` | `#EAF4FF` | Same as ageBadgeBg (alias) |
| `infoText` | `#1557B0` | Info text |
| `cardShadow` | `#1A0B2D5C` | All card/appbar shadows |
| `inactiveTab` | `Colors.grey` | Unselected nav items |
| `greenTab` | `#388E3C` | Temperature launcher FAB when active/recording |

**Hard-coded one-offs** (inline, not in AppColors):
- Device tile bg: `#F5F8FC` (same as scaffold)
- Session tile bg: `#F7FAFD`
- Live stat pill bg: `#F0F2F5`
- Chart grid lines: `#E2EAF2` (horizontal), `#EAF0F6` (vertical)
- Empty chart border: `#E0E7EF`
- Settings section border: `#E0E7EF`
- ChoiceChip unselected border in settings sheet: `#DDE6F1`
- Warmup badge bg: `#FFF3E0` (orange tint), text `Colors.orange.shade800`
- Error states: `Colors.red[50]` bg / `Colors.red[700]` text

---

## 2. Brand Gradient
**Token**: `AppColors.brandGradient`
```
LinearGradient(
  colors: [#079FE0, #193FC2],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
)
```
**Used on**: `GradientAppBar` container, temperature panel device status card.

---

## 3. Typography
**File**: `lib/core/theme/app_text_styles.dart`

| Token | Size | Weight | Line Height | Color |
|---|---|---|---|---|
| `heading` | 22px | w700 | 1.18 | `#111827` |
| `sectionTitle` | 18px | w700 | 1.25 | `#111827` |
| `title` | 16px | w600 | 1.30 | `#111827` |
| `body` | 15px | normal | 1.40 | `#1F2937` |
| `caption` | 12px | w500 | 1.35 | `#6B7280` |
| `badge` | 13px | w700 | 1.20 | `#FFFFFF` |
| `wordmark` | 28px | bold | — | `#000000`, Georgia, letterSpacing 2.0 |

**AppBar title**: white, 18px, w700, height 1.2 (hardcoded in `AppTheme`).

**TextTheme mappings**:
- `headlineMedium` → `heading`
- `headlineSmall` / `titleLarge` → `sectionTitle`
- `titleMedium` → `title`
- `titleSmall` → 14px w600 `#1F2937`
- `bodyLarge` / `bodyMedium` → `body`
- `bodySmall` / `labelSmall` → `caption`
- `labelLarge` → `badge`
- `labelMedium` → 12px w700 `#111827`
- `displaySmall` / `headlineLarge` → 24px w700 `#111827`
- `displayMedium` → 28px w700 `#111827`
- `displayLarge` → 32px w700 `#111827`

---

## 4. Spacing & Radius
**File**: `lib/core/constants/app_sizes.dart`

| Token | Value | Usage |
|---|---|---|
| `cardRadius` | 18.0 | Cards, app bar bottom corners, nav drawer right corners |
| `buttonRadius` | 16.0 | Buttons, inputs, chips |
| `cardPadding` | 16.0 | Default card inner padding; card margin = 8 (cardPadding/2) |
| `cardShadowBlur` | 18.0 | Card box shadow blur radius |
| `cardShadowOffsetY` | 6.0 | Card box shadow Y offset |

---

## 5. App Bar
**File**: `lib/core/theme/gradient_app_bar.dart`

- Container with `brandGradient` + rounded bottom corners (`cardRadius = 18`)
- Shadow: `cardShadow` color, blur 18, offset y 6
- Inner `AppBar`: `backgroundColor: transparent`, elevation 0, `surfaceTintColor: transparent`
- Title: white, 18px, w700
- All icons: white (`IconThemeData(color: Colors.white)`)
- Auto back button: `Icons.arrow_back` when route can pop
- Auto menu button: `Icons.menu` when shell has drawer and cannot go back
- `preferredSize`: `kToolbarHeight + bottom.preferredSize.height`

---

## 6. Cards

### Theme default (`CardThemeData` in `AppTheme`)
- `color`: white
- `shape`: `RoundedRectangleBorder(radius: 18)`
- `elevation`: 2
- `shadowColor`: `#1A0B2D5C`
- `surfaceTintColor`: transparent
- `margin`: `EdgeInsets.all(8)`

### `SectionCard` widget (`lib/widgets/section_card.dart`)
Custom card used for audit form sections:
- Container (not Material `Card`) — same white/radius-18/shadow spec
- Optional `title` header row with `sectionTitle`-sized text
- **Saved state** (`isSaved: true`):
  - `Border(top: BorderSide(color: #388E3C, width: 3))`
  - `IgnorePointer(ignoring: true)` — all inputs blocked
  - Content `Opacity(0.6)`
  - "Edit" `TextButton.icon(foregroundColor: #388E3C)` shown in header

### Temperature device status card
- Uses `brandGradient` container (not white Card)
- Rounded corners `cardRadius`
- All text/icons white or white with alpha

### Session/completed tiles
- bg `#F7FAFD`, radius 12, border: place-color @ 20% alpha
- Used inside larger white Cards

---

## 7. Buttons

### `ElevatedButton` (theme default)
- bg: `#1769D8`, fg: white
- elevation: 0
- padding: h18 / v14
- radius: 16
- textStyle: `badge` (13px w700)

### `OutlinedButton` (theme default)
- fg + border: `#1769D8`
- padding: h18 / v14
- radius: 16
- textStyle: `badge` @ primary color

### `TextButton` (theme default)
- fg: `#1769D8`
- textStyle: `badge` @ primary color

### `FilledButton` (M3, used in temperature panel)
- Used for primary actions: "Start place session", "Finish & sync"
- Inherits M3 `primary` color from `ColorScheme`
- Full-width (`SizedBox(width: double.infinity)`) for start action
- Icon + label pattern with loading `CircularProgressIndicator(strokeWidth: 2)` while busy

### Device settings action buttons (inside gradient card)
- Custom `TextButton.styleFrom`:
  - `foregroundColor: Colors.white`
  - `backgroundColor: Colors.white @ 12% alpha`
  - `shape: RoundedRectangleBorder(radius: 18)`

---

## 8. Inputs

### `InputDecorationTheme` (theme default)
- `filled: true`, `fillColor: white`
- `labelStyle` / `hintStyle`: `caption` (12px w500 `#6B7280`)
- `floatingLabelStyle`: `caption` @ primary color, w700
- `contentPadding`: h16 / v14
- `border` / `enabledBorder`: `OutlineInputBorder(radius: 16, borderSide: grey.shade200)`
- `focusedBorder`: `OutlineInputBorder(radius: 16, borderSide: #1769D8 @ 1.5px)`

### `DropdownButtonFormField`
Uses same `InputDecoration` theme. `labelText` pattern used throughout.

---

## 9. Chips

### `ChipThemeData` (theme default)
- `backgroundColor`: white
- `selectedColor`: `#1769D8`
- `checkmarkColor`: white
- `side`: `grey.shade200`
- `labelStyle`: `caption` @ w700
- `shape`: `RoundedRectangleBorder(radius: 16)`

### `ChoiceChip` usage patterns
**Standard** (place chips, interval chips):
- `selectedColor: AppColors.primary`
- selected label: white 12px
- unselected label: `Colors.black87` 12px

**Settings sheet variant**:
- `backgroundColor: Colors.white`
- selected border: `#1769D8`
- unselected border: `#DDE6F1`

### `FilterChip` (chart session filter)
- `selectedColor`: place-color @ 16% alpha
- `checkmarkColor`: place-color
- `side`: place-color @ 35% alpha

### `SegmentedButton` (chart metric selector)
- Inherits M3 `ColorScheme.primary`
- Three segments: Temp / R.H. / Both

---

## 10. Status Badges
**File**: `lib/widgets/status_badge.dart`

Pill shape: `BorderRadius.circular(16)`, padding h12/v6, text 12px w600.

| Status key | bg | text |
|---|---|---|
| `completed`, `synced` | `#E8F5E9` | `#388E3C` |
| `active`, `syncing` | `#E8F2FF` | `#193FC2` |
| `failed`, `error`, `syncfailed` | `Colors.red[50]` | `Colors.red[700]` |
| default | `Colors.grey[300]` | `Colors.grey[700]` |

---

## 11. Navigation

### Mobile (width < 900px) — Drawer
- Width: `(screenWidth × 0.72).clamp(260, 300)`
- bg: white, elevation 10, shadow `cardShadow`
- Right corners rounded to `cardRadius (18)`
- `surfaceTintColor: transparent`
- Header: `ChickMarkLogo` + close button
- Nav items: selected = `activeBg (#E8F2FF)` fill, `primary` icon/text w700; unselected = transparent, `#535966` icon/text w600
- Item radius: 12, padding h14/v12

### Desktop (width ≥ 900px) — NavigationRail
- bg: white, right shadow `cardShadow`
- `minWidth: 88`, `labelType: all`
- Selected: `#1769D8` icon + text w600
- Unselected: `Colors.grey`
- Leading: `ChickMarkLogo(logoSize: 58, compact: true)` with top 14 / bottom 22 padding

### Tabs (7 destinations)
Home · Dashboard · Customers · Audits · Temperature · BMK · Settings

---

## 12. Temperature Toggle

### `TempToggle` widget (`lib/widgets/temp_toggle.dart`)
Segmented pill — **not** a Chip or SegmentedButton:
- Outer container: `#EAF4FF` bg, `BorderRadius.circular(999)`
- Selected segment: `#1769D8` bg, `BorderRadius.circular(999)`, white text w600 14px
- Unselected segment: transparent bg, `Colors.grey[700]` text w600 14px
- Segment padding: h12/v6
- Reads/writes `AppProvider.tempUnit` → persisted preference

### Where temperature toggle appears
| Location | Widget |
|---|---|
| Settings screen | `TempToggle` |
| Temp panel device settings sheet | `ChoiceChip` pair (°F / °C with checkmark avatar) |
| **Missing** from all audit screens | Known gap — see S.4 |

---

## 13. Floating Temperature Launcher
**File**: `lib/app.dart` — `_AppMeasureOverlay`

- 64×64 circular `Material` button wrapping `TemperatureRhLauncher`
- **Draggable**: `GestureDetector.onPanUpdate` moves freely
- **Dockable**: on pan end, if within `_dockThreshold (42px)` of left/right edge → snaps and hides behind edge; pull-tab `_MeasurePullTab` shown instead
- **Dock handle**: 38px wide × 72px tall
- Active (recording): `#388E3C` bg, `Icons.thermostat` + green/orange status dot at bottom
- Inactive: `#1769D8` bg, `Icons.thermostat_auto`
- Warmup dot: 10px orange; ready dot: 8px white with green border
- Visible on all authenticated routes except `/login` and `/startup-sync`

---

## 14. Chart Colors (Temperature Panel)
Ordered palette for multi-place line charts:
1. `#1769D8` (primary)
2. `#388E3C` (greenTab)
3. `#E67E22` (orange)
4. `#7E57C2` (purple)
5. `#00897B` (teal)
6. `#D81B60` (pink)
7. `#5D6D7E` (slate)

Assigned by `TemperaturePlace.index % 7`.

---

## 15. Sheets / Modals

### Bottom sheets (standard)
- `isScrollControlled: true`, `backgroundColor: transparent`
- Container: `AppColors.background` fill, `BorderRadius.vertical(top: Radius.circular(24))`
- Drag handle: 42px wide × 5px, `Colors.black @ 25% alpha`, pill shape
- Content padding: `fromLTRB(20, 10, 20, 24)`

### Dialogs (desktop ≥ 900px, temp panel)
- `Dialog(alignment: Alignment.centerRight)`
- `SizedBox(width: 420, height: screenHeight - 80)`

### Temperature panel dimensions
- Mobile: `ModalBottomSheet` at 86% screen height
- Desktop: right-aligned dialog 420px wide

---

## 16. Known Gaps vs APP_SPEC.md
| Gap | Detail |
|---|---|
| S.1 | Spec references orange `#F65C00` brand color — never implemented; blue `#1769D8` is actual primary |
| S.2 | Spec references orange gradient — never implemented; blue `#079FE0→#193FC2` is actual gradient |
| S.4 | `TempToggle` missing from audit screens (Setter Optimizing, Hatcher Optimizing, Chick Quality, Egg Storage) |
| Dashboard filters | No "Clear filters" button; `clearFilters()` / `hasActiveFilters` not yet in `DashboardProvider` |
