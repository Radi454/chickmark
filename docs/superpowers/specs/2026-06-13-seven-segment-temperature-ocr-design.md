# Seven-Segment Temperature OCR Design

## Goal

Improve ChickMark's guided thermometer scanner so it can reliably read the
large central temperature from the red-backlit seven-segment device used for:

- Egg Storage EST.
- Setter EST.
- Chicks CVT.
- Hatcher CVT.

The scanner must ignore the smaller memory value and date/time digits visible
elsewhere on the device screen.

## Current Context

All four measurement sectors already use the shared `OcrService` and reusable
`OcrCaptureScreen`. The service crops the visible guide frame, creates balanced,
high-contrast, and binary variants, sends them to Google ML Kit, and parses
plausible Celsius or Fahrenheit values.

The current pipeline is still general text OCR. It does not deliberately isolate
the large seven-segment row, and its grayscale variants can preserve the small
memory/date digits strongly enough for ML Kit to choose the wrong row or return
no usable text.

Current stored units differ by sector:

- Egg Storage EST is stored and calculated in Celsius.
- Setter EST, Chicks CVT, and Hatcher CVT are stored and calculated in
  Fahrenheit.

Those persistence conventions and existing thresholds must remain unchanged.

## Decisions

- Add device-tuned preprocessing before introducing a trained model.
- Read only the large central temperature row and its nearby `F` or `C` unit.
- Add an `F / C` selector to each EST/CVT measurement sector.
- Default every selector to Fahrenheit when the sector is opened.
- Keep the selected unit local to the sector UI; no database migration is
  required.
- Convert values only at the UI/persistence boundary so existing stored data,
  averages, CV calculations, dashboard queries, and benchmark thresholds keep
  their current canonical units.
- If OCR detects a unit different from the selected sector unit, do not silently
  convert and accept it. Show a mismatch warning with actions to retake, enter
  manually, or explicitly use the detected reading.
- Keep manual entry and the native camera fallback available.

## OCR Pipeline

### Display Isolation

Keep the existing visible scan guide, but derive a second, tighter region from
the guide-frame crop for recognition. The recognition region targets the
central/lower main digit band where the large reading appears and excludes most
of the top memory row and bottom date row.

The full guide-frame crop remains available for quality checks and evidence
photos. Only OCR preprocessing uses the tighter recognition region.

### Device-Tuned Variants

Generate a small ordered set of variants from the main-reading region:

1. Red-channel or red-dominant luminance extraction to separate black LCD
   segments from the illuminated red background.
2. Contrast-normalized grayscale.
3. Inverted high-contrast grayscale.
4. Adaptive or histogram-derived binary thresholding rather than only the
   current fixed threshold.

Upscale the tight crop before recognition so thin seven-segment strokes and the
decimal point occupy enough pixels for ML Kit.

The existing balanced whole-frame variant remains a final compatibility
fallback for other thermometer appearances.

### Candidate Selection

Return structured temperature candidates rather than losing unit information
immediately.

Each candidate contains:

- Numeric display value.
- Detected unit, when present.
- Celsius-normalized value for consensus comparison.
- Source variant.
- Confidence contribution.

Candidate parsing should:

- Prefer `DDD.D`, `DD.D`, and missed-decimal equivalents from the isolated main
  row.
- Accept common seven-segment OCR confusions only when they produce a plausible
  temperature, such as `O` to `0` or separator noise around the decimal.
- Ignore small date/time and memory tokens by relying on the tight crop and
  ranking the expected main-reading shape.
- Preserve the detected `F` or `C` marker for unit validation.
- Require stronger consensus for a recovered decimal when no unit is detected.

Auto-scan should remain lightweight: run the best device-tuned primary variant
on each timer tick and let later frames provide consensus. A manual single
capture may fan out through all variants before falling back to manual entry.

## Unit Selector And Data Flow

Introduce a shared temperature-entry unit value used by EST/CVT sector widgets
and `OcrCaptureConfig`.

Each sector shows a compact segmented `F / C` control near its grid heading and
starts on `F`.

Changing the selector:

- Converts all currently displayed readings to the newly selected unit.
- Updates grid suffixes, average labels, target labels, and manual-entry
  suffixes.
- Does not alter the underlying physical readings or duplicate-convert saved
  values.

Saving follows the sector's existing canonical storage:

- Egg Storage converts selected/displayed Fahrenheit values to Celsius before
  writing its existing EST fields.
- Setter EST, Chicks CVT, and Hatcher CVT convert selected/displayed Celsius
  values to Fahrenheit before writing their existing fields.

Loading reverses that boundary conversion for the current selector. Because the
selector defaults to Fahrenheit, existing Egg Storage Celsius readings display
as Fahrenheit when the sector first opens.

## Unit Mismatch Flow

The OCR result must expose both the reading and detected device unit.

When the detected unit matches the selected sector unit, the existing review
and confirm flow continues normally.

When both units are known and differ, show a clear warning such as:

> Device shows °C, but this sector is set to °F.

The warning offers:

- `Retake`.
- `Enter manually`.
- `Use detected reading`.

`Use detected reading` converts the detected reading into the selected display
unit, stages it for review, and still requires the normal confirmation before
saving. OCR never silently accepts a mismatched unit.

When no unit is detected, the scanner may stage a high-confidence numeric
reading using the selected sector unit, but recovered-decimal or low-confidence
results must stay in review rather than auto-confirming.

## Architecture

Keep the shared capture architecture and extend its boundaries:

- `OcrService` owns crop generation, device-specific variants, candidate
  parsing, consensus, and detected-unit metadata.
- `ThermoScanOcrResult` carries the detected display value/unit in addition to
  its Celsius-normalized value and confidence.
- `OcrCaptureConfig` declares the selected display unit and canonical storage
  conversion behavior without embedding station-specific persistence.
- `OcrCaptureController` owns mismatch state and explicit mismatch resolution.
- `OcrCaptureScreen` renders mismatch warnings and unit-aware manual/review
  labels.
- Egg Storage, Setter, Chicks, and Hatcher widgets own their local `F / C`
  selector and canonical-unit conversion when loading or applying results.

No panel-table, audit-model, repository, sync, or migration changes are needed.

## Error Handling

- A failed device-tuned variant falls through to the next variant.
- If all OCR variants fail, keep the existing retry and manual-entry choices.
- If the crop fails quality checks, retain the existing move closer, move back,
  and reduce glare guidance.
- A mismatch is not an OCR failure; preserve the captured frame while the user
  chooses how to proceed.
- Temporary preprocessing files continue to be deleted after recognition or
  after deferred timeout cleanup.

## Testing

Use test-first implementation.

Add focused tests for:

- The supplied device-style fixture is cropped to the main display row rather
  than the memory/date rows.
- Red-channel, inverted, and adaptive-threshold variants preserve large
  seven-segment strokes.
- Parser candidates prefer the large `104.6°F`-style reading and ignore smaller
  numeric rows.
- Common seven-segment decimal and character confusions are recovered only
  inside plausible temperature ranges.
- Detected units are preserved in OCR results.
- Matching units proceed to normal review.
- Mismatched units produce warning state and are not silently accepted.
- Explicit `Use detected reading` converts once and stages the correct selected
  unit.
- Each of the four sectors defaults to Fahrenheit and can switch between
  Fahrenheit and Celsius without changing its canonical stored values.
- Existing EST/CVT averages, CV percentages, thresholds, photos, persistence,
  and capture navigation remain green.

The provided photo may be copied into a test-fixture directory in the repository
for deterministic preprocessing tests. Tests should not depend on the external
Photos Library path.

## Documentation

After implementation, update `docs/LIVING_SPEC.md` to describe:

- Main-row seven-segment OCR behavior.
- Device-tuned preprocessing variants.
- Per-sector `F / C` selection with Fahrenheit default.
- Unit-mismatch warning and explicit resolution.
- Unchanged canonical storage units.

## Risks And Assumptions

- The device family uses a similar large-row screen layout across hatchery
  measurements. The compatibility fallback protects other thermometer layouts.
- ML Kit may still miss individual frames because of glare, motion, or LCD
  refresh artifacts; repeated auto-scan frames and manual capture remain
  necessary.
- The selected unit is intentionally local and defaults to Fahrenheit on each
  sector open. Persisting a user preference is outside this task.
- This work targets temperature display recognition only. It does not introduce
  general OCR for unrelated audit fields.

