# ChickMark AI Agent Avatar Design

**Date:** 2026-08-14

**Status:** Approved visual direction; awaiting written-spec review

**Selected concept:** Clean ChickMark Agent (refined from Spark Guide)

## Goal

Give the in-app hatchery assistant a recognizable ChickMark identity without
introducing generic robot imagery or visual language associated with another AI
brand. The avatar must remain legible in small message rows and work as a
reusable identity for the in-app assistant and Telegram agent.

## Approved Visual Direction

The avatar uses the current ChickMark cap-and-glasses chick and its existing
blue check mark. It does not add a star, sparkle, floating badge, circuit icon,
or right-side ornament. The mascot is the identity; the agent's behavior and
copy communicate its intelligence.

The master avatar has:

- a square 1024 × 1024 canvas with a circular safe area;
- the current yellow chick, blue cap, round glasses, smiling beak, wings, and
  blue check;
- the existing ChickMark blue gradient (`#079FE0` through `#193FC2`);
- a clean white separation ring around the logo artwork;
- a 10% safe margin so circular platform masks do not clip the cap, glasses,
  wings, or check;
- no text or wordmark.

Very subtle egg-shaped contour lines may appear in large decorative treatments,
but they are not baked into the core avatar asset because they disappear at
small sizes and add visual noise.

## Asset Set

Create one master asset and derive deterministic exports from it:

- `assets/branding/chickmark-agent-avatar.png` — 1024 × 1024 master PNG;
- 512 × 512 PNG for Telegram or other external profile surfaces;
- 128 × 128 and 64 × 64 PNGs for QA and platform-specific reuse if needed.

Flutter uses the master asset and lets the framework downsample it. The master
asset is added to `pubspec.yaml` explicitly, following the repository's current
branding-asset convention.

## In-App Usage

### Assistant header

Show the avatar at 36–40 logical pixels before the `Assistant` title in the
gradient app bar. Keep the existing clear-conversation action unchanged. The
avatar is decorative because the title already names the destination.

### Empty conversation

Replace the generic `forum_outlined` icon with the avatar at 80–96 logical
pixels. Keep the existing localized heading and explanatory copy below it. This
is the largest in-app treatment and can retain the full chick-and-check mark.

### Assistant messages

Show a 28–32 logical-pixel avatar beside assistant messages only. User messages
do not receive this avatar. The avatar and bubble form one
`Row` using directional alignment so Arabic continues to mirror correctly.
Failed and sending-state labels remain attached to their existing message
column.

### Thinking state

Show the same 28–32 logical-pixel avatar beside the existing `Thinking` label
and spinner. Do not animate the avatar itself. This avoids unnecessary motion
and keeps the status indicator accessible under reduced-motion settings.

## External Usage

Use the 512 × 512 export as the Telegram bot profile image when the team is
ready to update that external account. The Flutter implementation does not
change Telegram automatically; the profile-image update is a separate manual or
bot-management action.

## Reusable Flutter Component

Introduce a small, presentation-only `AssistantAvatar` widget that owns:

- the asset path;
- circular clipping;
- requested size;
- optional semantic labeling;
- a simple fallback to the existing ChickMark logo asset if the dedicated
  avatar cannot be decoded.

The widget has no provider, network, database, or sync dependency. The chat
screen decides placement and size. This keeps the asset treatment reusable
without coupling branding to conversation state.

## Accessibility and Localization

- Decorative header and message avatars are excluded from semantics when the
  adjacent text already identifies the assistant.
- The empty-state avatar uses the localized semantic label `ChickMark logo`.
- No text is embedded in the image, so the asset works unchanged in English and
  Arabic.
- All message layout continues to use `AlignmentDirectional` and directional
  padding.
- The static avatar introduces no flashing or required motion.

## Validation

Add or update widget tests to verify:

- the empty state renders the dedicated agent avatar instead of the generic
  forum icon;
- assistant messages render one avatar while user messages do not;
- the thinking state renders the avatar without changing the existing thinking
  key or spinner behavior;
- Arabic message alignment still mirrors correctly;
- the clear action, retry states, offline notice, composer, and current message
  copy remain unchanged.

Run the narrow chat suite:

```bash
flutter test test/features/chat/
```

Run static analysis on the affected files or the full package if the narrow
analysis command is unavailable:

```bash
flutter analyze
```

## Documentation

The implementation is a meaningful product change. In the same implementation
commit, update `docs/LIVING_SPEC.md` to describe the agent avatar's current
placements and add a new `2026-08-14` entry at the top of
`docs/CHANGELOG.md`. Do not rewrite earlier changelog entries.

## Out of Scope

- renaming the assistant;
- changing assistant personality, prompts, or response behavior;
- changing the ChickMark company logo or launcher icons;
- animated eyes, mouth, sparkle, glow, or status variants;
- automatic Telegram profile administration;
- avatar upload or user-selectable agent skins.
