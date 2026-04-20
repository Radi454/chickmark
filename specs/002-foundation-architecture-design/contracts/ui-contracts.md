# UI Contracts: Phase 1 — Foundation, Architecture & Design System

**Date**: 2026-04-18
**Branch**: `002-foundation-architecture-design`

These contracts define the public interface of each shared widget and service stub
produced in Phase 1. Any Phase 2+ feature that consumes these widgets must respect
these contracts. Changes require a plan amendment.

---

## Shared Widgets

### `ChickMarkLogo` (`lib/widgets/chick_mark_logo.dart`)

**Purpose**: Renders the full brand identity — SVG logo, wordmark, tagline.

```dart
ChickMarkLogo({
  double? logoSize,        // Default 80.0
  bool showWordmark,       // Default true
  bool showTagline,        // Default true
  bool compact,            // Default false — stacks logo above wordmark
})
```

**Behaviour**:
- If SVG asset unavailable, renders a styled text fallback: orange "C" in a circle.
- `compact: true` renders only the logo mark (no wordmark/tagline) at smaller size.

---

### `TempToggle` (`lib/widgets/temp_toggle.dart`)

**Purpose**: [°C / °F] segmented toggle. Reads/writes temp unit preference from
`AppProvider`.

```dart
TempToggle({
  // No required params — reads from context (AppProvider)
})
```

**Behaviour**:
- Placed in AppBar actions on screens with temperature fields.
- Active segment uses `AppColors.primary` (#F65C00) fill.
- Switching unit triggers `AppProvider.setTempUnit(TempUnit)` which notifies all
  listening widgets.
- Does not store the value itself; `AppProvider` persists to `shared_preferences`.

---

### `StatusBadge` (`lib/widgets/status_badge.dart`)

**Purpose**: Renders a coloured pill badge for audit status.

```dart
StatusBadge({
  required String status,   // 'completed' | 'active'
  String? label,            // Override display text (defaults to capitalized status)
})
```

**Variants**:
- `completed`: `#e8f5e9` background, `#388e3c` text
- `active`: `#fff8e1` background, `#f57c00` text
- Unknown status falls back to grey.

---

### `SectionCard` (`lib/widgets/section_card.dart`)

**Purpose**: Standard card container used throughout the app.

```dart
SectionCard({
  required Widget child,
  String? title,           // Optional section heading inside card
  EdgeInsets? padding,     // Default: 16px all sides
  bool isSaved,            // Default false — if true, shows green top border/tab
  VoidCallback? onEdit,    // If provided and isSaved==true, shows Edit button
})
```

**Behaviour**:
- Border radius: 14px.
- Box shadow: `BoxShadow(color: Color(0x0F000000), blurRadius: 4, offset: Offset(0,1))`.
- `isSaved: true` renders a 3px green top border (`#388e3c`) and a small "Edit" button
  in the top-right corner. All child inputs are `enabled: false` when `isSaved: true`.

---

### `TroubleshootingIcon` (`lib/widgets/troubleshooting_icon.dart`)

**Purpose**: 💡 stub widget — Phase 1 creates the widget shell; functionality
activated in Phase 2+.

```dart
TroubleshootingIcon({
  required String category,   // 'egg_breakout' | 'pasgar'
  required String parameter,
  bool visible,               // Default false in Phase 1 (no-op stub)
})
```

**Phase 1 behaviour**: Renders nothing (`SizedBox.shrink()`) regardless of `visible`.
Phase 2+ will render the 💡 icon and open the troubleshooting bottom sheet.

---

## Service Contracts

### `SupabaseService` (`lib/services/supabase/supabase_service.dart`)

```dart
abstract class SupabaseService {
  bool get isAvailable;

  Future<AuthResult> signIn(String email, String password);
  Future<AuthResult> signUp(String email, String password, String fullName);
  Future<void> sendPasswordReset(String email);
  Future<void> signOut();
  Future<void> syncAudit(AuditModel audit);   // Background; never throws to caller
}

class AuthResult {
  final bool success;
  final String? error;
  final UserModel? user;
}
```

**Degradation**: If `isAvailable == false` (no network at init), `signIn` / `signUp`
return `AuthResult(success: false, error: 'offline')`. Offline login is handled by
`AuthProvider` using the cached SQLite token, not by `SupabaseService`.

---

### `GoveeService` (`lib/services/govee/govee_service.dart`)

```dart
abstract class GoveeService {
  bool get isAvailable;   // false if Bluetooth unsupported or permission denied
  bool get isConnected;

  Future<void> startScan();
  Future<void> stopScan();
  Stream<GoveeSensorReading> get readings;
}

class GoveeSensorReading {
  final double? temperatureFahrenheit;
  final double? humidity;
  final DateTime timestamp;
}
```

**Degradation**: If `isAvailable == false`, `startScan()` is a no-op; `readings`
is an empty stream. UI guards: `if (goveeService.isAvailable) TempToggle()`.

---

### `OcrService` (`lib/services/ocr/ocr_service.dart`)

```dart
abstract class OcrService {
  bool get isAvailable;   // false if camera unavailable or permission denied

  Future<String?> recognizeText(String imagePath);
}
```

**Degradation**: If `isAvailable == false`, `recognizeText` returns `null`. UI
shows the OCR button only when `isAvailable == true`.

---

## AppProvider Contract (`lib/providers/app_provider.dart`)

```dart
enum TempUnit { fahrenheit, celsius }

class AppProvider extends ChangeNotifier {
  UserModel? get currentUser;
  TempUnit get tempUnit;          // Default: TempUnit.fahrenheit

  void setCurrentUser(UserModel? user);
  void setTempUnit(TempUnit unit);  // Persists to shared_preferences
}
```

**Contract**: All screens access `tempUnit` from `AppProvider` via `context.watch`.
Temperature display widgets use `TempConverter.display(value, showCelsius: appProvider.tempUnit == TempUnit.celsius)`.

---

## AuthProvider Contract (`lib/features/auth/providers/auth_provider.dart`)

```dart
enum AuthState { unauthenticated, loading, authenticated, pendingApproval, error }

class AuthProvider extends ChangeNotifier {
  AuthState get state;
  String? get errorMessage;
  UserModel? get user;

  Future<void> login(String email, String password);
  Future<void> register(String fullName, String email, String password);
  Future<void> logout();
  Future<void> checkCachedToken();  // Called on app init
}
```

**Routing logic** (in `app.dart`):
- `unauthenticated` → `LoginScreen`
- `loading` → `SplashScreen` (or loading overlay)
- `authenticated` → `MainShell` (6-tab bottom nav)
- `pendingApproval` → `PendingApprovalScreen`
- `error` → `LoginScreen` with error message
