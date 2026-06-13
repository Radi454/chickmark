# Seven-Segment Temperature OCR Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Read the large central temperature from the hatchery's red-backlit seven-segment thermometer, add per-sector Fahrenheit/Celsius selection defaulting to Fahrenheit, and warn before using a reading whose detected device unit differs from the selected unit.

**Architecture:** Extend the shared OCR layer to return a structured reading with detected unit, add a device-focused main-display crop and red-LCD preprocessing variants, and carry mismatch state through the existing reusable capture controller/screen. Keep every panel's current canonical persistence unit and convert through a shared sector-unit adapter at the UI boundary.

**Tech Stack:** Flutter/Dart, `package:image`, Google ML Kit text recognition, Provider, Flutter widget/unit tests.

---

### Task 1: Structured Temperature Units And OCR Candidates

**Files:**
- Modify: `lib/services/ocr/ocr_service.dart`
- Modify: `test/services/ocr/ocr_service_test.dart`

- [ ] **Step 1: Add failing parser tests for detected units and main-row noise**

Add tests that request a structured estimate:

```dart
test('preserves fahrenheit unit on the accepted large reading', () {
  final estimate = OcrService.estimateThermoScanReading([
    '102.2 M\n104.6 °F\n3 7 30 30',
  ]);

  expect(estimate.displayValue, 104.6);
  expect(estimate.detectedUnit, ThermoScanUnit.fahrenheit);
  expect(estimate.readingCelsius, closeTo(40.33, 0.01));
});

test('normalizes common seven-segment OCR characters', () {
  final estimate = OcrService.estimateThermoScanReading(['1O4,6 °F']);

  expect(estimate.displayValue, 104.6);
  expect(estimate.detectedUnit, ThermoScanUnit.fahrenheit);
});
```

- [ ] **Step 2: Run the parser tests and verify RED**

Run:

```bash
flutter test test/services/ocr/ocr_service_test.dart
```

Expected: compile failure because `ThermoScanUnit`,
`estimateThermoScanReading`, `displayValue`, and `detectedUnit` do not exist.

- [ ] **Step 3: Add structured unit and reading types**

Introduce:

```dart
enum ThermoScanUnit { fahrenheit, celsius }

class ThermoScanReadingEstimate {
  const ThermoScanReadingEstimate({
    this.displayValue,
    this.detectedUnit,
    this.readingCelsius,
    this.confidence = ThermoScanOcrConfidence.none,
    this.confidenceScore = 0,
    this.supportingReadings = 0,
  });

  final double? displayValue;
  final ThermoScanUnit? detectedUnit;
  final double? readingCelsius;
  final ThermoScanOcrConfidence confidence;
  final double confidenceScore;
  final int supportingReadings;
}
```

Keep `estimateThermoScanReadingCelsius` as a compatibility wrapper over the new
`estimateThermoScanReading`. Normalize OCR text before matching:

```dart
static String _normalizeSevenSegmentText(String text) => text
    .replaceAll(RegExp(r'(?<=\d)[oO](?=\d)'), '0')
    .replaceAll(RegExp(r'(?<=\d),(?=\d)'), '.');
```

Rank explicit-unit candidates above bare date/time candidates, retain the
candidate's display value/unit, and normalize candidates to Celsius only for
consensus.

- [ ] **Step 4: Run the parser tests and verify GREEN**

Run:

```bash
flutter test test/services/ocr/ocr_service_test.dart
```

Expected: all parser and analyzer tests pass.

- [ ] **Step 5: Commit the structured parser**

```bash
git add lib/services/ocr/ocr_service.dart test/services/ocr/ocr_service_test.dart
git commit -m "feat: preserve thermometer OCR units"
```

### Task 2: Device-Focused Red LCD Preprocessing

**Files:**
- Create: `test/fixtures/ocr/thermoscan_red_lcd.jpeg`
- Modify: `lib/services/ocr/ocr_service.dart`
- Modify: `test/services/ocr/ocr_preprocessing_test.dart`

- [ ] **Step 1: Copy the supplied device photo into the test fixtures**

Run:

```bash
mkdir -p test/fixtures/ocr
cp '/Users/ibrahimradi/Pictures/Photos Library.photoslibrary/resources/derivatives/1/1559F8E9-D808-4712-B484-557BAEEDED97_1_105_c.jpeg' test/fixtures/ocr/thermoscan_red_lcd.jpeg
```

- [ ] **Step 2: Add failing crop and variant tests**

Expose a testable preprocessing profile and assert the generated image is a
wide main-display band, excludes most of the upper memory row, and enlarges the
digits:

```dart
test('device profile isolates and upscales the main seven-segment row', () async {
  final result = await OcrService.prepareThermoScanImageForOcr(
    sourcePath: 'test/fixtures/ocr/thermoscan_red_lcd.jpeg',
    outputPath: outputPath,
    enableQualityChecks: false,
    profile: ThermoScanPreprocessProfile.redLcdMainDisplay,
  );

  final decoded = img.decodeImage(await File(outputPath).readAsBytes())!;
  expect(result.shouldRunOcr, isTrue);
  expect(decoded.width / decoded.height, greaterThan(2.0));
  expect(decoded.width, greaterThanOrEqualTo(640));
});
```

Add a pixel-statistics assertion proving the red-channel variant is not a plain
grayscale copy and preserves dark segment/background separation.

- [ ] **Step 3: Run preprocessing tests and verify RED**

Run:

```bash
flutter test test/services/ocr/ocr_preprocessing_test.dart
```

Expected: compile failure because the red-LCD profile is missing.

- [ ] **Step 4: Implement the main-display crop and variants**

Add:

```dart
enum ThermoScanPreprocessProfile { balanced, redLcdMainDisplay }
```

From the guide crop, derive a recognition crop approximately:

```dart
final mainDisplay = image.copyCrop(
  guideCrop,
  x: (guideCrop.width * 0.04).round(),
  y: (guideCrop.height * 0.30).round(),
  width: (guideCrop.width * 0.92).round(),
  height: (guideCrop.height * 0.50).round(),
);
```

Clamp the rectangle, upscale the result to at least 640 pixels wide, and add
ordered variants:

```dart
enum _ThermoScanPreprocessVariant {
  redChannel,
  invertedHighContrast,
  adaptiveBinary,
  balanced,
}
```

Implement red-channel extraction by writing each pixel's red value into all
three channels. Implement adaptive thresholding from the crop histogram/mean
rather than the fixed `128` cutoff. Keep balanced preprocessing as the final
compatibility fallback.

- [ ] **Step 5: Run preprocessing and service tests**

Run:

```bash
flutter test test/services/ocr/ocr_preprocessing_test.dart test/services/ocr/ocr_service_test.dart
```

Expected: all tests pass.

- [ ] **Step 6: Commit device preprocessing**

```bash
git add test/fixtures/ocr/thermoscan_red_lcd.jpeg lib/services/ocr/ocr_service.dart test/services/ocr/ocr_preprocessing_test.dart
git commit -m "feat: tune OCR for red seven-segment displays"
```

### Task 3: Unit-Aware Capture And Mismatch Resolution

**Files:**
- Modify: `lib/features/audits/ocr_capture/ocr_capture_config.dart`
- Modify: `lib/features/audits/ocr_capture/ocr_capture_controller.dart`
- Modify: `lib/features/audits/ocr_capture/ocr_capture_screen.dart`
- Modify: `lib/features/audits/models/est_guided_capture_state.dart`
- Modify: `test/features/audits/ocr_capture/ocr_capture_controller_test.dart`
- Modify: `test/features/audits/ocr_capture/ocr_capture_screen_test.dart`

- [ ] **Step 1: Add failing mismatch controller tests**

Change the recognizer test seam to return `ThermoScanOcrResult` and add:

```dart
test('mismatched detected unit requires explicit resolution', () async {
  final c = _build(
    config: const OcrCaptureConfig(
      title: 'CVT',
      selectedUnit: ThermoScanUnit.fahrenheit,
    ),
    recognizer: (_, _) async => const ThermoScanOcrResult(
      displayValue: 40.0,
      detectedUnit: ThermoScanUnit.celsius,
      readingCelsius: 40.0,
    ),
  );

  await c.captureOnce();

  expect(c.hasUnitMismatch, isTrue);
  expect(c.pendingValue, isNull);
  expect(c.detectedUnit, ThermoScanUnit.celsius);
});
```

Add a second test where `useDetectedReading()` stages `104.0` Fahrenheit and a
matching-unit test that stages the reading directly.

- [ ] **Step 2: Run controller tests and verify RED**

Run:

```bash
flutter test test/features/audits/ocr_capture/ocr_capture_controller_test.dart
```

Expected: compile failure for the structured recognizer and mismatch API.

- [ ] **Step 3: Implement mismatch state**

Update `OcrCaptureConfig`:

```dart
final ThermoScanUnit selectedUnit;

String get unitSuffix =>
    selectedUnit == ThermoScanUnit.fahrenheit ? '°F' : '°C';
```

Change the recognizer typedef:

```dart
typedef ThermoScanRecognizer = Future<ThermoScanOcrResult> Function(
  String imagePath,
  ThermoScanCropFrame? cropFrame,
);
```

Store pending detected value/unit separately in the controller. Matching or
unknown units stage the selected-unit value. Known mismatches preserve the
photo and expose:

```dart
bool get hasUnitMismatch;
ThermoScanUnit? get detectedUnit;
void useDetectedReading();
void retakeAfterUnitMismatch();
```

`useDetectedReading()` converts from the OCR result's Celsius-normalized value
to the config's selected unit exactly once.

- [ ] **Step 4: Add failing mismatch screen test**

Pump the screen with a mismatch controller and assert:

```dart
expect(find.textContaining('Device shows °C'), findsOneWidget);
expect(find.widgetWithText(OutlinedButton, 'Retake'), findsOneWidget);
expect(find.widgetWithText(OutlinedButton, 'Enter manually'), findsOneWidget);
expect(find.widgetWithText(FilledButton, 'Use detected reading'), findsOneWidget);
```

- [ ] **Step 5: Implement the mismatch warning card**

Render a dedicated mismatch card before the normal review card. Wire the three
actions to controller methods and keep the captured frame pending until the
user chooses retake or confirms a resolved reading.

- [ ] **Step 6: Run capture tests and verify GREEN**

Run:

```bash
flutter test test/features/audits/ocr_capture/ocr_capture_controller_test.dart test/features/audits/ocr_capture/ocr_capture_screen_test.dart
```

Expected: all tests pass.

- [ ] **Step 7: Commit mismatch-aware capture**

```bash
git add lib/features/audits/ocr_capture lib/features/audits/models/est_guided_capture_state.dart test/features/audits/ocr_capture
git commit -m "feat: warn on thermometer unit mismatch"
```

### Task 4: Shared Sector Unit Adapter

**Files:**
- Create: `lib/features/audits/models/temperature_entry_unit.dart`
- Create: `test/features/audits/temperature_entry_unit_test.dart`

- [ ] **Step 1: Write failing conversion tests**

```dart
test('egg storage converts display fahrenheit to canonical celsius', () {
  expect(
    TemperatureEntryUnit.fahrenheit.toCanonical(
      104.0,
      canonicalUnit: TemperatureEntryUnit.celsius,
    ),
    closeTo(40.0, 0.01),
  );
});

test('selector conversion does not duplicate-convert canonical values', () {
  final canonical = TemperatureEntryUnit.celsius.toCanonical(
    40.0,
    canonicalUnit: TemperatureEntryUnit.celsius,
  );
  expect(
    TemperatureEntryUnit.fahrenheit.fromCanonical(
      canonical,
      canonicalUnit: TemperatureEntryUnit.celsius,
    ),
    closeTo(104.0, 0.01),
  );
});
```

- [ ] **Step 2: Run the unit test and verify RED**

Run:

```bash
flutter test test/features/audits/temperature_entry_unit_test.dart
```

Expected: compile failure because `TemperatureEntryUnit` does not exist.

- [ ] **Step 3: Implement the adapter**

```dart
enum TemperatureEntryUnit {
  fahrenheit,
  celsius;

  String get suffix => this == fahrenheit ? '°F' : '°C';

  double convert(double value, TemperatureEntryUnit target) {
    if (this == target) return value;
    return target == fahrenheit
        ? TempConverter.toFahrenheit(value)
        : TempConverter.toCelsius(value);
  }

  double toCanonical(
    double value, {
    required TemperatureEntryUnit canonicalUnit,
  }) => convert(value, canonicalUnit);

  double fromCanonical(
    double value, {
    required TemperatureEntryUnit canonicalUnit,
  }) => canonicalUnit.convert(value, this);
}
```

Add mapping to/from `ThermoScanUnit` for the capture config.

- [ ] **Step 4: Run the adapter tests and commit**

Run:

```bash
flutter test test/features/audits/temperature_entry_unit_test.dart
```

Expected: all tests pass.

Commit:

```bash
git add lib/features/audits/models/temperature_entry_unit.dart test/features/audits/temperature_entry_unit_test.dart
git commit -m "feat: add audit temperature unit adapter"
```

### Task 5: Add Fahrenheit-Default Selectors To All Four Sectors

**Files:**
- Modify: `lib/features/audits/screens/egg_storage_screen.dart`
- Modify: `lib/features/audits/screens/setter_optimizing_screen.dart`
- Modify: `lib/features/audits/screens/hatcher_optimizing_screen.dart`
- Modify: `lib/features/audits/widgets/tabs/cvt_tab.dart`
- Modify: `test/features/audits/egg_storage_screen_test.dart`
- Modify: `test/features/audits/incubation_age_hours_test.dart`
- Modify: `test/features/audits/chick_quality_screen_test.dart`

- [ ] **Step 1: Add failing widget tests for four Fahrenheit defaults**

For each sector, pump the screen, find a stable key such as
`egg-est-unit-selector`, and assert `F` is selected. Switch to `C`, enter or
load one known canonical value, and assert the displayed grid value and suffix
convert while provider data remains in the existing canonical unit.

Example Egg Storage assertion:

```dart
expect(find.byKey(const ValueKey('egg-est-unit-f-selected')), findsOneWidget);
await tester.tap(find.byKey(const ValueKey('egg-est-unit-c')));
await tester.pump();
expect(find.text('°C'), findsWidgets);
```

Add equivalent keys for Setter EST, Chicks CVT, and Hatcher CVT.

- [ ] **Step 2: Run the widget tests and verify RED**

Run:

```bash
flutter test test/features/audits/egg_storage_screen_test.dart test/features/audits/incubation_age_hours_test.dart test/features/audits/chick_quality_screen_test.dart
```

Expected: selector keys are absent.

- [ ] **Step 3: Add a shared compact selector widget**

Create a small private/shared widget using `SegmentedButton` or the repository's
existing compact choice pattern. It receives:

```dart
TemperatureEntryUnit value;
ValueChanged<TemperatureEntryUnit> onChanged;
String keyPrefix;
bool enabled;
```

Place it beside each EST/CVT grid heading. Initialize local state to
`TemperatureEntryUnit.fahrenheit`.

- [ ] **Step 4: Wire Egg Storage canonical Celsius conversion**

Keep `_currentEstReadings()` and provider writes canonical Celsius. Convert
controller text from selected display unit to Celsius when calculating/saving,
and convert canonical Celsius to the selected unit when loading or toggling.
Pass the selected unit into `OcrCaptureConfig`.

- [ ] **Step 5: Wire Setter, Chicks, And Hatcher canonical Fahrenheit conversion**

Keep their current JSON, average, CV, thresholds, and persistence values in
Fahrenheit. Convert controller text to Fahrenheit before calculations/saves and
from Fahrenheit when loading/toggling. Pass each selected unit into
`OcrCaptureConfig`.

- [ ] **Step 6: Run sector widget tests and verify GREEN**

Run:

```bash
flutter test test/features/audits/egg_storage_screen_test.dart test/features/audits/incubation_age_hours_test.dart test/features/audits/chick_quality_screen_test.dart
```

Expected: all tests pass.

- [ ] **Step 7: Commit sector unit selectors**

```bash
git add lib/features/audits/screens/egg_storage_screen.dart lib/features/audits/screens/setter_optimizing_screen.dart lib/features/audits/screens/hatcher_optimizing_screen.dart lib/features/audits/widgets/tabs/cvt_tab.dart test/features/audits/egg_storage_screen_test.dart test/features/audits/incubation_age_hours_test.dart test/features/audits/chick_quality_screen_test.dart
git commit -m "feat: add EST and CVT unit selectors"
```

### Task 6: Documentation And Full Verification

**Files:**
- Modify: `docs/LIVING_SPEC.md`

- [ ] **Step 1: Update implemented behavior**

Document the large-row red-LCD crop, red/inverted/adaptive preprocessing,
structured detected units, mismatch warning, per-sector `F / C` controls
defaulting to Fahrenheit, and unchanged canonical storage units. Update the
Last Updated date to `2026-06-13` and add a dated change-history entry.

- [ ] **Step 2: Format and analyze**

Run:

```bash
dart format lib/services/ocr/ocr_service.dart lib/features/audits/ocr_capture lib/features/audits/models/temperature_entry_unit.dart lib/features/audits/models/est_guided_capture_state.dart lib/features/audits/screens/egg_storage_screen.dart lib/features/audits/screens/setter_optimizing_screen.dart lib/features/audits/screens/hatcher_optimizing_screen.dart lib/features/audits/widgets/tabs/cvt_tab.dart test/services/ocr test/features/audits/ocr_capture test/features/audits/temperature_entry_unit_test.dart test/features/audits/egg_storage_screen_test.dart test/features/audits/incubation_age_hours_test.dart test/features/audits/chick_quality_screen_test.dart
flutter analyze
```

Expected: formatter succeeds and analyzer reports no issues.

- [ ] **Step 3: Run the focused regression suite**

Run:

```bash
flutter test test/services/ocr/ocr_service_test.dart test/services/ocr/ocr_preprocessing_test.dart test/features/audits/ocr_capture/ocr_capture_controller_test.dart test/features/audits/ocr_capture/ocr_capture_screen_test.dart test/features/audits/temperature_entry_unit_test.dart test/features/audits/egg_storage_screen_test.dart test/features/audits/incubation_age_hours_test.dart test/features/audits/chick_quality_screen_test.dart
```

Expected: all tests pass.

- [ ] **Step 4: Verify repository diff**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; only intended implementation, fixture, tests,
plan, and living-spec files are changed.

- [ ] **Step 5: Commit documentation**

```bash
git add docs/LIVING_SPEC.md
git commit -m "docs: document seven-segment temperature OCR"
```

