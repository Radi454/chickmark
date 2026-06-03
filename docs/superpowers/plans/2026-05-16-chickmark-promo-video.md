# ChickMark Promo Video Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce the first vertical ChickMark promo video file from the approved "Tiny Manager + Boss Mode" design.

**Architecture:** Generate all visual frames with a deterministic Python/Pillow renderer, synthesize a short upbeat WAV bed in the same script, then encode frames plus audio into a single video using a Swift AVFoundation helper. Keep generated outputs under `outputs/promo/` and reusable production scripts under `tools/promo_video/`.

**Tech Stack:** Python 3, Pillow, NumPy, Swift, AVFoundation, existing `assets/branding/chickmark-icon.png`.

---

## File Structure

- `tools/promo_video/generate_chickmark_promo.py`: creates 9:16 PNG frames, thumbnail stills, and a WAV audio bed.
- `tools/promo_video/encode_chickmark_promo.swift`: encodes PNG frames and WAV audio into a final video file.
- `outputs/promo/chickmark_tiny_manager_vertical/frames/`: generated frame sequence.
- `outputs/promo/chickmark_tiny_manager_vertical/audio.wav`: generated upbeat audio bed.
- `outputs/promo/chickmark_tiny_manager_vertical/storyboard_contact_sheet.png`: generated visual proof sheet.
- `outputs/promo/chickmark-tiny-manager-vertical.mp4`: final video file.

## Task 1: Create The Frame And Audio Generator

**Files:**
- Create: `tools/promo_video/generate_chickmark_promo.py`

- [ ] **Step 1: Add the generator script**

Create a Python script that renders 1080x1920 frames at 24 FPS for 15 seconds. It should draw the four approved beats: suspicious numbers, tiny manager entrance, Boss Mode dashboard cards, and the final "Meet ChickMark" logo payoff. It must also create a short WAV file with an upbeat beat and simple pop/check/sting cues.

- [ ] **Step 2: Run the generator**

Run:

```bash
python3 tools/promo_video/generate_chickmark_promo.py
```

Expected:

- `outputs/promo/chickmark_tiny_manager_vertical/frames/frame_0000.png` exists.
- `outputs/promo/chickmark_tiny_manager_vertical/frames/frame_0359.png` exists.
- `outputs/promo/chickmark_tiny_manager_vertical/audio.wav` exists.
- `outputs/promo/chickmark_tiny_manager_vertical/storyboard_contact_sheet.png` exists.

## Task 2: Create The Video Encoder

**Files:**
- Create: `tools/promo_video/encode_chickmark_promo.swift`

- [ ] **Step 1: Add the Swift encoder**

Create a Swift script that reads the generated PNG frames and WAV audio, writes a temporary video-only MOV with AVAssetWriter, then merges the video and audio tracks into `outputs/promo/chickmark-tiny-manager-vertical.mp4`.

- [ ] **Step 2: Run the encoder**

Run:

```bash
swift tools/promo_video/encode_chickmark_promo.swift
```

Expected:

- `outputs/promo/chickmark-tiny-manager-vertical.mp4` exists.
- The encoder reports the frame count and final output path.

## Task 3: Verify The Produced Video

**Files:**
- Inspect: `outputs/promo/chickmark-tiny-manager-vertical.mp4`
- Inspect: `outputs/promo/chickmark_tiny_manager_vertical/storyboard_contact_sheet.png`

- [ ] **Step 1: Verify generated file metadata**

Run:

```bash
ls -lh outputs/promo/chickmark-tiny-manager-vertical.mp4 outputs/promo/chickmark_tiny_manager_vertical/storyboard_contact_sheet.png
```

Expected: both files are present and non-empty.

- [ ] **Step 2: Verify video duration and tracks**

Run:

```bash
python3 tools/promo_video/generate_chickmark_promo.py --verify-only
```

Expected: reports that the final video exists and that all expected generated assets are present.

- [ ] **Step 3: Open the storyboard still for visual review**

Use the generated contact sheet as the quick visual proof. If it shows the four beats in order, the video is ready for user review.
