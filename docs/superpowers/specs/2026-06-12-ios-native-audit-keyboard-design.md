# iOS Native Audit Keyboard Design

## Problem

On the iPhone app, tapping an audit numeric entry field focuses the field and
scrolls it into view, but the in-app numeric keypad does not appear. The user
cannot enter the desired audit value.

The current adaptive input policy routes both Android and iOS through the
custom `AuditNumericKeyboard` overlay. The overlay is vulnerable to focus and
layout rebuilds in the embedded visit-session screens.

## Decision

Use the native iOS numeric keyboard for adaptive audit numeric fields.

- Native iOS builds use `TextInputType.numberWithOptions`.
- Android builds continue to use the existing in-app audit keypad.
- Desktop and desktop-web builds continue to use normal system/physical input.
- Mobile web keeps its existing browser platform policy.
- Explicit `customKeyboard` and `systemKeyboard` modes remain available for
  tests and callers that deliberately override adaptive behavior.

## Behavior

Tapping an enabled numeric audit field on iPhone opens the native iOS numeric
keyboard. The field remains governed by the existing numeric formatter:

- digits are accepted;
- decimal input follows `allowDecimal`;
- signed input follows `allowNegative`;
- decimal precision follows `maxDecimalPlaces`;
- invalid edits are rejected without changing the last valid value.

The existing station scroll behavior may move the focused field above the
keyboard. The visit-session Govee card and navigation footer continue to hide
while an editable field has focus on phone layouts.

## Implementation Scope

Change only the default adaptive platform decision in
`audit_numeric_keyboard.dart` so iOS selects system input instead of the custom
keypad. Do not modify persistence, station models, audit field callbacks, or
the Android keypad UI.

Update `docs/LIVING_SPEC.md` to describe native iOS audit numeric input and the
remaining Android custom-keypad behavior.

## Tests

Add or update widget tests proving:

1. Adaptive iOS mode renders a normal editable numeric `TextField` and no
   `AuditNumericKeyboard` overlay.
2. Adaptive Android mode still opens the custom keypad.
3. System numeric input retains decimal, signed, and precision validation.
4. Existing audit numeric keyboard and keyboard-dismiss tests remain green.

## Deployment Verification

Build a signed iOS release, install it over the current
`com.hatchery.hatchaudit` bundle on the connected iPhone, and launch that exact
bundle. Do not uninstall either ChickMark bundle, because uninstalling would
remove that bundle's local app data.

## Risks

- The native iOS number pad may not expose every punctuation key in every
  locale. The configured signed/decimal input type requests the appropriate
  keyboard, and the formatter remains the final validation layer.
- Android retains the custom overlay and is intentionally outside this fix.
- Two ChickMark bundle IDs are installed on the phone; verification must target
  `com.hatchery.hatchaudit`.
