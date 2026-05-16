#!/usr/bin/env python3
"""Generate the ChickMark Tiny Manager promo frames."""

from __future__ import annotations

import argparse
from functools import lru_cache
import math
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[2]
LOGO_PATH = ROOT / "assets" / "branding" / "chickmark-icon.png"
OUT_DIR = ROOT / "outputs" / "promo" / "chickmark_tiny_manager_vertical"
FRAMES_DIR = OUT_DIR / "frames"
CONTACT_SHEET_PATH = OUT_DIR / "storyboard_contact_sheet.png"
FINAL_VIDEO_PATH = ROOT / "outputs" / "promo" / "chickmark-tiny-manager-vertical.mp4"

WIDTH = 1080
HEIGHT = 1920
FPS = 24
DURATION_SECONDS = 15
TOTAL_FRAMES = FPS * DURATION_SECONDS

BLUE = (0, 78, 190)
BLUE_DARK = (4, 42, 105)
BLUE_LIGHT = (225, 239, 255)
YELLOW = (255, 202, 0)
YELLOW_DARK = (246, 169, 0)
ORANGE = (255, 126, 0)
INK = (15, 23, 42)
MUTED = (92, 105, 124)
GREEN = (35, 180, 125)
RED = (239, 68, 68)
WHITE = (255, 255, 255)


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/Library/Fonts/Arial Bold.ttf" if bold else "/Library/Fonts/Arial.ttf",
        "/System/Library/Fonts/Supplemental/Helvetica Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Helvetica.ttf",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size=size)
        except OSError:
            continue
    return ImageFont.load_default()


FONT_HERO = font(86, True)
FONT_TITLE = font(68, True)
FONT_CARD = font(46, True)
FONT_BODY = font(38)
FONT_SMALL = font(30, True)
FONT_TINY = font(24, True)


def clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return max(low, min(high, value))


def ease_out_back(x: float) -> float:
    x = clamp(x)
    c1 = 1.70158
    c3 = c1 + 1
    return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)


def ease_in_out(x: float) -> float:
    x = clamp(x)
    return x * x * (3 - 2 * x)


def ease_out(x: float) -> float:
    x = clamp(x)
    return 1 - pow(1 - x, 3)


def lerp(a: float, b: float, x: float) -> float:
    return a + (b - a) * x


def text_size(draw: ImageDraw.ImageDraw, text: str, text_font: ImageFont.ImageFont) -> tuple[int, int]:
    box = draw.textbbox((0, 0), text, font=text_font)
    return box[2] - box[0], box[3] - box[1]


def draw_center_text(
    draw: ImageDraw.ImageDraw,
    xy: tuple[float, float],
    text: str,
    text_font: ImageFont.ImageFont,
    fill: tuple[int, int, int] = INK,
    spacing: int = 8,
) -> None:
    lines = text.split("\n")
    sizes = [text_size(draw, line, text_font) for line in lines]
    total_h = sum(h for _, h in sizes) + spacing * (len(lines) - 1)
    y = xy[1] - total_h / 2
    for line, (w, h) in zip(lines, sizes):
        draw.text((xy[0] - w / 2, y), line, font=text_font, fill=fill)
        y += h + spacing


def rounded_rect_with_shadow(
    base: Image.Image,
    rect: tuple[int, int, int, int],
    radius: int,
    fill: tuple[int, int, int],
    shadow: tuple[int, int, int, int] = (12, 34, 80, 35),
    outline: tuple[int, int, int] | None = None,
    width: int = 2,
) -> None:
    shadow_layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow_layer)
    sx1, sy1, sx2, sy2 = rect
    sdraw.rounded_rectangle((sx1, sy1 + 16, sx2, sy2 + 16), radius=radius, fill=shadow)
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(18))
    base.alpha_composite(shadow_layer)
    draw = ImageDraw.Draw(base)
    draw.rounded_rectangle(rect, radius=radius, fill=fill, outline=outline, width=width)


def make_card(
    size: tuple[int, int],
    title: str,
    value: str,
    accent: tuple[int, int, int],
    subtitle: str = "",
    chart: bool = False,
) -> Image.Image:
    card = Image.new("RGBA", size, (0, 0, 0, 0))
    rounded_rect_with_shadow(card, (8, 8, size[0] - 8, size[1] - 8), 34, WHITE, outline=(225, 232, 244))
    draw = ImageDraw.Draw(card)
    draw.rounded_rectangle((34, 34, 96, 96), radius=18, fill=accent)
    draw.text((118, 34), title, font=FONT_SMALL, fill=MUTED)
    draw.text((36, 118), value, font=FONT_CARD, fill=INK)
    if subtitle:
        draw.text((38, 184), subtitle, font=FONT_TINY, fill=MUTED)
    if chart:
        points = [(280, 205), (335, 182), (390, 192), (445, 148), (505, 130), (565, 108)]
        draw.line(points, fill=accent, width=8, joint="curve")
        for point in points[-3:]:
            draw.ellipse((point[0] - 7, point[1] - 7, point[0] + 7, point[1] + 7), fill=accent)
    return card


def paste_rotated(base: Image.Image, layer: Image.Image, center: tuple[float, float], angle: float, scale: float = 1.0) -> None:
    if scale != 1.0:
        new_size = (max(1, int(layer.width * scale)), max(1, int(layer.height * scale)))
        layer = layer.resize(new_size, Image.Resampling.LANCZOS)
    rotated = layer.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
    base.alpha_composite(rotated, (int(center[0] - rotated.width / 2), int(center[1] - rotated.height / 2)))


@lru_cache(maxsize=16)
def logo_asset(size: int) -> Image.Image:
    logo = Image.open(LOGO_PATH).convert("RGBA")
    pixels = []
    for r, g, b, a in logo.getdata():
        if r > 246 and g > 246 and b > 246:
            pixels.append((r, g, b, 0))
        else:
            pixels.append((r, g, b, a))
    logo.putdata(pixels)
    logo = logo.resize((size, size), Image.Resampling.LANCZOS)
    return logo


def make_logo_badge(size: int, label: str | None = None) -> Image.Image:
    padding = max(18, size // 14)
    badge = Image.new("RGBA", (size + padding * 2, size + padding * 2 + (52 if label else 0)), (0, 0, 0, 0))
    shadow = Image.new("RGBA", badge.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle(
        (padding // 2, padding // 2 + 18, badge.width - padding // 2, badge.height - padding // 2 + 18),
        radius=max(44, size // 5),
        fill=(6, 33, 88, 26),
    )
    badge.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(20)))
    badge.alpha_composite(logo_asset(size), (padding, padding))
    if label:
        d = ImageDraw.Draw(badge)
        w, h = text_size(d, label, FONT_TINY)
        x = (badge.width - w - 42) // 2
        y = padding + size - 10
        d.rounded_rectangle((x, y, x + w + 42, y + 44), radius=22, fill=BLUE)
        d.text((x + 21, y + 11), label, font=FONT_TINY, fill=WHITE)
    return badge


def make_clipboard_card(label: str, value: str, accent: tuple[int, int, int] = BLUE) -> Image.Image:
    card = Image.new("RGBA", (420, 260), (0, 0, 0, 0))
    rounded_rect_with_shadow(card, (10, 18, 410, 250), 28, WHITE, outline=(229, 234, 244))
    draw = ImageDraw.Draw(card)
    draw.rounded_rectangle((144, 0, 276, 42), radius=18, fill=(227, 232, 241))
    draw.text((42, 70), label, font=FONT_SMALL, fill=MUTED)
    draw.text((42, 122), value, font=FONT_CARD, fill=accent)
    draw.line((42, 202, 360, 202), fill=(226, 232, 240), width=5)
    return card


def draw_checkmark(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], color: tuple[int, int, int], width: int) -> None:
    x1, y1, x2, y2 = box
    points = [
        (x1 + (x2 - x1) * 0.10, y1 + (y2 - y1) * 0.58),
        (x1 + (x2 - x1) * 0.42, y1 + (y2 - y1) * 0.88),
        (x1 + (x2 - x1) * 0.92, y1 + (y2 - y1) * 0.18),
    ]
    draw.line(points, fill=color, width=width, joint="curve")


def make_audit_paper(clean: bool = False, scale: float = 1.0) -> Image.Image:
    w = int(500 * scale)
    h = int(650 * scale)
    paper = Image.new("RGBA", (w + 70, h + 70), (0, 0, 0, 0))
    shadow = Image.new("RGBA", paper.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((38, 42, w + 38, h + 42), radius=int(28 * scale), fill=(6, 33, 88, 34))
    paper.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(int(14 * scale))))

    d = ImageDraw.Draw(paper)
    d.rounded_rectangle((28, 24, w + 28, h + 24), radius=int(24 * scale), fill=WHITE, outline=(220, 228, 240), width=max(2, int(3 * scale)))
    mini = logo_asset(int(88 * scale))
    paper.alpha_composite(mini, (int(50 * scale), int(42 * scale)))
    d.text((int(150 * scale), int(58 * scale)), "ChickMark", font=font(max(12, int(34 * scale)), True), fill=BLUE_DARK)
    d.text((int(150 * scale), int(98 * scale)), "Audit sheet", font=font(max(10, int(23 * scale)), True), fill=MUTED)

    rows = [
        ("BMK target", "ready" if clean else "unclear", GREEN if clean else RED),
        ("Trend", "clean signal" if clean else "missing", BLUE),
        ("Visit summary", "decision ready" if clean else "scattered", YELLOW_DARK),
    ]
    y = int(180 * scale)
    for label, value, color in rows:
        d.rounded_rectangle((int(54 * scale), y, int(450 * scale), y + int(94 * scale)), radius=int(20 * scale), fill=(248, 251, 255), outline=(226, 234, 246), width=max(1, int(2 * scale)))
        d.text((int(78 * scale), y + int(18 * scale)), label, font=font(max(9, int(20 * scale)), True), fill=MUTED)
        d.text((int(78 * scale), y + int(48 * scale)), value, font=font(max(11, int(28 * scale)), True), fill=color)
        y += int(118 * scale)

    chart_y = int(545 * scale)
    d.line((int(80 * scale), chart_y, int(430 * scale), chart_y), fill=(226, 234, 246), width=max(2, int(4 * scale)))
    points = [
        (int(85 * scale), int(575 * scale)),
        (int(150 * scale), int(548 * scale)),
        (int(225 * scale), int(560 * scale)),
        (int(300 * scale), int(520 * scale)),
        (int(385 * scale), int(492 * scale)),
    ]
    d.line(points, fill=GREEN if clean else BLUE, width=max(4, int(7 * scale)), joint="curve")
    if clean:
        d.rounded_rectangle((int(142 * scale), int(386 * scale), int(365 * scale), int(452 * scale)), radius=int(22 * scale), fill=(225, 252, 240), outline=GREEN, width=max(2, int(3 * scale)))
        d.text((int(178 * scale), int(405 * scale)), "READY", font=font(max(13, int(30 * scale)), True), fill=GREEN)
    return paper


def make_check_layer(size: int = 620) -> Image.Image:
    layer = Image.new("RGBA", (size, int(size * 0.78)), (0, 0, 0, 0))
    shadow = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    draw_checkmark(sd, (40, 80, size - 34, int(size * 0.68) + 24), (4, 42, 105, 48), max(28, size // 12))
    layer.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14)))
    d = ImageDraw.Draw(layer)
    draw_checkmark(d, (34, 60, size - 44, int(size * 0.68)), BLUE, max(30, size // 11))
    # Small white gloves keep the motion readable without inventing a new mascot.
    glove_r = max(18, size // 18)
    for gx, gy in [(int(size * 0.26), int(size * 0.51)), (int(size * 0.66), int(size * 0.29))]:
        d.ellipse((gx - glove_r, gy - glove_r, gx + glove_r, gy + glove_r), fill=WHITE, outline=BLUE_LIGHT, width=max(2, size // 85))
    return layer


def make_check_carrying_paper(clean: bool = False, scale: float = 1.0) -> Image.Image:
    canvas = Image.new("RGBA", (int(820 * scale), int(820 * scale)), (0, 0, 0, 0))
    paper = make_audit_paper(clean=clean, scale=0.62 * scale)
    check = make_check_layer(int(560 * scale))
    canvas.alpha_composite(paper.rotate(-5, resample=Image.Resampling.BICUBIC, expand=True), (int(145 * scale), int(20 * scale)))
    canvas.alpha_composite(check, (int(120 * scale), int(330 * scale)))
    d = ImageDraw.Draw(canvas)
    d.line((int(300 * scale), int(420 * scale), int(278 * scale), int(285 * scale)), fill=BLUE, width=max(8, int(14 * scale)))
    d.line((int(545 * scale), int(345 * scale), int(565 * scale), int(278 * scale)), fill=BLUE, width=max(8, int(14 * scale)))
    return canvas


def draw_background(base: Image.Image) -> None:
    draw = ImageDraw.Draw(base)
    for y in range(HEIGHT):
        ratio = y / HEIGHT
        r = int(255 * (1 - ratio) + 242 * ratio)
        g = int(255 * (1 - ratio) + 247 * ratio)
        b = int(255 * (1 - ratio) + 255 * ratio)
        draw.line((0, y, WIDTH, y), fill=(r, g, b))
    draw.ellipse((-250, -180, 460, 500), fill=(242, 247, 255))
    draw.ellipse((710, 1080, 1260, 1700), fill=(255, 248, 216))


def draw_suspicious_numbers(frame: Image.Image, t: float) -> None:
    wobble = math.sin(t * 17) * 8
    cards = [
        (make_clipboard_card("BMK target", "unclear", RED), (322 + wobble, 525), -7 - wobble * 0.18),
        (make_clipboard_card("Trend", "missing", BLUE), (748 - wobble, 700), 6 + wobble * 0.16),
        (make_clipboard_card("Visit summary", "scattered", YELLOW_DARK), (520, 900 + wobble), -2),
    ]
    for card, center, angle in cards:
        paste_rotated(frame, card, center, angle)
    d = ImageDraw.Draw(frame)
    d.text((96, 165), "Hatchery audit status:", font=FONT_SMALL, fill=MUTED)
    d.text((96, 212), "numbers need a manager", font=font(58, True), fill=INK)
    draw_center_text(
        d,
        (WIDTH / 2, 1515),
        "When the hatchery numbers\nstart freelancing...",
        FONT_CARD,
        fill=INK,
    )


def draw_tiny_manager(frame: Image.Image, progress: float, absolute_time: float) -> None:
    d = ImageDraw.Draw(frame)
    draw_suspicious_numbers(frame, absolute_time)
    entry = ease_out_back(progress)
    x = lerp(-260, WIDTH / 2, entry)
    y = lerp(1520, 1030, ease_out(progress)) + math.sin(absolute_time * 14) * 26 * (1 - progress * 0.45)
    angle = math.sin(absolute_time * 9) * 5 - (1 - progress) * 12
    character = make_check_carrying_paper(clean=False, scale=0.82)

    for i in range(4):
        trail_x = x - 90 - i * 55
        trail_y = y + 150 + i * 18
        d.rounded_rectangle((trail_x - 42, trail_y - 8, trail_x + 42, trail_y + 8), radius=8, fill=(0, 78, 190, 28))

    paste_rotated(frame, character, (x, y), angle, 1.0)

    bubble_alpha = int(255 * clamp((progress - 0.22) / 0.28))
    if bubble_alpha:
        bubble = Image.new("RGBA", (620, 200), (0, 0, 0, 0))
        bd = ImageDraw.Draw(bubble)
        bd.rounded_rectangle((18, 18, 602, 152), radius=46, fill=(255, 255, 255, bubble_alpha), outline=(0, 78, 190, bubble_alpha), width=4)
        bd.polygon([(286, 150), (330, 150), (298, 190)], fill=(255, 255, 255, bubble_alpha), outline=(0, 78, 190, bubble_alpha))
        bd.text((84, 58), "Audit paper secured.", font=font(40, True), fill=(*BLUE_DARK, bubble_alpha))
        frame.alpha_composite(bubble, (230, 300))

    stamp_progress = clamp((progress - 0.45) / 0.45)
    for i, pos in enumerate([(275, 610), (770, 785), (540, 975)]):
        p = clamp((stamp_progress * 3) - i)
        if p <= 0:
            continue
        size = int(85 + 35 * ease_out_back(p))
        d.ellipse((pos[0] - size, pos[1] - size, pos[0] + size, pos[1] + size), fill=(225, 239, 255), outline=BLUE, width=8)
        draw_checkmark(d, (pos[0] - size + 28, pos[1] - size + 36, pos[0] + size - 20, pos[1] + size - 24), BLUE, 18)


def draw_dashboard(frame: Image.Image, progress: float, absolute_time: float) -> None:
    d = ImageDraw.Draw(frame)
    d.text((82, 126), "Dashboard clarity", font=FONT_TITLE, fill=BLUE_DARK)
    d.text((86, 208), "BMK signals, ready to act on.", font=FONT_BODY, fill=MUTED)

    if progress < 0.48:
        throw_p = ease_out(clamp(progress / 0.48))
        start = (120, 1440)
        end = (780, 565)
        arc_y = -220 * math.sin(math.pi * throw_p)
        paper = make_audit_paper(clean=True, scale=0.55)
        px = lerp(start[0], end[0], throw_p)
        py = lerp(start[1], end[1], throw_p) + arc_y
        paste_rotated(frame, paper, (px, py), lerp(-18, 11, throw_p) + math.sin(absolute_time * 10) * 3)
        check = make_check_layer(460)
        paste_rotated(frame, check, (235 + 40 * math.sin(absolute_time * 8), 1390), -7 + math.sin(absolute_time * 6) * 2)
        d.rounded_rectangle((326, 1520, 826, 1600), radius=34, fill=WHITE, outline=(219, 229, 244), width=3)
        d.text((365, 1542), "Clean it. Toss it. Decide.", font=FONT_SMALL, fill=BLUE_DARK)

    cards = [
        (make_card((820, 285), "BMK", "On benchmark", GREEN, "Targets readable at a glance"), (540, 470), BLUE),
        (make_card((820, 285), "Trend", "Clean signal", BLUE, "Signals line up cleanly", chart=True), (540, 795), BLUE),
        (make_card((820, 285), "Visit Summary", "Decision ready", YELLOW_DARK, "No mystery spreadsheet chase"), (540, 1120), YELLOW_DARK),
    ]
    for index, (card, final_center, _) in enumerate(cards):
        p = ease_out(clamp((progress - 0.10 * index) / 0.46))
        x = lerp(-500, final_center[0], p)
        y = final_center[1] + math.sin(absolute_time * 5 + index) * 4 * (1 - p)
        paste_rotated(frame, card, (x, y), lerp(-4, 0, p), 1.0)

    chick = make_check_layer(230)
    bob = math.sin(absolute_time * 8) * 8
    paste_rotated(frame, chick, (835, 1488 + bob), -4)
    d.rounded_rectangle((116, 1396, 730, 1554), radius=48, fill=WHITE, outline=(219, 229, 244), width=3)
    d.text((156, 1432), "BMK benchmarks.", font=FONT_SMALL, fill=BLUE_DARK)
    d.text((156, 1475), "Clearer decisions.", font=FONT_SMALL, fill=INK)
    d.text((156, 1518), "Fewer mystery spreadsheets.", font=FONT_TINY, fill=MUTED)

    check_p = ease_out(clamp((progress - 0.55) / 0.35))
    if check_p > 0:
        x2 = int(150 + 780 * check_p)
        d.line((135, 1710, x2, 1710), fill=BLUE_LIGHT, width=20)
        draw_checkmark(d, (725, 1620, 985, 1810), BLUE, int(18 + 20 * check_p))


def draw_logo_payoff(frame: Image.Image, progress: float) -> None:
    d = ImageDraw.Draw(frame)
    logo = Image.open(LOGO_PATH).convert("RGBA")
    logo_scale = 0.52 + 0.20 * ease_out_back(clamp(progress / 0.65))
    logo_size = int(760 * logo_scale)
    logo = logo.resize((logo_size, logo_size), Image.Resampling.LANCZOS)

    sweep = ease_out(clamp(progress / 0.45))
    draw_checkmark(d, (-120, 710, int(1180 * sweep), 1210), BLUE, 80)

    logo_y = int(350 + 24 * math.sin(progress * math.pi))
    frame.alpha_composite(logo, (int(WIDTH / 2 - logo.width / 2), logo_y))

    title_p = ease_out(clamp((progress - 0.35) / 0.42))
    if title_p > 0:
        y = int(1288 + 60 * (1 - title_p))
        d.text((WIDTH / 2 - text_size(d, "Meet ChickMark.", FONT_HERO)[0] / 2, y), "Meet ChickMark.", font=FONT_HERO, fill=INK)
        d.rounded_rectangle((278, y + 132, 802, y + 194), radius=31, fill=BLUE)
        d.text((327, y + 147), "Tiny Manager Mode: ON", font=FONT_TINY, fill=WHITE)


def render_frame(index: int) -> Image.Image:
    seconds = index / FPS
    frame = Image.new("RGBA", (WIDTH, HEIGHT), WHITE)
    draw_background(frame)

    if seconds < 2.0:
        draw_suspicious_numbers(frame, seconds)
    elif seconds < 5.0:
        draw_tiny_manager(frame, (seconds - 2.0) / 3.0, seconds)
    elif seconds < 10.2:
        draw_dashboard(frame, (seconds - 5.0) / 5.2, seconds)
    else:
        draw_logo_payoff(frame, (seconds - 10.2) / 4.8)

    return frame.convert("RGB")


def make_contact_sheet() -> None:
    picks = [
        (12, "Suspicious numbers"),
        (70, "Tiny manager enters"),
        (176, "Dashboard clarity"),
        (276, "Logo sweep"),
        (328, "Meet ChickMark"),
    ]
    thumbs = []
    for frame_index, label in picks:
        img = Image.open(FRAMES_DIR / f"frame_{frame_index:04d}.png").convert("RGB")
        img.thumbnail((270, 480), Image.Resampling.LANCZOS)
        cell = Image.new("RGB", (300, 560), (248, 251, 255))
        cell.paste(img, ((300 - img.width) // 2, 20))
        d = ImageDraw.Draw(cell)
        draw_center_text(d, (150, 520), label, FONT_TINY, fill=INK)
        thumbs.append(cell)
    sheet = Image.new("RGB", (300 * len(thumbs), 560), WHITE)
    for i, thumb in enumerate(thumbs):
        sheet.paste(thumb, (i * 300, 0))
    sheet.save(CONTACT_SHEET_PATH, quality=95)


def verify_only() -> int:
    expected = [
        FRAMES_DIR / "frame_0000.png",
        FRAMES_DIR / f"frame_{TOTAL_FRAMES - 1:04d}.png",
        CONTACT_SHEET_PATH,
        FINAL_VIDEO_PATH,
    ]
    missing = [path for path in expected if not path.exists() or path.stat().st_size == 0]
    frame_count = len(list(FRAMES_DIR.glob("frame_*.png"))) if FRAMES_DIR.exists() else 0
    if frame_count != TOTAL_FRAMES:
        print(f"Expected {TOTAL_FRAMES} frames, found {frame_count}.")
        return 1
    if missing:
        print("Missing or empty generated assets:")
        for path in missing:
            print(f"- {path}")
        return 1
    print("Verified promo assets:")
    for path in expected:
        print(f"- {path} ({path.stat().st_size:,} bytes)")
    return 0


def generate() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    if FRAMES_DIR.exists():
        shutil.rmtree(FRAMES_DIR)
    FRAMES_DIR.mkdir(parents=True)

    if not LOGO_PATH.exists():
        raise FileNotFoundError(f"Logo not found: {LOGO_PATH}")

    for index in range(TOTAL_FRAMES):
        frame = render_frame(index)
        frame.save(FRAMES_DIR / f"frame_{index:04d}.png", optimize=False, compress_level=2)
        if index % 48 == 0:
            print(f"Rendered frame {index:04d}/{TOTAL_FRAMES - 1}")

    make_contact_sheet()
    print(f"Frames: {FRAMES_DIR}")
    print(f"Contact sheet: {CONTACT_SHEET_PATH}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-only", action="store_true", help="Verify generated assets and final video exist.")
    args = parser.parse_args()
    if args.verify_only:
        return verify_only()
    generate()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
