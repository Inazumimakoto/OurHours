#!/usr/bin/env python3
"""Render OurHours App Store screenshots from simulator PNGs. Requires Pillow."""

import argparse
from dataclasses import dataclass
from functools import lru_cache
import math
from pathlib import Path
import random
from tempfile import TemporaryDirectory

try:
    from PIL import Image, ImageChops, ImageColor, ImageDraw, ImageFilter, ImageFont, ImageOps
except ImportError as error:
    raise SystemExit("Pillow is required. Install it with python3 -m pip install Pillow.") from error


WIDTH, HEIGHT = 1320, 2868
SIZE = (WIDTH, HEIGHT)
INK = "#242947"
SKY = ("#FFE4CF", "#FCE8D8", "#F8E8F2", "#E6EBFF")
SOURCE = Path(__file__).resolve().parents[1] / "Apps/OurHoursiOS/Sources"
ASSETS = SOURCE / "Assets.xcassets"
DEFAULT_TEST_OUT = Path("/tmp/ourhours_screenshot_selftest")
LANCZOS = Image.Resampling.LANCZOS
PREVIEW_GAP = 12
PREVIEW_SIZE = (264, 574)


@dataclass(frozen=True)
class Slide:
    raw: str
    output: str
    title: str
    subtitle: str


SLIDES = (
    Slide("raw_home.png", "01_home.png", "ふたりでいた時間を", "近くにいるだけで自動計測"),
    Slide("raw_calendar.png", "02_calendar.png", "自動で記録、", "月間合計・記念日を一覧表示"),
    Slide("raw_dayDetail.png", "03_timeline.png", "カレンダーで管理。", "1分単位で編集＆ひとことメモ"),
    Slide("raw_pairing.png", "04_pairing.png", "QRコードでかんたん連携", "1回読み取るだけで設定完了"),
    Slide("raw_settings.png", "05_privacy.png", "地図は非表示・完全暗号化", "位置座標は見せず、iCloudで同期"),
)


def color_ramp(stops, length):
    """Sample RGB or RGBA stops in normalized coordinates."""
    pixels = []
    segment = 0
    for index in range(length):
        position = index / (length - 1)
        while position > stops[segment + 1][0]:
            segment += 1
        start, left = stops[segment]
        end, right = stops[segment + 1]
        fraction = (position - start) / (end - start)
        pixels.append(tuple(round(a + (b - a) * fraction) for a, b in zip(left, right)))
    return pixels


def vertical_ramp(size, stops):
    column = Image.new("RGBA", (1, size[1]))
    column.putdata(color_ramp(stops, size[1]))
    return column.resize(size, Image.Resampling.NEAREST)


def glow(canvas, center, size, color, opacity):
    falloff = Image.radial_gradient("L").point(
        [round(opacity * (1 - index / 255) ** 2) for index in range(256)]
    )
    mask = falloff.resize(size, Image.Resampling.BICUBIC)
    light = Image.new("RGBA", size, color)
    light.putalpha(mask)
    canvas.alpha_composite(light, (center[0] - size[0] // 2, center[1] - size[1] // 2))


def sky(width, palette):
    row = Image.new("RGB", (width, 1))
    row.putdata(color_ramp(
        tuple((index / (len(palette) - 1), ImageColor.getrgb(color))
              for index, color in enumerate(palette)),
        width,
    ))
    canvas = row.resize((width, HEIGHT), Image.Resampling.NEAREST).convert("RGBA")
    for x, y, w, h, color, opacity in (
        (0.18, 360, 0.70, 1680, "#FFF7DB", 184),
        (0.65, 620, 0.66, 1620, "#FFFFFF", 160),
        (0.04, 1880, 0.56, 3060, "#FFCFAE", 148),
        (0.45, 2350, 0.85, 2450, "#FFF6D9", 166),
        (0.81, 1650, 0.68, 2820, "#F4D1F2", 146),
        (0.99, 1050, 0.44, 2020, "#D1DCFF", 142),
        (0.97, 2820, 0.57, 1740, "#D6DBFF", 143),
    ):
        glow(canvas, (round(width * x), y), (round(width * w), h), color, opacity)
    return canvas


def rounded_mask(size, radius):
    width, height = size
    mask = Image.new("L", (2 * width, 2 * height))
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, 2 * width - 1, 2 * height - 1), radius=2 * radius, fill=255
    )
    return mask.resize(size, LANCZOS)


def rounded_layer(canvas, box, radius, fill):
    x, y, right, bottom = box
    size = (right - x, bottom - y)
    layer = fill if isinstance(fill, Image.Image) else Image.new("RGBA", size, fill)
    mask = rounded_mask(size, radius)
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
    canvas.alpha_composite(layer, (x, y))


def shadow(canvas, box, radius, blur, offset, color):
    x, y, right, bottom = box
    padding = blur * 3
    face = rounded_mask((right - x, bottom - y), radius)
    mask = Image.new("L", (face.width + 2 * padding, face.height + 2 * padding))
    mask.paste(face, (padding, padding))
    shade = Image.new("RGBA", mask.size, color)
    shade.putalpha(mask.filter(ImageFilter.GaussianBlur(blur)).point(
        [round(value * color[3] / 255) for value in range(256)]
    ))
    canvas.alpha_composite(shade, (x - padding, y - padding + offset))


def glass(canvas, box, radius):
    x, y, right, bottom = box
    width, height = right - x, bottom - y
    shadow(canvas, box, radius, 38, 15, (158, 123, 169, 42))
    surface = canvas.crop(box).resize((width // 2, height // 2), Image.Resampling.BOX)
    surface = surface.filter(ImageFilter.GaussianBlur(10)).resize((width, height), LANCZOS)
    surface.alpha_composite(vertical_ramp((width, height), (
        (0.0, (255, 255, 255, 186)),
        (0.18, (255, 255, 255, 106)),
        (0.72, (255, 253, 255, 85)),
        (1.0, (248, 239, 255, 124)),
    )))
    edge = ImageChops.subtract(
        rounded_mask((width, height), radius),
        ImageOps.expand(rounded_mask((width - 8, height - 8), radius - 4), border=4),
    )
    border = Image.new("RGBA", (width, height), "white")
    border.putalpha(edge.point(lambda value: round(value * 0.8)))
    surface.alpha_composite(border)
    rounded_layer(canvas, box, radius, surface)


RIM_COLORS = (
    "#AC9DEE", "#EBA5D5", "#FFBBAA", "#FBE7A7",
    "#A1E1E2", "#AAC7FB", "#AC9DEE",
)
RIM_RAMP = color_ramp(
    tuple((index / 6, ImageColor.getrgb(color)) for index, color in enumerate(RIM_COLORS)),
    720,
)


@lru_cache(maxsize=1)
def particle():
    with Image.open(ASSETS / "BubbleParticle.imageset/bubble_particle.png") as source:
        return source.convert("RGBA")


def reflection(draw, center, radius, start, end, thickness, opacity):
    """Draw a tapered arc of light on the curved film."""
    outer, inner = [], []
    for index in range(41):
        t = index / 40
        angle = math.radians(start + (end - start) * t)
        half_width = thickness * math.sin(math.pi * t) ** 0.75 / 2
        dx, dy = math.cos(angle), math.sin(angle)
        outer.append((center + dx * (radius + half_width), center + dy * (radius + half_width)))
        inner.append((center + dx * (radius - half_width), center + dy * (radius - half_width)))
    draw.polygon(outer + inner[::-1], fill=(255, 255, 255, opacity))


def bubble_sprite(diameter, phase):
    """Combine the app's particle with a supersampled interference rim and specular arcs."""
    scale = 2
    padding = max(8, round(diameter * 0.12))
    size = diameter + 2 * padding
    side = size * scale
    center = side / 2
    radius = diameter * scale / 2
    bubble = Image.new("RGBA", (side, side))

    shade_mask = Image.new("L", bubble.size)
    drop = radius * 0.12
    ImageDraw.Draw(shade_mask).ellipse((
        center - radius, center - radius + drop,
        center + radius, center + radius + drop,
    ), fill=51)
    clear_center = Image.new("L", bubble.size)
    inner = radius * 0.92
    ImageDraw.Draw(clear_center).ellipse((
        center - inner, center - inner, center + inner, center + inner,
    ), fill=53)
    softness = ImageFilter.GaussianBlur(max(2, radius * 0.074))
    shade = Image.new("RGBA", bubble.size, "#8A6DA6")
    shade.putalpha(ImageChops.subtract(shade_mask.filter(softness), clear_center.filter(softness)))
    bubble.alpha_composite(shade)

    # The asset's painted rim sits at about 80% of its square width.
    texture = particle().rotate(-phase, resample=Image.Resampling.BICUBIC)
    texture_side = round(diameter * scale / 0.80)
    texture = texture.resize((texture_side, texture_side), LANCZOS)
    texture.putalpha(texture.getchannel("A").point(lambda value: round(value * 0.78)))
    inset = (side - texture_side) // 2
    bubble.alpha_composite(texture, (inset, inset))

    film = Image.new("RGBA", bubble.size)
    pixels = film.load()
    radial_alpha = [
        round(104 * math.exp(-((index / 1000 - 0.965) / 0.032) ** 2)
              + 95 * math.exp(-((index / 1000 - 0.994) / 0.009) ** 2))
        for index in range(1021)
    ]
    phase_index = round(phase * len(RIM_RAMP) / 360)
    extent = radius * 1.02
    for y in range(int(center - extent), math.ceil(center + extent)):
        dy = (y + 0.5 - center) / radius
        for x in range(int(center - extent), math.ceil(center + extent)):
            dx = (x + 0.5 - center) / radius
            distance_squared = dx * dx + dy * dy
            if 0.86 ** 2 <= distance_squared <= 1.02 ** 2:
                angle = math.atan2(dy, dx) / math.tau
                color = RIM_RAMP[(round(angle * len(RIM_RAMP)) + phase_index) % len(RIM_RAMP)]
                alpha = radial_alpha[round(math.sqrt(distance_squared) * 1000)]
                pixels[x, y] = (*color, alpha)
    bubble.alpha_composite(film)

    highlights = Image.new("RGBA", bubble.size)
    draw = ImageDraw.Draw(highlights)
    reflection(draw, center, radius * 0.87, 207, 271, radius * 0.091, 242)
    reflection(draw, center, radius * 0.95, 219, 250, radius * 0.026, 220)
    reflection(draw, center, radius * 0.85, 42, 91, radius * 0.060, 142)
    reflection(draw, center, radius * 0.98, 19, 125, radius * 0.023, 166)
    bubble.alpha_composite(highlights.filter(ImageFilter.GaussianBlur(max(0.7, radius * 0.022))))
    bubble.alpha_composite(highlights)
    return bubble.resize((size, size), LANCZOS)


def bubbles(canvas, placements, opacity=1.0):
    for x, y, diameter, phase in placements:
        bubble = bubble_sprite(diameter, phase)
        if opacity < 1:
            bubble.putalpha(bubble.getchannel("A").point(lambda value: round(value * opacity)))
        canvas.alpha_composite(bubble, (x - bubble.width // 2, y - bubble.height // 2))


@lru_cache(maxsize=64)
def font(weight, size):
    return ImageFont.truetype(str(SOURCE / "Fonts" / f"ZenMaruGothic-{weight}.ttf"), size)


def fitted_font(draw, copy, weight, max_size, max_width):
    for size in range(max_size, 0, -1):
        face = font(weight, size)
        left, _, right, _ = draw.textbbox((0, 0), copy, font=face)
        if right - left <= max_width:
            return face
    raise ValueError(f"Text does not fit: {copy!r}")


def centered_text(draw, center, copy, face, fill=INK):
    left, top, right, bottom = draw.textbbox((0, 0), copy, font=face)
    x, y = center
    draw.text((round(x - (left + right) / 2), round(y - (top + bottom) / 2)),
              copy, font=face, fill=fill)


def banner_copy(canvas, center, slide):
    draw = ImageDraw.Draw(canvas)
    title = fitted_font(draw, slide.title, "Bold", 112, WIDTH - 2 * 137)
    subtitle = fitted_font(draw, slide.subtitle, "Medium", 49, WIDTH - 2 * 175)
    left, _, right, _ = draw.textbbox((0, 0), slide.subtitle, font=subtitle)
    half_width = math.ceil((right - left) / 2) + 52
    pill = (center - half_width, 386, center + half_width, 487)
    rounded_layer(canvas, pill, 51, (255, 255, 255, 203))
    rounded_layer(canvas, (pill[0] + 3, 389, pill[2] - 3, 484), 48, (248, 241, 250, 138))
    centered_text(draw, (center, 288), slide.title, title)
    centered_text(draw, (center, 436), slide.subtitle, subtitle)


def normalized_screen(path):
    with Image.open(path) as source:
        screen = ImageOps.exif_transpose(source).convert("RGBA")
    backing = Image.new("RGBA", screen.size, "#FFF4EA")
    backing.alpha_composite(screen)
    # Keep the simulator status bar and navigation area when trimming extra height.
    return ImageOps.fit(backing.convert("RGB"), SIZE, LANCZOS, centering=(0.5, 0.0))


def phone(canvas, center, capture):
    screen_height = 1902
    screen_width = round(screen_height * WIDTH / HEIGHT)
    bezel = 15
    x = center - screen_width // 2 - bezel
    y = 758
    width, height = screen_width + 2 * bezel, screen_height + 2 * bezel
    box = (x, y, x + width, y + height)
    shadow(canvas, box, 69, 41, 29, (54, 42, 74, 93))
    shadow(canvas, box, 69, 13, 12, (43, 36, 54, 62))

    # Side controls, titanium edge, dark bezel, then the screen at its native aspect.
    for button_x, button_y, button_width, button_height in (
        (x - 5, y + 214, 10, 47),
        (x - 6, y + 300, 11, 102),
        (x - 6, y + 427, 11, 102),
        (x + width - 5, y + 366, 11, 137),
        (x + width - 4, y + 629, 9, 100),
    ):
        rounded_layer(canvas, (button_x, button_y, button_x + button_width,
                               button_y + button_height), 4, "#4E4D5C")
    rim = vertical_ramp((width, height), (
        (0.0, (158, 156, 170, 255)),
        (0.12, (96, 95, 111, 255)),
        (0.52, (129, 126, 141, 255)),
        (0.85, (62, 60, 75, 255)),
        (1.0, (138, 135, 153, 255)),
    ))
    rounded_layer(canvas, box, 69, rim)
    rounded_layer(canvas, (x + 4, y + 4, x + width - 4, y + height - 4), 65, "#1F222E")
    screen = capture.resize((screen_width, screen_height), LANCZOS).convert("RGBA")
    rounded_layer(canvas, (x + bezel, y + bezel, x + bezel + screen_width,
                           y + bezel + screen_height), 54, screen)


def panorama(screens):
    canvas = sky(3 * WIDTH, SKY)
    bubbles(canvas, (
        (335, 74, 66, 25), (819, 141, 213, 59), (1086, 56, 51, 142),
        (1498, 115, 81, 16), (1854, 112, 175, 41), (2450, 62, 92, 216),
        (2792, 170, 155, 167), (3274, 96, 70, 42), (3634, 113, 174, 19),
        (62, 1092, 290, 90), (1213, 1048, 167, 168), (1360, 1518, 152, 102),
        (1430, 2218, 145, 20), (2573, 1554, 240, 127), (2702, 2195, 170, 148),
        (3896, 1382, 280, 154), (87, 2415, 195, 24), (3720, 2478, 148, 106),
    ), opacity=0.59)
    glass(canvas, (84, 150, 3 * WIDTH - 84, 560), 166)
    glass(canvas, (94, 720, 3 * WIDTH - 94, 2740), 154)
    bubbles(canvas, (
        (109, 586, 166, 28), (66, 722, 100, 15), (185, 774, 66, 109),
        (273, 674, 45, 200), (941, 645, 86, 128), (1050, 603, 41, 34),
        (1298, 681, 136, 120), (1431, 611, 62, 3), (1712, 668, 45, 65),
        (2262, 642, 72, 74), (2536, 665, 93, 157), (2678, 609, 121, 25),
        (2765, 730, 57, 108), (3514, 675, 51, 55), (3662, 759, 75, 94),
        (3781, 685, 114, 145), (3873, 573, 172, 28),
        (1166, 1866, 70, 214), (1425, 1336, 103, 88),
        (2525, 1933, 91, 83), (2709, 1983, 81, 133), (2668, 944, 120, 31),
        (178, 2747, 112, 125), (1143, 2768, 91, 30), (1320, 2652, 376, 82),
        (1539, 2796, 64, 62), (2254, 2807, 66, 70), (2750, 2704, 118, 20),
        (2811, 2806, 52, 161), (3677, 2797, 99, 138), (3961, 2854, 462, 131),
    ))
    for index, (slide, screen) in enumerate(zip(SLIDES[:3], screens)):
        center = index * WIDTH + WIDTH // 2
        banner_copy(canvas, center, slide)
        phone(canvas, center, screen)
    return [
        canvas.crop((index * WIDTH, 0, (index + 1) * WIDTH, HEIGHT)).convert("RGB")
        for index in range(3)
    ]


def standalone(slide, screen, palette, mirror=False):
    canvas = sky(WIDTH, palette)
    background = (
        (282, 84, 84, 131), (846, 136, 227, 55), (1146, 69, 76, 33),
        (109, 1171, 330, 162), (1197, 1558, 252, 101), (108, 2403, 202, 68),
    )
    foreground = (
        (102, 576, 163, 31), (65, 717, 96, 145), (177, 758, 55, 21),
        (258, 658, 43, 71), (899, 635, 66, 110), (1035, 697, 85, 72),
        (1149, 753, 78, 131), (1213, 637, 120, 163), (1289, 527, 155, 26),
        (1155, 1118, 87, 95), (138, 1918, 93, 32), (1204, 2168, 110, 129),
        (78, 2610, 123, 42), (168, 2755, 191, 89), (330, 2802, 63, 20),
        (1023, 2770, 80, 77), (1301, 2838, 382, 119),
    )
    if mirror:
        background = [(WIDTH - x, y, diameter, phase) for x, y, diameter, phase in background]
        foreground = [(WIDTH - x, y, diameter, phase) for x, y, diameter, phase in foreground]
    bubbles(canvas, background, opacity=0.60)
    glass(canvas, (84, 150, WIDTH - 84, 560), 166)
    glass(canvas, (94, 720, WIDTH - 94, 2740), 154)
    bubbles(canvas, foreground)
    banner_copy(canvas, WIDTH // 2, slide)
    phone(canvas, WIDTH // 2, screen)
    return canvas.convert("RGB")


def preview(panels):
    width, height = PREVIEW_SIZE
    strip = Image.new("RGB", (len(panels) * (width + PREVIEW_GAP) + PREVIEW_GAP,
                              height + 2 * PREVIEW_GAP), "#F7F7FA")
    for index, panel in enumerate(panels):
        left = PREVIEW_GAP + index * (width + PREVIEW_GAP)
        strip.paste(panel.resize(PREVIEW_SIZE, LANCZOS), (left, PREVIEW_GAP))
    return strip


def render(raw_dir, out_dir):
    missing = [slide.raw for slide in SLIDES if not (raw_dir / slide.raw).is_file()]
    if missing:
        raise FileNotFoundError(f"Missing simulator PNGs in {raw_dir}: {', '.join(missing)}")
    screens = [normalized_screen(raw_dir / slide.raw) for slide in SLIDES]
    panels = panorama(screens[:3])
    panels.append(standalone(SLIDES[3], screens[3], ("#FFE2CB", "#FBEBDE", "#F8E7F2")))
    panels.append(standalone(SLIDES[4], screens[4], ("#FCE8DC", "#F8E8F2", "#E6EBFF"), mirror=True))

    out_dir.mkdir(parents=True, exist_ok=True)
    for slide, panel in zip(SLIDES, panels):
        panel.save(out_dir / slide.output)
    preview(panels[:3]).save(out_dir / "preview_panorama_1_2_3.png")
    preview(panels).save(out_dir / "preview_all_5.png")


def mock_screens(raw_dir):
    titles = ("", "カレンダー", "11月21日（土）", "ペア設定", "設定")
    rng = random.Random(42)
    for index, (slide, title) in enumerate(zip(SLIDES, titles)):
        base = Image.new("RGBA", SIZE, ("#FCE8DC", "#F9EAF0", "#F7EDF8",
                                        "#FFEBDD", "#F8EEF7")[index])
        glow(base, (960, 1770), (2140, 2250), "#FFFFFF", 200)
        draw = ImageDraw.Draw(base)
        draw.text((105, 67), "9:41", font=font("Bold", 43), fill=INK)
        draw.rounded_rectangle((477, 39, 842, 142), radius=52, fill="#15141B")
        for bar in range(4):
            x = 1048 + bar * 15
            draw.rounded_rectangle((x, 110 - 7 * (bar + 1), x + 10, 111),
                                   radius=2, fill=INK)
        draw.rounded_rectangle((1135, 80, 1212, 111), radius=9, outline=INK, width=4)
        draw.rounded_rectangle((1143, 86, 1204, 105), radius=5, fill=INK)
        draw.rounded_rectangle((477, 2821, 843, 2838), radius=9, fill=INK)
        centered_text(draw, (660, 236), title, font("Bold", 64))

        if index == 0:
            with Image.open(ASSETS / "BubbleMascot.imageset/bubble_mascot.png") as mascot:
                base.alpha_composite(mascot.convert("RGBA").resize((920, 920), LANCZOS),
                                     (200, 559))
            centered_text(draw, (660, 947), "いま一緒", font("Bold", 104))
            centered_text(draw, (660, 1098), "付き合って 365日目", font("Medium", 49))
            captions = ((1600, "今月 8日 · 27時間40分"), (1830, "累計 382時間15分"))
        elif index == 1:
            centered_text(draw, (660, 444), "2026年11月", font("Bold", 86))
            for day, weekday in enumerate("日月火水木金土"):
                centered_text(draw, (160 + day * 167, 660), weekday, font("Medium", 46))
            for day in range(30):
                x, y = 160 + day % 7 * 167, 817 + day // 7 * 165
                if day in (1, 4, 7, 12, 13, 16, 20, 21, 27):
                    draw.ellipse((x - 58, y - 58, x + 58, y + 58), fill="#F5C9DF")
                centered_text(draw, (x, y), str(day + 1), font("Bold", 53))
            captions = ((1780, "今月 27時間40分 · 8日"), (2010, "ふたりの記念日"))
        elif index == 2:
            centered_text(draw, (660, 432), "3時間25分", font("Bold", 105))
            draw.rounded_rectangle((90, 572, 1230, 760), radius=54, fill="#FFFAFC")
            centered_text(draw, (660, 665), "久しぶりに一緒にお散歩", font("Medium", 46))
            for index_in_grid, hour in enumerate(range(9, 19)):
                y = 922 + index_in_grid * 154
                draw.text((92, y - 27), f"{hour}:00", font=font("Medium", 38), fill=INK)
                draw.line((260, y, 1210, y), fill="#DED3E7", width=3)
            draw.rounded_rectangle((325, 1080, 1150, 1545), radius=64, fill="#F6CBE1")
            draw.rounded_rectangle((325, 1845, 1150, 2100), radius=64, fill="#E2DDF9")
            centered_text(draw, (738, 1306), "2時間10分", font("Bold", 65))
            centered_text(draw, (738, 1968), "1時間15分", font("Bold", 65))
            captions = ()
        elif index == 3:
            centered_text(draw, (660, 484), "相手を招待する", font("Bold", 83))
            draw.rounded_rectangle((279, 650, 1041, 1412), radius=67, fill="white")
            for row in range(29):
                for column in range(29):
                    if rng.random() < 0.46:
                        x, y = 370 + 20 * column, 741 + 20 * row
                        draw.rectangle((x, y, x + 19, y + 19), fill=INK)
            for x, y in ((370, 741), (810, 741), (370, 1181)):
                draw.rectangle((x, y, x + 139, y + 139), fill=INK)
                draw.rectangle((x + 20, y + 20, x + 119, y + 119), fill="white")
                draw.rectangle((x + 40, y + 40, x + 99, y + 99), fill=INK)
            captions = ((1610, "相手のOurHoursで読み取る"), (1940, "招待リンクを共有"))
        else:
            captions = ((452, "ふたりのプロフィール"), (744, "自動記録"),
                        (1036, "位置情報で精度を上げる"), (1328, "ふたりで同期"),
                        (1620, "カレンダーの印"), (1912, "はじめかたを見る"))

        for y, caption in captions:
            draw.rounded_rectangle((93, y, 1227, y + 176), radius=58, fill="#FFFAFD")
            centered_text(draw, (660, y + 88), caption, font("Bold", 49))
        base.convert("RGB").save(raw_dir / slide.raw)


def self_test(out_dir):
    with TemporaryDirectory(prefix="ourhours-raw-") as raw_dir:
        raw_dir = Path(raw_dir)
        mock_screens(raw_dir)
        render(raw_dir, out_dir)
    for slide in SLIDES:
        path = out_dir / slide.output
        assert path.is_file(), f"Missing {path}"
        with Image.open(path) as image:
            image.load()
            assert image.format == "PNG" and image.mode == "RGB" and image.size == SIZE, path
            assert "transparency" not in image.info, path
    for name, count in (("preview_panorama_1_2_3.png", 3), ("preview_all_5.png", 5)):
        path = out_dir / name
        assert path.is_file(), f"Missing {path}"
        with Image.open(path) as image:
            image.load()
            assert image.format == "PNG" and image.mode == "RGB", path
            assert image.size == (count * PREVIEW_SIZE[0] + (count + 1) * PREVIEW_GAP,
                                  PREVIEW_SIZE[1] + 2 * PREVIEW_GAP), path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw-dir", type=Path, help="directory containing the five simulator PNGs")
    parser.add_argument("--out-dir", type=Path, help="directory for promotional screenshots and previews")
    parser.add_argument("--self-test", action="store_true", help="render and validate synthetic captures")
    args = parser.parse_args()
    if args.self_test:
        if args.raw_dir is not None:
            parser.error("--self-test generates its own inputs. Omit --raw-dir.")
        out_dir = args.out_dir or DEFAULT_TEST_OUT
    else:
        if args.raw_dir is None or args.out_dir is None:
            parser.error("--raw-dir and --out-dir are required for simulator captures.")
        out_dir = args.out_dir

    try:
        if args.self_test:
            self_test(out_dir)
        else:
            render(args.raw_dir, out_dir)
    except OSError as error:
        parser.exit(1, f"{error}\n")
    print(f"Wrote five screenshots and two previews to {out_dir}")


if __name__ == "__main__":
    main()
