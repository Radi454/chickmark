# ChickMark UI Elevation: Design System Refinement

> Apple-level simplicity. Clean premium SaaS polish. Medical/industrial aesthetic.
> Constraints: UI/UX layer only. No functional, business logic, provider, DB, or routing changes.

---

## A. UI CRITIQUE

### A1. Spacing System — No Grid Foundation

**Problem**: Spacing uses 20+ magic numbers with no systemic basis.

| Inline value | Appears in | Should be |
|---|---|---|
| `3` | `_AttentionTile` subtitle gap | `4` (xs) |
| `4` | KPI label-to-value, badge gaps | `4` (xs) |
| `6` | BreakdownBar progress top-pad | `8` (s) |
| `8` | ActiveAuditCard badge-to-title | `8` (s) |
| `12` | Card icon gaps, section spacing | `12` (m) |
| `14` | Card padding `_ActiveAuditCard`, `_AttentionTile` | `16` (l) |
| `16` | Most section gaps, card padding | `16` (l) |
| `24` | Major section gaps | `24` (xl) |
| `96` | Bottom padding (FAB clearance) | `96` (2xl) |

**Impact**: Visual rhythm is inconsistent. Some cards use 14px padding, others 16. The home screen mixes 3px, 4px, 6px, 8px, 12px, 14px, 16px, 24px with no hierarchy logic.

Only 5 constants exist in `AppSizes` — need a full 8pt spacing scale.

### A2. Typography — Token Leakage

**Problems**:
1. **8 inline font sizes** bypass `AppTextStyles`: 22, 24, 13, 14, 15, 12, 18, 15 (duplicated)
2. **`FontWeight.bold`** vs **`FontWeight.w700`** used interchangeably — same value, inconsistent style
3. **Hardcoded colors**: `Colors.black87`, `Colors.grey[600]`, `Colors.grey`, `Colors.black45`, `Colors.black26`, `Colors.red[700]`, `AppColors.primary` (inline overrides)
4. `SectionCard.title` uses `TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)` — should use `AppTextStyles.sectionTitle`
5. Dashboard `_sectionHeader` uses `Theme.of(context).textTheme.titleSmall` which resolves to `14px w600 #1F2937` — not the same as `sectionTitle` (18px w700 #111827)
6. Dashboard `_metricRow` uses `TextStyle(fontWeight: FontWeight.bold)` — no size, no color token
7. Dashboard find/findings text uses `TextStyle(fontSize: 13)` — not a recognized token
8. Home screen `_KpiCard` uses `AppTextStyles.heading.copyWith(fontSize: 22)` — overwriting heading's own 22px
9. Home screen stat cards use hardcoded `fontSize: 24, fontWeight: FontWeight.bold`

### A3. Color — Token Gaps & Leakage

**Missing semantic tokens** (colors hardcoded inline):

| Hardcoded | Location | Should be token |
|---|---|---|
| `Color(0xFF3a9a5c)` | Threshold good status | `statusGood` |
| `Color(0xFFE6A23C)` | Amber finding | `statusWarning` |
| `Color(0xFFE24B4A)` | Red finding/threshold | `statusError` |
| `Colors.grey.shade200` | Input borders | `borderDefault` |
| `Colors.grey.shade300` | Badge default bg | `statusNeutralBg` |
| `Colors.grey[700]` | Badge default text | `statusNeutralText` |
| `Colors.red[50]` | Error bg | `statusErrorBg` |
| `Colors.red[700]` | Error text | `statusErrorText` |
| `Colors.orange.shade700` | Warmup status | `statusWarningText` |
| `Colors.orange.shade800` | Warmup text variant | `statusWarningText` |
| `Colors.grey[600]` | Subtitle text | `textSecondary` |
| `Colors.black87` | Card title override | `textPrimary` |
| `Colors.black45` | Empty state text | `textTertiary` |
| `Colors.black26` | Empty icon | `iconEmpty` |
| `Colors.grey.shade600` | Disabled button | `textDisabled` |
| `Colors.white` | General purpose | `surface` |

**Inconsistencies**:
- `AppColors.completedText #388E3C` vs threshold green `#3a9a5c` — two different greens
- `ageBadgeBg #EAF4FF` and `infoBg #EAF4FF` are same value — redundant token
- Chart colors are hardcoded in temperature panel, not tokenized

### A4. Shadows — Too Heavy

Current: `blurRadius: 18, offset: Offset(0, 6)` with color `#1A0B2D5C` (~36% opacity)

**Problems**:
- Every card has the same shadow regardless of context (KPI, list tile, section card, attention tile, sync status, empty state)
- Apple-style uses barely-there shadows: `0 1px 3px rgba(0,0,0,0.08)` for resting, `0 4px 12px rgba(0,0,0,0.12)` for elevated
- Current shadow creates a "floating card soup" effect — every element competes visually

### A5. Radius — Too Round, No Hierarchy

| Current | Apple Reference | Proposed |
|---|---|---|
| `cardRadius: 18` | Apple uses 12-16 for cards | Reduce to `14` |
| `buttonRadius: 16` | Apple uses 8-10 for small buttons, 12 for large | Reduce to `12` |
| Badge `circular(16)` | Pills should be `circular(8)` | Reduce badge radius to `8` |
| Icon containers `circular(12)` | Consistent at 12 | Keep at `12` |
| TempToggle `circular(999)` | Keep for pill shape | OK |

Missing radius tokens: `badgeRadius`, `iconContainerRadius`, `sheetRadius`, `dialogRadius`, `inputRadius`

### A6. Card/Button Hierarchy — Flat

**Problem**: All cards use the same shadow + radius + padding. No visual hierarchy.

- KPI cards = Section cards = List tiles = Attention tiles = Empty states = Sync boxes
- All use: `white bg, radius 18, shadow blur 18 offset 6, padding 16`
- Apple uses: Level 0 (flat), Level 1 (1px border), Level 2 (subtle shadow), Level 3 (prominent shadow)

**Home screen has 6 custom card-like containers** (`_KpiCard`, `_FocusMetricCard`, `_RecentAuditTile`, `_AttentionTile`, `_ShortcutTile`, `_EmptyHomeMessage`) — all hand-decorated inline with the same pattern, no shared base widget.

### A7. Dashboard-Specific Issues

1. **Filter bar** — white container with no visual grounding. Dropdowns look disconnected from the data below. `OutlineInputBorder()` used without theme borderRadius.
2. **Visit Sessions card** — `ExpansionTile` inside `Card` creates double-shadow (Card shadow + ExpansionTile default elevation)
3. **Findings chips** — raw `Chip` with inline `_findingChip` method, different pattern from `StatusBadge`
4. **Session date selector** — `ChoiceChip` with raw day/month/year format, not localized
5. **Section headers** — `_sectionHeader` uses `titleSmall` (14px w600) instead of proper section title (18px w700)
6. **Metric rows** — inline style `TextStyle(fontWeight: FontWeight.bold)` with no size or color reference
7. **Empty sections** — hardcoded `Colors.black26` and `Colors.black45`
8. **No clear/filters button visible when no filters active** — only shows conditionally
9. **All dashboard sections use `Card` widget** — uniform elevation, no hierarchy distinction

### A8. Micro-Interaction Gaps

| Gap | Impact |
|---|---|
| No button press animation | All buttons feel static |
| No card tap feedback scale | Cards with InkWell have ripple but no scale |
| No page transitions | Raw `MaterialPageRoute` everywhere |
| No save success animation | Users get SnackBar text only |
| No chart entry animation | Charts render statically |
| TempToggle has no animated selector | Segment slides instantly |
| No hover/elevation on desktop | Navigation rail and cards feel flat on desktop |
| No loading skeleton | `CircularProgressIndicator` shown while loading |

### A9. Component-Level Issues

**`SectionCard`**:
- Title uses hardcoded `fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87` instead of `AppTextStyles.sectionTitle`
- Saved state uses `IgnorePointer + Opacity(0.6)` — this makes the entire card feel broken rather than "locked"

**`StatusBadge`**:
- `BorderRadius.circular(16)` is too round for a small pill badge
- No animation on status change

**`TempToggle`**:
- `GestureDetector` with no `AnimatedContainer` for segment transition
- No haptic feedback

**Dashboard filter**:
- `DropdownButtonFormField` uses `OutlineInputBorder()` without `AppSizes.buttonRadius`
- `initialValue` is used but should be `value` for proper controlled state

**Home screen**:
- `_QuickActionButton` overrides theme disabled colors with `Colors.grey.shade300/600` — should use design tokens
- `OutlinedButton` in `_buildActionButtons` overrides shape radius to `10` vs theme `16`
- `_BreakdownBar` progress bar height `10` is hardcoded

### A10. Missing Design System Tokens

**Missing from `AppSizes`**:
- Spacing scale (xs, sm, md, lg, xl, etc.)
- Badge/pill radius
- Icon container radius
- Sheet/modal top radius
- Bottom padding for FAB clearance
- Input height
- Icon sizes (standard: 20, 24, 48)
- Divider thickness

**Missing from `AppColors`**:
- `surface` token (white)
- `textPrimary` token (#111827)
- `textSecondary` token (#6B7280 — same as caption but semantic)
- `textTertiary` token
- `textDisabled` token
- `borderDefault` token
- `borderFocused` token
- `statusGood/Warning/Error` + bg/text variants
- `divider` token
- `scaffoldDivider` token

**Missing from `AppTextStyles`**:
- `sectionHeader` for dashboard section titles
- `metricValue` for large metric numbers
- `badgeLabel` for chip/badge labels
- `emptyTitle` / `emptyMessage` for empty states

---

## B. PROPOSED IMPROVEMENTS

### B1. 8pt Spacing Scale

```dart
class AppSpacing {
  static const double xs = 4.0;    // micro gaps (badge to text, 2-line items)
  static const double sm = 8.0;    // tight gaps (icon-to-label, inline)
  static const double md = 12.0;   // standard gaps (card internal)
  static const double lg = 16.0;   // card padding, section internal
  static const double xl = 24.0;   // section gaps
  static const double xxl = 32.0;  // major separations
  static const double fabBottom = 96.0; // FAB clearance
}
```

Replace all `SizedBox(height: 3)`, `SizedBox(height: 6)`, etc. with the closest scale value.

### B2. Typography Refinement

**Changes**:
- Replace all inline `TextStyle` with `AppTextStyles` tokens
- Add missing tokens: `sectionHeader`, `metricLarge`, `badgeLabel`
- Ensure `SectionCard.title` uses `AppTextStyles.sectionTitle`
- Dashboard section headers use `AppTextStyles.sectionTitle`
- Remove all `FontWeight.bold` usage, use `w700` consistently
- Remove `color: Colors.black87`, use `AppColors.textPrimary`

### B3. Color Token Expansion

Add to `AppColors`:
```dart
// Semantic text
static const Color textPrimary = Color(0xFF111827);
static const Color textSecondary = Color(0xFF6B7280);
static const Color textTertiary = Color(0xFF9CA3AF);
static const Color textDisabled = Color(0xFFD1D5DB);

// Borders
static const Color borderDefault = Color(0xFFE5E7EB);   // grey.shade200
static const Color borderFocused = Color(0xFF1769D8);    // same as primary

// Status
static const Color statusGood = Color(0xFF388E3C);       // replaces #3a9a5c → unify
static const Color statusGoodBg = Color(0xFFE8F5E9);      // same as completedBg
static const Color statusWarning = Color(0xFFE67E22);    // amber warning
static const Color statusWarningBg = Color(0xFFFFF3E0);  // warmup/pending bg
static const Color statusError = Color(0xFFDC2626);      // red error
static const Color statusErrorBg = Color(0xFFFEF2F2);    // red bg

// Surface
static const Color surface = Colors.white;
static const Color surfaceVariant = Color(0xFFF9FAFB);   // slightly lighter than scaffold

// Dividers
static const Color divider = Color(0xFFE5E7EB);
```

**Consolidate**: Remove `infoBg` (alias of `ageBadgeBg`). Merge threshold green `#3a9a5c` into `statusGood #388E3C`.

### B4. Apple-Style Shadow System

```dart
class AppElevation {
  // Level 0: Flat, no shadow (dividers, inline cards)
  static List<BoxShadow> get none => [];

  // Level 1: Subtle, for resting cards
  static List<BoxShadow> get level1 => [
    BoxShadow(
      color: const Color(0x0F000000), // 6% opacity
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  // Level 2: Standard, for elevated cards and modals
  static List<BoxShadow> get level2 => [
    BoxShadow(
      color: const Color(0x1A000000), // 10% opacity
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  // Level 3: High, for app bar and floating elements
  static List<BoxShadow> get level3 => [
    BoxShadow(
      color: const Color(0x1A000000),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];
}
```

**Mapping**:
- App bar: `level3` (current)
- KPI cards, section cards: `level1`
- List tiles, empty states: `level1`
- FAB, modals, dialogs: `level2`

### B5. Radius Refinement

```dart
class AppSizes {
  // Radius
  static const double cardRadius = 14.0;     // was 18 — softer Apple style
  static const double buttonRadius = 12.0;   // was 16
  static const double badgeRadius = 8.0;      // NEW — pills/badges
  static const double iconRadius = 12.0;      // NEW — icon containers
  static const double sheetRadius = 24.0;     // NEW — bottom sheets
  static const double inputRadius = 12.0;     // was buttonRadius (16) for inputs
  static const double dialogRadius = 14.0;    // NEW — dialogs

  // Spacing (8pt grid)
  static const double spaceXs = 4.0;
  static const double spaceSm = 8.0;
  static const double spaceMd = 12.0;
  static const double spaceLg = 16.0;
  static const double spaceXl = 24.0;
  static const double spaceXxl = 32.0;

  // Padding
  static const double cardPadding = 16.0;
  static const double cardMargin = 8.0;

  // Icon sizes
  static const double iconSm = 20.0;
  static const double iconMd = 24.0;
  static const double iconLg = 48.0;

  // Misc
  static const double fabBottomPadding = 96.0;
  static const double dividerThickness = 1.0;
  static const double badgeHeight = 28.0;

  // Legacy — keep for backward compat, delegate to new names
  static const double cardShadowBlur = 18.0;  // will be replaced
  static const double cardShadowOffsetY = 6.0; // will be replaced
}
```

### B6. Shared Card Component

Create `AppCard` to replace all 6+ inline container patterns:

```dart
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final AppElevationLevel elevation;
  final BorderRadius? borderRadius;
  final BoxBorder? border;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.elevation = AppElevationLevel.level1,
    this.borderRadius,
    this.border,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(AppSizes.cardRadius);
    final shadows = AppElevation.fromLevel(elevation);

    return Container(
      margin: margin ?? const EdgeInsets.all(AppSizes.cardMargin),
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: radius,
        boxShadow: shadows,
        border: border,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: onTap != null
            ? InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
                borderRadius: radius,
                child: Padding(
                  padding: padding ?? const EdgeInsets.all(AppSizes.cardPadding),
                  child: child,
                ),
              )
            : Padding(
                padding: padding ?? const EdgeInsets.all(AppSizes.cardPadding),
                child: child,
              ),
      ),
    );
  }
}

enum AppElevationLevel { none, level1, level2, level3 }
```

### B7. Dashboard Refresh

1. **Filter bar**: Add subtle `surfaceVariant` background, horizontal padding, reduce vertical padding. Move "Clear" to inline icon button.
2. **Section hierarchy**: Use `AppCard` with `elevation: level1` for collapsible sections. Use `AppCard` with `elevation: none` + border for flat metric rows inside.
3. **KPI cards**: Reduce shadow to `level1`, increase value font to `metricLarge`, add subtle color accent bar on left.
4. **Visit sessions**: Replace `Card + ExpansionTile` with `AppCard` + custom expand header (remove double shadow).
5. **Section headers**: Change from `titleSmall` (14px) to `sectionTitle` (18px w700).
6. **Metric rows**: Add `statusGood/Warning/Error` color tokens instead of inline hex.
7. **Empty states**: Use `AppColors.textTertiary` and `AppColors.textSecondary` instead of `Colors.black45/26`.
8. **Spacing**: Replace all `SizedBox(height: 16)` with `SizedBox(height: AppSizes.spaceXl)` for sections, `AppSizes.spaceLg` for internal card gaps.
9. **Visit session date chips**: Use `AppBadge` widget instead of raw `ChoiceChip`.

### B8. Micro-Animation Additions

**8a. Button Press Scale** — `ScaleButton` wrapper:
```dart
class ScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown; // default 0.97

  // On tap: scale to 0.97 100ms → scale back 100ms
  // On tapCancel: scale back 100ms
}
```

Apply to: `ElevatedButton`, `OutlinedButton`, `TextButton`, `QuickActionButton`, card tiles.

**8b. Card Elevation on Tap** — Use `AnimatedContainer` for shadow transitions:
```dart
// In AppCard:
AnimatedContainer(
  duration: const Duration(milliseconds: 200),
  decoration: BoxDecoration(
    boxShadow: isPressed ? AppElevation.level2 : AppElevation.level1,
    ...
  ),
)
```

**8c. Page Transitions** — Replace `MaterialPageRoute` with custom `PageRouteBuilder`:
```dart
class AppPageRoute extends PageRouteBuilder {
  AppPageRoute({required WidgetBuilder builder})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) => builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 250),
      );
}
```

**8d. Save Success** — Subtle check animation:
```dart
class SuccessCheckmark extends StatefulWidget {
  // 24px circle, green ✓ icon, fadeIn + scale 100ms, hold 800ms, fadeOut 200ms
}
```
Replace `SnackBar(content: Text('Sync complete'))` with success animation.

**8e. Chart Entry** — Add `curve: Curves.easeOutCubic` to fl_chart animations (already supported via `swapAnimationDuration` and `swapAnimationCurve`).

**8f. TempToggle Animated Selector** — Replace `GestureDetector` with `AnimatedContainer` for the selected segment:
```dart
// Add AnimatedContainer with color transition 150ms
// Add slide transition using AnimatedSlide or positioned container
```

### B9. Logo Exploration Concepts

Since the logo is an image asset (`assets/branding/chickmark-logo.png`), I'll provide concept directions rather than SVG code:

**9a. Monoline Apple-style**: Single-weight stroke, continuous line chick silhouette. Minimal, technical. Works at 24px. No fill, just outline.

**9b. Negative-Space Hidden Symbol**: Chick outline with a thermometer or egg shape embedded in negative space. Premium dual-meaning mark.

**9c. Premium Badge**: Encircled chick icon with subtle gradient stroke. Shield or circular badge form. Works for app icon and splash.

**9d. App Icon Variant**: Rounded square (squircle) with brand gradient background, white monoline chick symbol centered. Follows Apple HIG icon format.

**Implementation**: Would require a designer to produce SVG assets. Code-side, we'd need to:
1. Add new logo assets to `assets/branding/`
2. Update `ChickMarkLogo` widget to support variant selection
3. Add app icon configuration in `ios/Runner/Assets.xcassets` and `android/app/src/main/res/`

### B10. Component Polish Summary

| Component | Current | Proposed |
|---|---|---|
| `ElevatedButton` | No press feedback | `ScaleButton` wrapper, 0.97 scale |
| `OutlinedButton` | Hardcoded radius 10 in home | Use `AppSizes.buttonRadius` (12) |
| `TextButton` | No changes | No change needed |
| `StatusBadge` | radius 16, no animation | radius 8, `AnimatedContainer` color |
| `SectionCard` | Inline styles, Opacity(0.6) saved | Use `AppTextStyles.sectionTitle`, fade to 40% opacity |
| `TempToggle` | No animation | `AnimatedContainer` slide + color |
| `InputDecoration` | radius 16 | radius 12 (matches buttonRadius) |
| `ChoiceChip` | Various patterns | Unify with `AppColors.statusGood/warning/error` |
| `FilterChip` | Place-color dependent | Keep, consistent radius |
| `BottomSheet` | radius 24, drag handle | Keep radius, smoother handle (6px x 40px) |
| `Dialog` | 420px wide | Keep, add subtle slide-in transition |
| `Card` (theme) | elevation 2, radius 18 | elevation 1, radius 14, shadow `level1` |
| `_KpiCard` etc. | 6 inline patterns | Refactor to `AppCard` |
| Dashboard sections | Raw `Card` + `ExpansionTile` | `AppCard` + custom header |
| Date chips | Raw `ChoiceChip` | Consistent badge styling |

---

## C. REVISED DESIGN SYSTEM

### C1. Color Palette (Revised)

```dart
class AppColors {
  // Brand
  static const Color primary = Color(0xFF1769D8);
  static const Color primaryLight = Color(0xFF079FE0);
  static const Color primaryDark = Color(0xFF193FC2);
  static const LinearGradient brandGradient = LinearGradient(
    colors: [primaryLight, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Accent (Zoetis-inspired orange — restrained accent only)
  static const Color accent = Color(0xFFE65100);         // used sparingly: attention dots, key CTAs
  static const Color accentBg = Color(0xFFFFF3E0);       // warmup bg, attention bg

  // Surface
  static const Color background = Color(0xFFF5F8FC);     // scaffold
  static const Color surface = Color(0xFFFFFFFF);         // cards, modals
  static const Color surfaceVariant = Color(0xFFF9FAFB);  // subtle bg, tile bg
  static const Color surfaceRaised = Color(0xFFF7FAFD);   // session tiles

  // Text
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);
  static const Color textDisabled = Color(0xFFD1D5DB);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Border
  static const Color borderDefault = Color(0xFFE5E7EB);
  static const Color borderFocused = Color(0xFF1769D8);

  // Status
  static const Color statusGood = Color(0xFF388E3C);
  static const Color statusGoodBg = Color(0xFFE8F5E9);
  static const Color statusWarning = Color(0xFFE67E22);
  static const Color statusWarningBg = Color(0xFFFFF3E0);
  static const Color statusError = Color(0xFFDC2626);
  static const Color statusErrorBg = Color(0xFFFEF2F2);
  static const Color statusActive = Color(0xFF193FC2);
  static const Color statusActiveBg = Color(0xFFE8F2FF);
  static const Color statusNeutralBg = Color(0xFFF3F4F6);
  static const Color statusNeutralText = Color(0xFF4B5563);

  // Semantic (kept for backward compat)
  static const Color completedBg = statusGoodBg;
  static const Color completedText = statusGood;
  static const Color activeBg = statusActiveBg;
  static const Color activeText = statusActive;
  static const Color ageBadgeBg = Color(0xFFEAF4FF);
  static const Color cardBackground = surface;
  static const Color cardShadow = Color(0x14000000);      // ~8% opacity — lighter
  static const Color cardShadowElevated = Color(0x1A000000); // ~10% for hover/elevated
  static const Color greenTab = statusGood;
  static const Color inactiveTab = Color(0xFF9CA3AF);       // was Colors.grey
  static const Color infoBg = ageBadgeBg;
  static const Color infoText = Color(0xFF1557B0);

  // Chart palette
  static const Color chart1 = Color(0xFF1769D8);
  static const Color chart2 = Color(0xFF388E3C);
  static const Color chart3 = Color(0xFFE67E22);
  static const Color chart4 = Color(0xFF7E57C2);
  static const Color chart5 = Color(0xFF00897B);
  static const Color chart6 = Color(0xFFD81B60);
  static const Color chart7 = Color(0xFF5D6D7E);
  static const Color chartGridHorizontal = Color(0xFFE2EAF2);
  static const Color chartGridVertical = Color(0xFFEAF0F6);
  static const Color chartEmptyBorder = Color(0xFFE0E7EF);

  // Dividers
  static const Color divider = Color(0xFFE5E7EB);
}
```

### C2. Typography (Revised)

```dart
class AppTextStyles {
  // Core scale (8pt-aligned sizes)
  static const TextStyle displayLarge = TextStyle(  // 32px
    fontWeight: FontWeight.w700, fontSize: 32, height: 1.12, color: AppColors.textPrimary,
  );
  static const TextStyle displayMedium = TextStyle(  // 28px
    fontWeight: FontWeight.w700, fontSize: 28, height: 1.14, color: AppColors.textPrimary,
  );
  static const TextStyle displaySmall = TextStyle(   // 24px
    fontWeight: FontWeight.w700, fontSize: 24, height: 1.18, color: AppColors.textPrimary,
  );
  static const TextStyle heading = TextStyle(        // 22px
    fontWeight: FontWeight.w700, fontSize: 22, height: 1.18, color: AppColors.textPrimary,
  );
  static const TextStyle sectionTitle = TextStyle(   // 18px
    fontWeight: FontWeight.w700, fontSize: 18, height: 1.25, color: AppColors.textPrimary,
  );
  static const TextStyle title = TextStyle(          // 16px
    fontWeight: FontWeight.w600, fontSize: 16, height: 1.30, color: AppColors.textPrimary,
  );
  static const TextStyle subtitle = TextStyle(       // 14px w600
    fontWeight: FontWeight.w600, fontSize: 14, height: 1.30, color: AppColors.textSecondary,
  );
  static const TextStyle body = TextStyle(           // 15px
    fontWeight: FontWeight.w400, fontSize: 15, height: 1.40, color: Color(0xFF1F2937),
  );
  static const TextStyle caption = TextStyle(        // 12px
    fontWeight: FontWeight.w500, fontSize: 12, height: 1.35, color: AppColors.textSecondary,
  );
  static const TextStyle badge = TextStyle(          // 13px
    fontWeight: FontWeight.w700, fontSize: 13, height: 1.20, color: AppColors.textOnPrimary,
  );
  static const TextStyle badgeLabel = TextStyle(     // 12px w700 — for chip text
    fontWeight: FontWeight.w700, fontSize: 12, height: 1.20, color: AppColors.textPrimary,
  );
  static const TextStyle metricLarge = TextStyle(   // 28px — KPI numbers
    fontWeight: FontWeight.w700, fontSize: 28, height: 1.10, color: AppColors.textPrimary,
  );
  static const TextStyle wordmark = TextStyle(       // 28px Georgia
    fontFamily: 'Georgia', fontWeight: FontWeight.w700, fontSize: 28,
    color: AppColors.textPrimary, letterSpacing: 2.0,
  );

  // Note: FontWeight.w400 replaces FontWeight.normal for clarity
  // Note: FontWeight.w700 replaces FontWeight.bold for consistency
}
```

### C3. Sizes & Spacing (Revised)

```dart
class AppSizes {
  // ── Radius ──
  static const double cardRadius = 14.0;
  static const double buttonRadius = 12.0;
  static const double badgeRadius = 8.0;
  static const double iconRadius = 12.0;
  static const double inputRadius = 12.0;
  static const double sheetRadius = 24.0;
  static const double dialogRadius = 14.0;
  static const double pillRadius = 999.0;

  // ── Spacing (8pt grid) ──
  static const double spaceXs = 4.0;
  static const double spaceSm = 8.0;
  static const double spaceMd = 12.0;
  static const double spaceLg = 16.0;
  static const double spaceXl = 24.0;
  static const double spaceXxl = 32.0;

  // ── Padding ──
  static const double cardPadding = 16.0;
  static const double cardMargin = 8.0;
  static const double sectionPadding = 16.0;

  // ── Icon sizes ──
  static const double iconSm = 20.0;
  static const double iconMd = 24.0;
  static const double iconLg = 48.0;
  static const double iconContainerSm = 36.0;   // was 38-42 varying
  static const double iconContainerMd = 44.0;   // was 40-42 varying

  // ── Misc ──
  static const double dividerThickness = 1.0;
  static const double badgeHeight = 28.0;
  static const double fabBottomPadding = 96.0;

  // ── Legacy (backwards compat) ──
  static const double cardShadowBlur = 18.0;
  static const double cardShadowOffsetY = 6.0;
}
```

### C4. Shadows (New)

```dart
class AppElevation {
  static List<BoxShadow> get none => [];

  static List<BoxShadow> get level1 => [
    BoxShadow(
      color: const Color(0x0F000000),
      blurRadius: AppSizes.spaceSm,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get level2 => [
    BoxShadow(
      color: const Color(0x1A000000),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get level3 => [
    BoxShadow(
      color: const Color(0x1A000000),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> fromLevel(AppElevationLevel level) {
    return switch (level) {
      AppElevationLevel.none => none,
      AppElevationLevel.level1 => level1,
      AppElevationLevel.level2 => level2,
      AppElevationLevel.level3 => level3,
    };
  }
}

enum AppElevationLevel { none, level1, level2, level3 }
```

### C5. Theme Updates (Revised `AppTheme`)

```dart
class AppTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.primaryLight,
      surface: AppColors.surface,
      error: AppColors.statusError,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: AppTextStyles.textTheme,
      visualDensity: VisualDensity.standard,

      dividerColor: AppColors.divider,
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: AppSizes.dividerThickness,
        space: AppSizes.spaceLg,
      ),

      appBarTheme: const AppBarTheme(
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),

      cardTheme: CardThemeData(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        ),
        elevation: 0,                                    // CHANGED: no Material elevation
        shadowColor: AppColors.cardShadow,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.all(AppSizes.cardMargin),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.spaceLg,
            vertical: AppSizes.spaceMd,
          ),
          textStyle: AppTextStyles.badge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.spaceLg,
            vertical: AppSizes.spaceMd,
          ),
          textStyle: AppTextStyles.badge.copyWith(color: AppColors.primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: AppTextStyles.badge.copyWith(color: AppColors.primary),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        labelStyle: AppTextStyles.caption,
        hintStyle: AppTextStyles.caption,
        floatingLabelStyle: AppTextStyles.caption.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSizes.spaceLg,
          vertical: AppSizes.spaceMd,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.inputRadius),
          borderSide: const BorderSide(color: AppColors.borderDefault),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.inputRadius),
          borderSide: const BorderSide(color: AppColors.borderDefault),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.inputRadius),
          borderSide: const BorderSide(color: AppColors.borderFocused, width: 1.5),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primary,
        checkmarkColor: Colors.white,
        side: const BorderSide(color: AppColors.borderDefault),
        labelStyle: AppTextStyles.badgeLabel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
        ),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.inactiveTab,
        selectedLabelStyle: AppTextStyles.caption.copyWith(
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: AppTextStyles.caption,
      ),
    );
  }
}
```

---

## D. SAFE IMPLEMENTATION PLAN

### Phase 1: Foundation (Non-breaking token additions)
**Risk: MINIMAL** — Additive only, no visual changes yet.

1. Expand `AppColors` with new semantic tokens (add to existing file, don't remove old tokens)
2. Expand `AppSizes` with spacing + radius tokens (additive)
3. Expand `AppTextStyles` with new tokens (`badgeLabel`, `metricLarge`, `subtitle`)
4. Create `AppElevation` class in new file `lib/core/theme/app_elevation.dart`
5. Create `AppCard` widget in `lib/widgets/app_card.dart`

### Phase 2: Shadow + Radius Refinement (Visual, low-risk)
**Risk: LOW** — Changes shadow softness and corner roundness.

6. Update `AppTheme` card theme: `elevation: 0`, shadow via `AppElevation`
7. Reduce `cardRadius` from 18 → 14
8. Reduce `buttonRadius` from 16 → 12
9. Add `inputRadius` = 12 (replace `buttonRadius` in `InputDecorationTheme`)
10. Update `GradientAppBar` shadow to `AppElevation.level3`
11. Update `StatusBadge` radius from 16 → 8

### Phase 3: Color Unification (Visual, low-risk)
**Risk: LOW** — Replaces hardcoded colors with tokens.

12. Replace all `Colors.black87` → `AppColors.textPrimary`
13. Replace all `Colors.grey[600]` / `Colors.grey.shade600` → `AppColors.textSecondary`
14. Replace all `Colors.black45` → `AppColors.textTertiary`
15. Replace all `Colors.black26` → `AppColors.textDisabled`
16. Replace all `Colors.grey.shade200` → `AppColors.borderDefault`
17. Replace threshold colors `Color(0xFF3a9a5c)` → `AppColors.statusGood`
18. Replace threshold colors `Color(0xFFE24B4A)` → `AppColors.statusError`
19. Replace `Color(0xFFE6A23C)` → `AppColors.statusWarning`
20. Replace `Colors.red[50]` → `AppColors.statusErrorBg`
21. Replace `Colors.red[700]` → `AppColors.statusError`
22. Replace `Colors.orange.shade700/800` → `AppColors.statusWarning`/`statusWarningBg`

### Phase 4: Typography Unification (Visual, low-risk)
**Risk: LOW** — Replaces inline styles with design token references.

23. Replace `SectionCard.title` inline style → `AppTextStyles.sectionTitle`
24. Replace `_sectionHeader` → use `AppTextStyles.sectionTitle`
25. Replace all `FontWeight.bold` → `FontWeight.w700`
26. Replace all inline `fontSize` + `fontWeight` combinations → `AppTextStyles` tokens
27. Replace `TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primary)` → `AppTextStyles.metricLarge.copyWith(color: AppColors.primary)`
28. Replace `TextStyle(fontSize: 13, color: ...)`, `TextStyle(fontSize: 12, fontWeight: FontWeight.bold)` → `AppTextStyles.badgeLabel` or `AppTextStyles.caption`
29. Replace `TextStyle(color: Colors.grey)` → `AppTextStyles.caption` or `copyWith(color: AppColors.textSecondary)`

### Phase 5: Spacing Standardization (Visual, low-risk)
**Risk: LOW** — Replaces magic numbers with spacing constants.

30. Replace all `SizedBox(height: 3)` → `SizedBox(height: AppSizes.spaceXs)`
31. Replace all `SizedBox(height: 4)` → `SizedBox(height: AppSizes.spaceXs)`
32. Replace all `SizedBox(height: 6)` → `SizedBox(height: AppSizes.spaceSm)`
33. Replace all `SizedBox(height: 8)` / `SizedBox(width: 8)` → `AppSizes.spaceSm`
34. Replace all `SizedBox(height: 12)` / `SizedBox(width: 12)` → `AppSizes.spaceMd`
35. Replace all `SizedBox(height: 14)` → consolidate to `AppSizes.spaceLg`
36. Replace all `SizedBox(height: 16)` / `SizedBox(width: 16)` → `AppSizes.spaceLg`
37. Replace all section gaps `SizedBox(height: 24)` → `AppSizes.spaceXl`
38. Replace `padding: EdgeInsets.all(14)` → `EdgeInsets.all(AppSizes.spaceLg)` (16)
39. Replace `padding: EdgeInsets.all(12)` → `EdgeInsets.all(AppSizes.spaceMd)` (12)
40. Replace `padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6)` → badge padding

### Phase 6: Component Refactor (Visual + Structural, medium-risk)
**Risk: MEDIUM** — Replaces inline container patterns with shared `AppCard`.

41. Refactor `_KpiCard` → use `AppCard`
42. Refactor `_FocusMetricCard` → use `AppCard`
43. Refactor `_RecentAuditTile` → use `AppCard`
44. Refactor `_AttentionTile` → use `AppCard` with border
45. Refactor `_ShortcutTile` → use `AppCard`
46. Refactor `_EmptyHomeMessage` → use `AppCard`
47. Refactor `_buildStatCard` → use `AppCard`
48. Refactor sync status container → use `AppCard`
49. Refactor `SectionCard` shadow → `AppElevation.level1`

### Phase 7: Micro-Animations (Visual + Code, medium-risk)
**Risk: MEDIUM** — Adds animation widgets, must be performance-safe.

50. Create `ScaleButton` wrapper widget
51. Create `AppPageRoute` transition class
53. Add `AnimatedContainer` to `TempToggle` selected segment
54. Add chart animation curves to BmkBarChart, BmkDonutChart, BmkLineChart

### Phase 8: Dashboard Refresh (Visual, medium-risk)
**Risk: MEDIUM** — Changes dashboard layout and visual structure.

55. Refactor dashboard filter bar (improved visual hierarchy)
56. Refactor visit sessions section (remove double-shadow)
57. Standardize section headers to `AppTextStyles.sectionTitle`
58. Standardize empty states with `AppColors.textTertiary`
59. Apply `AppCard` to all dashboard sections
60. Add subtle spacing rhythm improvements

### Phase 9: Polish Pass (Visual, low-risk)
**Risk: LOW** — Final consistency pass.

61. Ensure all `IconThemeData(color: Colors.white)` on app bars
62. Ensure all card margins use `AppSizes.cardMargin`
63. Ensure all divider colors use `AppColors.divider`
64. Final review of all screens for remaining magic numbers

---

## E. COMPONENT-LEVEL CHANGES

### E1. `app_colors.dart` — Add tokens, keep legacy aliases
- ADD: `textPrimary`, `textSecondary`, `textTertiary`, `textDisabled`, `textOnPrimary`
- ADD: `borderDefault`, `borderFocused`
- ADD: `statusGood`, `statusWarning`, `statusError` + bg variants
- ADD: `surface`, `surfaceVariant`, `surfaceRaised`
- ADD: `accent`, `accentBg`
- ADD: `divider`
- ADD: chart palette tokens
- KEEP: `primary`, `primaryLight`, `primaryDark`, `background`, `ageBadgeBg`, `completedBg`, `completedText`, `activeBg`, `activeText`, `cardShadow`, `inactiveTab`, `greenTab`, `brandGradient` (as legacy compat)
- CHANGE: `cardBackground` → alias for `surface`
- CHANGE: `infoBg` → alias for `ageBadgeBg`

### E2. `app_text_styles.dart` — Add tokens
- ADD: `subtitle` (14px w600, textSecondary)
- ADD: `badgeLabel` (12px w700, textPrimary)
- ADD: `metricLarge` (28px w700, textPrimary)
- CHANGE: `body` fontWeight from `FontWeight.normal` to `FontWeight.w400`
- UPDATE: `TextTheme` mapping to use new color tokens

### E3. `app_sizes.dart` — Expand
- CHANGE: `cardRadius` from 18 → 14
- CHANGE: `buttonRadius` from 16 → 12
- ADD: `badgeRadius`, `iconRadius`, `inputRadius`, `sheetRadius`, `dialogRadius`, `pillRadius`
- ADD: spacing scale (`spaceXs` through `spaceXxl`)
- ADD: `iconSm`, `iconMd`, `iconLg`, `iconContainerSm`, `iconContainerMd`
- ADD: `dividerThickness`, `badgeHeight`, `fabBottomPadding`, `cardMargin`

### E4. `app_theme.dart` — Update
- CHANGE: Card theme elevation from 2 → 0, shadow via decoration
- CHANGE: Input border radius from `buttonRadius` → `inputRadius`
- CHANGE: Chip radius from `buttonRadius` → `badgeRadius`
- ADD: `dividerTheme` with `AppColors.divider`

### E5. `app_elevation.dart` — New file
- ADD: `AppElevation` class with `none`, `level1`, `level2`, `level3`
- ADD: `AppElevationLevel` enum

### E6. `app_card.dart` — New file
- ADD: `AppCard` stateless widget with `elevation`, `border`, `onTap` params
- Handles: shadow, radius, padding, Material + InkWell

### E7. `status_badge.dart` — Update
- CHANGE: radius from 16 → `AppSizes.badgeRadius` (8)
- CHANGE: padding to `EdgeInsets.symmetric(horizontal: AppSizes.spaceMd, vertical: AppSizes.spaceXs)`
- ADD: `AnimatedContainer` for color transitions (150ms)

### E8. `section_card.dart` — Update
- CHANGE: title style from inline → `AppTextStyles.sectionTitle`
- CHANGE: shadow from inline → `AppElevation.level2`
- CHANGE: saved state border to use `AppColors.statusGood`
- CHANGE: opacity from 0.6 → 0.4 (cleaner Apple style)

### E9. `temp_toggle.dart` — Update
- ADD: `AnimatedContainer` for segment color transition
- ADD: `AnimatedSlide` or positioned `AnimatedContainer` for selector slide

### E10. `gradient_app_bar.dart` — Update
- CHANGE: shadow from `AppColors.cardShadow / cardShadowBlur / cardShadowOffsetY` → `AppElevation.level3`
- No other changes needed

### E11. Home screen private widgets
- `_KpiCard`, `_FocusMetricCard`, `_RecentAuditTile`, `_AttentionTile`, `_ShortcutTile`, `_EmptyHomeMessage`, `_buildStatCard`, sync status container — all refactor to use `AppCard`
- Replace inline `Colors.white` → `AppColors.surface`
- Replace inline icon container sizes (38, 40, 42) → `AppSizes.iconContainerSm/Md`
- Replace hardcoded radius 12 → `AppSizes.iconRadius`
- Replace hardcoded radius 10 → `AppSizes.buttonRadius`
- Replace hardcoded font sizes → `AppTextStyles` tokens

### E12. Dashboard screen
- Replace `Card + ExpansionTile` → `AppCard + ExpansionTile` with no elevation
- Replace `_buildCascadeFilter` dropdown borders → `AppColors.borderDefault`
- Replace hardcoded metric text styles → `AppTextStyles` tokens
- Replace `_findingChip` → consistent `StatusBadge` pattern
- Replace session date format → localized format

### E13. `main_shell.dart` — Update
- ADD: `AppPageRoute` for page transitions (if desired)
- No structural changes needed

---

## F. CODE-LEVEL SUGGESTIONS

### F1. `lib/core/constants/app_colors.dart` — Full Revised File

```dart
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Brand ──
  static const Color primary = Color(0xFF1769D8);
  static const Color primaryLight = Color(0xFF079FE0);
  static const Color primaryDark = Color(0xFF193FC2);
  static const Color accent = Color(0xFFE65100);
  static const Color accentBg = Color(0xFFFFF3E0);
  static const LinearGradient brandGradient = LinearGradient(
    colors: [primaryLight, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Surface ──
  static const Color background = Color(0xFFF5F8FC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF9FAFB);
  static const Color surfaceRaised = Color(0xFFF7FAFD);

  // ── Text ──
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);
  static const Color textDisabled = Color(0xFFD1D5DB);
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color textBody = Color(0xFF1F2937);

  // ── Border ──
  static const Color borderDefault = Color(0xFFE5E7EB);
  static const Color borderFocused = Color(0xFF1769D8);

  // ── Status ──
  static const Color statusGood = Color(0xFF388E3C);
  static const Color statusGoodBg = Color(0xFFE8F5E9);
  static const Color statusWarning = Color(0xFFE67E22);
  static const Color statusWarningBg = Color(0xFFFFF3E0);
  static const Color statusError = Color(0xFFDC2626);
  static const Color statusErrorBg = Color(0xFFFEF2F2);
  static const Color statusActive = Color(0xFF193FC2);
  static const Color statusActiveBg = Color(0xFFE8F2FF);
  static const Color statusNeutralBg = Color(0xFFF3F4F6);
  static const Color statusNeutralText = Color(0xFF4B5563);

  // ── Shadow ──
  static const Color cardShadow = Color(0x14000000);
  static const Color cardShadowElevated = Color(0x1A000000);

  // ── Semantic Aliases (backward compat) ──
  static const Color completedBg = statusGoodBg;
  static const Color completedText = statusGood;
  static const Color activeBg = statusActiveBg;
  static const Color activeText = statusActive;
  static const Color ageBadgeBg = Color(0xFFEAF4FF);
  static const Color cardBackground = surface;
  static const Color greenTab = statusGood;
  static const Color inactiveTab = Color(0xFF9CA3AF);
  static const Color infoBg = ageBadgeBg;
  static const Color infoText = Color(0xFF1557B0);

  // ── Chart ──
  static const Color chart1 = Color(0xFF1769D8);
  static const Color chart2 = Color(0xFF388E3C);
  static const Color chart3 = Color(0xFFE67E22);
  static const Color chart4 = Color(0xFF7E57C2);
  static const Color chart5 = Color(0xFF00897B);
  static const Color chart6 = Color(0xFFD81B60);
  static const Color chart7 = Color(0xFF5D6D7E);
  static const Color chartGridH = Color(0xFFE2EAF2);
  static const Color chartGridV = Color(0xFFEAF0F6);
  static const Color chartEmptyBorder = Color(0xFFE0E7EF);

  // ── Dividers ──
  static const Color divider = Color(0xFFE5E7EB);
}
```

### F2. `lib/core/constants/app_sizes.dart` — Full Revised File

```dart
class AppSizes {
  AppSizes._();

  // ── Radius ──
  static const double cardRadius = 14.0;
  static const double buttonRadius = 12.0;
  static const double badgeRadius = 8.0;
  static const double iconRadius = 12.0;
  static const double inputRadius = 12.0;
  static const double sheetRadius = 24.0;
  static const double dialogRadius = 14.0;
  static const double pillRadius = 999.0;

  // ── Spacing (8pt grid) ──
  static const double spaceXs = 4.0;
  static const double spaceSm = 8.0;
  static const double spaceMd = 12.0;
  static const double spaceLg = 16.0;
  static const double spaceXl = 24.0;
  static const double spaceXxl = 32.0;

  // ── Padding ──
  static const double cardPadding = 16.0;
  static const double cardMargin = 8.0;

  // ── Icon sizes ──
  static const double iconSm = 20.0;
  static const double iconMd = 24.0;
  static const double iconLg = 48.0;
  static const double iconContainerSm = 36.0;
  static const double iconContainerMd = 44.0;

  // ── Misc ──
  static const double dividerThickness = 1.0;
  static const double badgeHeight = 28.0;
  static const double fabBottomPadding = 96.0;

  // ── Legacy (gradual migration) ──
  static const double cardShadowBlur = 18.0;
  static const double cardShadowOffsetY = 6.0;
}
```

### F3. `lib/core/theme/app_elevation.dart` — New File

```dart
import 'package:flutter/material.dart';
import '../constants/app_sizes.dart';

enum AppElevationLevel { none, level1, level2, level3 }

class AppElevation {
  AppElevation._();

  static List<BoxShadow> fromLevel(AppElevationLevel level) {
    return switch (level) {
      AppElevationLevel.none => none,
      AppElevationLevel.level1 => level1,
      AppElevationLevel.level2 => level2,
      AppElevationLevel.level3 => level3,
    };
  }

  static List<BoxShadow> get none => [];

  static List<BoxShadow> get level1 => [
    BoxShadow(
      color: const Color(0x0F000000),
      blurRadius: AppSizes.spaceSm,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get level2 => [
    BoxShadow(
      color: const Color(0x1A000000),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get level3 => [
    BoxShadow(
      color: const Color(0x1A000000),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];
}
```

### F4. `lib/widgets/app_card.dart` — New File

```dart
import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_sizes.dart';
import '../core/theme/app_elevation.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final AppElevationLevel elevation;
  final BorderRadius? borderRadius;
  final BoxBorder? border;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.elevation = AppElevationLevel.level1,
    this.borderRadius,
    this.border,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(AppSizes.cardRadius);
    final shadows = AppElevation.fromLevel(elevation);

    return Container(
      margin: margin ?? const EdgeInsets.all(AppSizes.cardMargin),
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: radius,
        boxShadow: shadows,
        border: border,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: onTap != null
            ? InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
                borderRadius: radius,
                child: Padding(
                  padding: padding ?? const EdgeInsets.all(AppSizes.cardPadding),
                  child: child,
                ),
              )
            : Padding(
                padding: padding ?? const EdgeInsets.all(AppSizes.cardPadding),
                child: child,
              ),
      ),
    );
  }
}
```

### F5. `lib/widgets/scale_button.dart` — New File

```dart
import 'package:flutter/material.dart';

class ScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown;
  final Duration duration;

  const ScaleButton({
    super.key,
    required this.child,
    this.onTap,
    this.scaleDown = 0.97,
    this.duration = const Duration(milliseconds: 100),
  });

  @override
  State<ScaleButton> createState() => _ScaleButtonState();
}

class _ScaleButtonState extends State<ScaleButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      reverseDuration: widget.duration,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: widget.scaleDown).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(scale: _scaleAnimation, child: widget.child),
    );
  }
}
```

### F6. `lib/core/theme/app_page_route.dart` — New File

```dart
import 'package:flutter/material.dart';

class AppPageRoute<T> extends PageRouteBuilder<T> {
  AppPageRoute({required WidgetBuilder builder, super.settings})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) => builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 200),
      );
}
```

### F7. Key Migration Examples

**Before** (home_screen.dart `_KpiCard`):
```dart
Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(AppSizes.cardRadius),
    boxShadow: const [
      BoxShadow(color: AppColors.cardShadow, blurRadius: AppSizes.cardShadowBlur, offset: Offset(0, AppSizes.cardShadowOffsetY)),
    ],
  ),
  // ...
)
```

**After**:
```dart
AppCard(
  child: Row(
    children: [
      Container(
        width: AppSizes.iconContainerMd,
        height: AppSizes.iconContainerMd,
        decoration: BoxDecoration(
          color: AppColors.activeBg,
          borderRadius: BorderRadius.circular(AppSizes.iconRadius),
        ),
        child: Icon(icon, color: AppColors.primary),
      ),
      const SizedBox(width: AppSizes.spaceMd),
      // ...
    ],
  ),
)
```

**Before** (status_badge.dart):
```dart
Container(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  decoration: BoxDecoration(
    color: bgColor,
    borderRadius: BorderRadius.circular(16),
  ),
  child: Text(displayLabel, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 12)),
)
```

**After**:
```dart
Container(
  padding: const EdgeInsets.symmetric(horizontal: AppSizes.spaceMd, vertical: AppSizes.spaceXs),
  decoration: BoxDecoration(
    color: bgColor,
    borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
  ),
  child: Text(displayLabel, style: AppTextStyles.badgeLabel.copyWith(color: textColor)),
)
```

**Before** (section_card.dart title):
```dart
Text(title!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87))
```

**After**:
```dart
Text(title!, style: AppTextStyles.sectionTitle)
```

**Before** (dashboard date format):
```dart
Text('${s.session.date.day}/${s.session.date.month}/${s.session.date.year}')
```

**After**:
```dart
Text(DateFormat.yMd().format(s.session.date))
```

---

## Implementation Priority Matrix

| Phase | Risk | Impact | Effort | Recommended Order |
|---|---|---|---|---|
| Phase 1: Foundation | MINIMAL | High | Low | **1st** |
| Phase 3: Color | LOW | High | Medium | **2nd** |
| Phase 4: Typography | LOW | High | Medium | **3rd** |
| Phase 5: Spacing | LOW | Medium | Medium | **4th** |
| Phase 2: Shadow/Radius | LOW | High | Low | **5th** |
| Phase 8: Dashboard | MEDIUM | High | Medium | **6th** |
| Phase 6: Component Refactor | MEDIUM | High | High | **7th** |
| Phase 7: Animations | MEDIUM | Medium | Medium | **8th** |
| Phase 9: Polish Pass | LOW | Medium | Low | **9th** |

Each phase should be a separate PR to keep the diff reviewable and revertible without breaking existing functionality.

---

## What This Does NOT Touch

- No provider/state management changes
- No database model changes
- No routing changes (only transition animation wrappers)
- No business logic changes
- No Supabase/API changes
- No functionality changes — purely visual refinements
- Existing `AppColors` legacy aliases kept for backward compatibility
- All existing widgets work without modification until phased migration