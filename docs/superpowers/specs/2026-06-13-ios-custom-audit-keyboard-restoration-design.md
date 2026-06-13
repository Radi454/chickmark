# iOS Custom Audit Keyboard Restoration Design

## Goal

Restore the existing ChickMark in-app numeric keypad for adaptive audit
numeric fields on native iOS. Ordinary text fields continue to use the native
iOS keyboard.

## Decision

Use the shared adaptive platform policy rather than adding per-screen
overrides. Native iOS and Android audit numeric fields use
`AuditNumericKeyboard`; desktop targets continue to use normal system or
physical input, and the existing web browser policy remains unchanged.

The keypad implementation, numeric validation, focus-preservation fixes, and
stable mounted station behavior remain unchanged.

## Scope

- Update the iOS adaptive-mode widget test to require the custom keypad.
- Route native iOS through the existing custom-keypad policy.
- Update `docs/LIVING_SPEC.md` to describe implemented behavior.

Persistence, audit models, screen-specific fields, and ordinary text input are
outside this change.

## Verification

Run the audit numeric keyboard, keyboard dismissal, session navigation, and
weight-grid widget tests. Verify the stable web preview still opens an audit
numeric field with the custom keypad under its mobile platform policy.

## Risks

The custom keypad depends on the recent focus and station-identity fixes. Those
fixes remain in place, so this restoration changes only which existing input
surface adaptive iOS selects.
