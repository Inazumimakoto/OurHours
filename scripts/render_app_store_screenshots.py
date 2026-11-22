#!/usr/bin/env python3
"""Render OurHours App Store screenshots from simulator PNGs. Requires Pillow."""

import argparse
from bisect import bisect_right
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
SIZE_1206 = (1206, 2622)
INK = "#242947"
SKY = ("#FFE4CF", "#FCE8D8", "#F8E8F2", "#E6EBFF")
SOURCE = Path(__file__).resolve().parents[1] / "Apps/OurHoursiOS/Sources"
ASSETS = SOURCE / "Assets.xcassets"
DEFAULT_TEST_OUT = Path("/tmp/ourhours_screenshot_selftest")
LANCZOS = Image.Resampling.LANCZOS
BICUBIC = Image.Resampling.BICUBIC
SCALE = 2
PREVIEW_GAP = 12
PREVIEW_SIZE = (264, 574)


RAW_NAMES = (
    "raw_home.png",
    "raw_calendar.png",
    "raw_gallery.png",
    "raw_map.png",
    "raw_customizer.png",
    "raw_dayDetail.png",
    "raw_pairing.png",
)
PANEL_NAMES = (
    "01_hero.png",
    "02_home.png",
    "03_calendar.png",
    "04_album.png",
    "05_map.png",
    "06_customizer.png",
    "07_timeline.png",
    "08_pairing.png",
)
PANORAMA_PREVIEW = "preview_panorama_1_2_3.png"
ALL_PREVIEW = "preview_all_8.png"


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
    scale = SCALE
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


def normalized_screen(path):
    with Image.open(path) as source:
        screen = ImageOps.exif_transpose(source).convert("RGBA")
    backing = Image.new("RGBA", screen.size, "#FFF4EA")
    backing.alpha_composite(screen)
    # Keep the simulator status bar and navigation area when trimming extra height.
    return ImageOps.fit(backing.convert("RGB"), SIZE, LANCZOS, centering=(0.5, 0.0))


def tinted_mask(mask, color, opacity=1.0):
    layer = Image.new("RGBA", mask.size, color)
    layer.putalpha(mask.point(lambda value: round(value * opacity)))
    return layer


def diagonal_ramp(size, stops):
    width, height = size
    ramp = Image.new("RGBA", (1024, 1))
    ramp.putdata(color_ramp(stops, ramp.width))
    # Project the top-left to bottom-right gradient onto a one-pixel ramp.
    length_squared = width ** 2 + height ** 2
    return ramp.transform(
        size, Image.Transform.AFFINE,
        (1023 * width / length_squared, 1023 * height / length_squared, 0.5, 0, 0, 0.5),
        BICUBIC,
    )


def organic_track(width, height, radius, seed, amplitude):
    """Sample the SwiftUI OrganicBubbleShape by distance along the rounded perimeter."""
    horizontal = width - 2 * radius
    vertical = height - 2 * radius
    quarter_arc = math.pi * radius / 2
    ends = []
    for length in (horizontal, quarter_arc, vertical, quarter_arc) * 2:
        ends.append((ends[-1] if ends else 0) + length)
    straight = (
        (radius, 0, 1, 0), (width, radius, 0, 1),
        (width - radius, height, -1, 0), (0, height - radius, 0, -1),
    )
    corners = (
        (width - radius, radius), (width - radius, height - radius),
        (radius, height - radius), (radius, radius),
    )

    def point(distance, inset=0):
        distance %= ends[-1]
        segment = bisect_right(ends, distance)
        offset = distance - (ends[segment - 1] if segment else 0)
        if segment % 2:
            x, y = corners[segment // 2]
            angle = (segment // 2 - 1) * math.pi / 2 + offset / radius
            nx, ny = math.cos(angle), math.sin(angle)
            x, y = x + radius * nx, y + radius * ny
        else:
            x, y, dx, dy = straight[segment // 2]
            x, y = x + offset * dx, y + offset * dy
            nx, ny = dy, -dx

        theta = math.tau * distance / ends[-1]
        wave = (1.15 * math.sin(3 * theta + seed)
                + 0.78 * math.cos(5 * theta - 1.3 * seed)
                + 0.45 * math.sin(7 * theta + 0.7 * seed))
        shift = amplitude * wave / 2.38 - inset
        return x + nx * shift, y + ny * shift

    return point, ends


def thin_film_highlights(surface, mask, track, ends, radius):
    highlights = Image.new("RGBA", surface.size)
    draw = ImageDraw.Draw(highlights)

    def tapered_arc(start, end, inset, thickness, alpha):
        outer, inner = [], []
        for step in range(101):
            t = step / 100
            distance = start + (end - start) * t
            half_width = thickness * math.sin(math.pi * t) ** 0.8 / 2
            outer.append(track(distance, inset - half_width))
            inner.append(track(distance, inset + half_width))
        draw.polygon(outer + inner[::-1], fill=(255, 255, 255, alpha))

    # Follow the same upper-left and lower-right curves as the wobbly rim.
    tapered_arc(ends[-1] - 1.29 * radius, radius * 0.76, 18 * SCALE, 12 * SCALE, 237)
    tapered_arc(ends[2] + 0.24 * radius, ends[2] + 1.43 * radius, 17 * SCALE, 8 * SCALE, 128)
    x, y = track(ends[-2] - 10 * SCALE, 24 * SCALE)
    dot_radius = 6 * SCALE
    draw.ellipse((x - dot_radius, y - dot_radius, x + dot_radius, y + dot_radius),
                 fill=(255, 255, 255, 228))
    shine = highlights.filter(ImageFilter.GaussianBlur(4 * SCALE))
    shine.alpha_composite(highlights)
    shine.putalpha(ImageChops.multiply(mask, shine.getchannel("A")))
    surface.alpha_composite(shine)


def bubble_card(canvas, box, lines, seed, max_size, tint, subtitle=None):
    x, y, right, bottom = box
    width, height = (right - x) * SCALE, (bottom - y) * SCALE
    padding = 48 * SCALE
    size = width + 2 * padding, height + 2 * padding
    radius = height * 0.43
    point, ends = organic_track(width, height, radius, seed, height * 0.062)

    def track(distance, inset=0):
        px, py = point(distance, inset)
        return px + padding, py + padding

    contour = [track(ends[-1] * step / 720) for step in range(720)]
    contour.append(contour[0])

    def stroke(width, offset=0):
        mask = Image.new("L", size)
        ImageDraw.Draw(mask).line(
            [(px, py + offset * SCALE) for px, py in contour],
            fill=255, width=width * SCALE, joint="curve",
        )
        return mask

    mask = Image.new("L", size)
    ImageDraw.Draw(mask).polygon(contour, fill=255)
    surface = tinted_mask(stroke(13, 9).filter(ImageFilter.GaussianBlur(4 * SCALE)), INK, 0.09)
    veil = diagonal_ramp(size, (
        (0.0, (255, 255, 255, 170)), (0.51, (255, 255, 255, 46)),
        (1.0, (*ImageColor.getrgb(tint), 77)),
    ))
    veil.putalpha(ImageChops.multiply(mask, veil.getchannel("A")))
    surface.alpha_composite(veil)

    iridescence = diagonal_ramp(size, (
        (0.0, (255, 255, 255, 245)), (0.22, (147, 228, 255, 228)),
        (0.43, (255, 157, 214, 224)), (0.63, (179, 181, 255, 229)),
        (0.82, (255, 225, 155, 238)), (1.0, (255, 255, 255, 245)),
    ))
    iridescent_alpha = iridescence.getchannel("A")
    for stroke_width, opacity, inside in ((43, 0.24, True), (24, 0.46, True),
                                           (17, 0.25, False), (9, 0.95, False)):
        edge = stroke(stroke_width)
        if inside:
            edge = ImageChops.multiply(edge, mask)
        alpha = ImageChops.multiply(edge, iridescent_alpha)
        iridescence.putalpha(alpha.point(lambda value: round(value * opacity)))
        surface.alpha_composite(iridescence)
    thin_film_highlights(surface, mask, track, ends, radius)

    draw = ImageDraw.Draw(surface)
    headline = fitted_font(draw, max(lines, key=len), "Bold", max_size * SCALE, width * 0.81)
    center_y = padding + height * (0.44 if subtitle else 0.50)
    leading = headline.size * 1.22
    for index, copy in enumerate(lines):
        centered_text(draw, (size[0] / 2, center_y + (index - 0.5) * leading), copy, headline)
    if subtitle:
        chip_font = fitted_font(draw, subtitle, "Bold", 43 * SCALE, width * 0.73)
        chip_half_width = draw.textlength(subtitle, font=chip_font) / 2 + 32 * SCALE
        chip_x, chip_y = size[0] / 2, padding + 0.74 * height
        chip = (chip_x - chip_half_width, chip_y - 34 * SCALE,
                chip_x + chip_half_width, chip_y + 34 * SCALE)
        pill_layer = Image.new("RGBA", size)
        ImageDraw.Draw(pill_layer).rounded_rectangle(
            chip, radius=34 * SCALE, fill=(255, 255, 255, 170),
            outline=(255, 255, 255, 205), width=2 * SCALE,
        )
        surface.alpha_composite(pill_layer)
        centered_text(draw, (chip_x, chip_y), subtitle, chip_font)

    canvas.alpha_composite(surface.resize((size[0] // SCALE, size[1] // SCALE), LANCZOS),
                           (x - padding // SCALE, y - padding // SCALE))


def continuous_corner_mask(size, radius):
    """Local G2 corners with straight sides. The quintic has zero endpoint curvature."""
    width, height = size
    control = (0, 0, 0, 0.40, 0.72, 1)
    corner = []
    for step in range(129):
        t = step / 128
        weights = [math.comb(5, i) * t ** i * (1 - t) ** (5 - i) for i in range(6)]
        corner.append(tuple(radius * sum(w * c for w, c in zip(weights, axis))
                            for axis in (control, control[::-1])))
    right, bottom = width - 1, height - 1
    mask = Image.new("L", size)
    ImageDraw.Draw(mask).polygon(
        corner
        + [(right - x, y) for x, y in reversed(corner)]
        + [(right - x, bottom - y) for x, y in corner]
        + [(x, bottom - y) for x, y in reversed(corner)],
        fill=255,
    )
    return mask


def phone(canvas, capture, screen_width, top_center, lean=0):
    """Frame and transform the shadow and device in the same 2× coordinate space."""
    display_width = screen_width * SCALE
    display_height = round(display_width * HEIGHT / WIDTH)
    bezel = round(0.024 * display_width)
    radius = round(0.148 * display_width)
    frame_width = display_width + 2 * bezel
    frame_height = display_height + 2 * bezel
    padding = 144 * SCALE
    size = frame_width + 2 * padding, frame_height + 2 * padding
    piece = Image.new("RGBA", size)
    frame_mask = continuous_corner_mask((frame_width, frame_height), radius + bezel)
    for blur, offset, opacity in ((44, 26, 0.19), (19, 12, 0.17), (6, 4, 0.19)):
        shade = Image.new("L", size)
        shade.paste(frame_mask, (padding, padding + offset * SCALE))
        piece.alpha_composite(tinted_mask(shade.filter(ImageFilter.GaussianBlur(blur * SCALE)),
                                         INK, opacity))

    draw = ImageDraw.Draw(piece)
    for side, y, length in ((-1, 0.20, 0.048), (-1, 0.30, 0.089), (-1, 0.418, 0.089),
                            (1, 0.34, 0.125), (1, 0.62, 0.084)):
        x = padding + (frame_width if side == 1 else 0)
        button_y = padding + round(y * display_width)
        draw.rounded_rectangle(
            (x - 7 * SCALE, button_y, x + 7 * SCALE, button_y + length * display_width),
            radius=5 * SCALE, fill="#7C7A82", outline="#D6D3D9", width=SCALE,
        )

    rim = vertical_ramp(frame_mask.size, (
        (0.0, (239, 235, 239, 255)), (0.028, (164, 159, 168, 255)),
        (0.17, (214, 208, 213, 255)), (0.42, (130, 127, 137, 255)),
        (0.66, (199, 194, 201, 255)), (1.0, (123, 122, 133, 255)),
    ))
    rim.putalpha(frame_mask)
    piece.alpha_composite(rim, (padding, padding))
    edge = 6 * SCALE
    inner_mask = continuous_corner_mask(
        (frame_width - 2 * edge, frame_height - 2 * edge), radius + bezel - edge,
    )
    piece.alpha_composite(tinted_mask(inner_mask, "#24242E"), (padding + edge, padding + edge))
    screen = capture.resize((display_width, display_height), LANCZOS).convert("RGBA")
    screen.putalpha(continuous_corner_mask(screen.size, radius))
    piece.alpha_composite(screen, (padding + bezel, padding + bezel))
    place_phone(canvas, piece, (padding + frame_width / 2, padding), top_center, lean)


def place_phone(canvas, piece, anchor, top_center, lean):
    # Map the visible destination back into the supersampled layer. This keeps
    # the off-canvas part of the device out of the rotated pixel buffer.
    sin, cos = math.sin(math.radians(lean)), math.cos(math.radians(lean))
    ax, ay = anchor
    tx, ty = (coordinate * SCALE for coordinate in top_center)
    corners = [(tx + cos * (x - ax) + sin * (y - ay),
                ty - sin * (x - ax) + cos * (y - ay))
               for x in (0, piece.width) for y in (0, piece.height)]
    left = max(0, math.floor(min(x for x, _ in corners) / SCALE))
    top = max(0, math.floor(min(y for _, y in corners) / SCALE))
    right = min(canvas.width, math.ceil(max(x for x, _ in corners) / SCALE))
    bottom = min(canvas.height, math.ceil(max(y for _, y in corners) / SCALE))
    dx, dy = left * SCALE - tx, top * SCALE - ty
    visible = piece.transform(
        ((right - left) * SCALE, (bottom - top) * SCALE), Image.Transform.AFFINE,
        (cos, -sin, ax + cos * dx - sin * dy, sin, cos, ay + sin * dx + cos * dy),
        BICUBIC,
    )
    canvas.alpha_composite(visible.resize((right - left, bottom - top), LANCZOS),
                           (left, top))


MASCOT_TINTS = (
    ((222, 250, 255), (150, 209, 252), (84, 156, 222)),
    ((255, 232, 245), (255, 184, 212), (219, 115, 163)),
)


@lru_cache(maxsize=1)
def mascot_texture():
    with Image.open(ASSETS / "BubbleMascot.imageset/bubble_mascot.png") as source:
        return source.convert("RGBA")


def round_stroke(draw, points, width, fill):
    draw.line(points, fill=fill, width=width, joint="curve")
    radius = width / 2
    for x, y in (points[0], points[-1]):
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=fill)


def quadratic(start, control, end):
    return [
        tuple((1 - t) ** 2 * a + 2 * t * (1 - t) * b + t ** 2 * c
              for a, b, c in zip(start, control, end))
        for t in (step / 32 for step in range(33))
    ]


def mascot(canvas, center, diameter, pink=False):
    texture = mascot_texture()
    side = round(diameter * texture.width / (texture.getbbox()[2] - texture.getbbox()[0]))
    size = (side * SCALE, side * SCALE)
    unit = size[0] / 128
    light, tint, deep = MASCOT_TINTS[pink]
    colors = color_ramp(((0.0, (*light, 43)), (0.52, (*tint, 163)), (1.0, (*deep, 126))), 256)
    # Affine-map a radial ramp to the app's top-leading light source.
    extent = size[0] * 0.84
    radial = Image.radial_gradient("L").transform(
        size, Image.Transform.AFFINE,
        (127 / extent, 0, 128 - 11.5 * unit * 127 / extent,
         0, 127 / extent, 128 - 11.5 * unit * 127 / extent),
        BICUBIC,
    )
    channels = [radial.point(list(channel)) for channel in zip(*colors)]
    disc = Image.new("L", size)
    ImageDraw.Draw(disc).ellipse((11.5 * unit, 11.5 * unit, 116.5 * unit, 116.5 * unit), fill=255)
    channels[3] = ImageChops.multiply(channels[3], disc)
    avatar = Image.merge("RGBA", channels)
    avatar.alpha_composite(texture.resize(size, LANCZOS))

    face = Image.new("RGBA", size)
    blush_mask = Image.new("L", size)
    blush = ImageDraw.Draw(blush_mask)
    for x in (37, 91):
        blush.ellipse(((x - 11) * unit, 65 * unit, (x + 11) * unit, 78 * unit), fill=135)
    face.alpha_composite(tinted_mask(blush_mask.filter(ImageFilter.GaussianBlur(3.1 * unit)),
                                     "#EE75A6"))
    draw = ImageDraw.Draw(face)

    def stroke(points, weight):
        round_stroke(draw, [(x * unit, y * unit) for x, y in points], round(weight * unit), INK)

    for index, x in enumerate((46, 81)):
        if pink:
            direction = 1 if index == 0 else -1
            point = (x + 5 * direction, 60)
            stroke(quadratic((x - 6 * direction, 54.5), (x - direction, 56), point)
                   + quadratic(point, (x - direction, 64), (x - 6 * direction, 65.5)), 3.1)
        else:
            stroke(quadratic((x - 6, 61), (x, 51), (x + 6, 61)), 3.1)
    stroke(quadratic((55, 70), (63, 81), (72, 70)), 3.1)
    avatar.alpha_composite(face)
    avatar = avatar.rotate(-8 if pink else 9, BICUBIC).resize((side, side), LANCZOS)
    canvas.alpha_composite(avatar, (center[0] - side // 2, center[1] - side // 2))


def panorama(home, calendar):
    canvas = sky(3 * WIDTH, SKY)
    bubbles(canvas, (
        (82, 100, 156, 25), (286, 89, 52, 114), (498, 150, 93, 30),
        (967, 88, 132, 59), (1178, 163, 60, 142), (1456, 152, 109, 16),
        (1764, 305, 202, 41), (2000, 137, 58, 110), (2258, 233, 109, 76),
        (2640, 396, 312, 216), (2493, 146, 74, 54), (2830, 191, 122, 5),
        (3075, 365, 196, 167), (3249, 140, 72, 42), (3520, 154, 128, 19),
        (3790, 96, 226, 81), (3935, 320, 112, 162),
        (21, 557, 170, 156), (1280, 630, 121, 23), (1439, 526, 209, 98),
        (125, 1021, 206, 95), (297, 1186, 78, 26), (494, 992, 56, 152),
        (660, 1256, 204, 23), (864, 1111, 91, 84), (1089, 1226, 155, 73),
        (1320, 1010, 254, 127), (1528, 790, 73, 199), (1482, 1425, 130, 45),
        (2482, 711, 136, 167), (2780, 830, 100, 138), (2594, 1074, 174, 17),
        (2335, 523, 58, 201), (2697, 1237, 74, 163),
        (77, 1368, 138, 71), (412, 1471, 113, 69), (835, 1510, 136, 35),
        (1169, 1605, 118, 214), (54, 2266, 104, 55), (450, 2441, 145, 152),
        (1258, 2365, 169, 134), (1332, 1814, 145, 20), (1580, 2143, 202, 58),
        (1389, 2082, 66, 25), (1456, 2432, 91, 151), (1734, 2535, 263, 143),
        (120, 2681, 231, 61), (337, 2586, 78, 31), (668, 2730, 151, 94),
        (1004, 2713, 55, 145), (1320, 2722, 308, 82), (1548, 2777, 78, 62),
        (1972, 2814, 155, 78), (3700, 1935, 196, 148), (3834, 1700, 77, 48),
        (3882, 2280, 278, 106), (3610, 2441, 106, 45), (3424, 2579, 172, 151),
        (3788, 2637, 143, 161), (3955, 2845, 302, 131), (3270, 2822, 122, 10),
    ), opacity=0.79)
    bubble_card(canvas, (100, 236, 1220, 941), ("2人の時間を", "自動で記録"),
                seed=1.8, max_size=150, tint="#FFCEE8")
    # Keep the calendar's last row above the foreground phone's titanium edge.
    phone(canvas, calendar, 1060, (3727, 665), lean=-27)
    phone(canvas, home, 1060, (1762, 1005), lean=26)
    mascot(canvas, (405, 1910), 780)
    mascot(canvas, (956, 2190), 720, pink=True)
    bubbles(canvas, (
        (97, 1589, 73, 120), (265, 1518, 49, 185), (748, 1612, 87, 105),
        (1230, 1825, 60, 35), (615, 2395, 66, 70), (752, 2588, 52, 136),
        (1194, 2561, 114, 186), (22, 2449, 137, 57), (530, 2817, 50, 117),
        (2640, 654, 155, 30),
    ), opacity=0.88)
    return [canvas.crop((i * WIDTH, 0, (i + 1) * WIDTH, HEIGHT)).convert("RGB") for i in range(3)]


def standalone_panel(
    screen,
    lines,
    subtitle=None,
    seed=0.6,
    tint="#FFD6EC",
    palette=("#FFE1CA", "#FBEBDE", "#F8E6F1"),
    flip_bubbles=False,
    phone_width=980,
    phone_top_y=895,
):
    canvas = sky(WIDTH, palette)
    placements = (
        (66, 80, 135, 25), (252, 107, 83, 131), (495, 68, 55, 19),
        (821, 94, 158, 55), (1127, 109, 77, 33), (1278, 233, 180, 151),
        (20, 473, 140, 196), (1296, 572, 93, 128), (71, 752, 116, 31),
        (189, 812, 63, 116), (407, 823, 47, 70), (884, 839, 69, 42),
        (1131, 829, 152, 133), (1298, 845, 131, 17), (42, 1050, 184, 162),
        (1252, 1170, 83, 69), (24, 1450, 112, 43), (1308, 1546, 200, 101),
        (66, 1760, 75, 89), (1282, 1875, 62, 82), (42, 2133, 151, 32),
        (1316, 2200, 145, 149), (25, 2459, 95, 51), (1296, 2565, 101, 95),
        (45, 2812, 221, 119), (1307, 2771, 71, 13),
    )
    if flip_bubbles:
        placements = [(WIDTH - x, y, diameter, phase) for x, y, diameter, phase in placements]
    bubbles(canvas, placements, opacity=0.83)
    bubble_card(
        canvas,
        (96, 220, 1224, 754),
        lines,
        seed=seed,
        max_size=108,
        tint=tint,
        subtitle=subtitle,
    )
    phone(canvas, screen, phone_width, (660, phone_top_y))
    return canvas.convert("RGB")


def preview(panels, gap=0):
    width, height = PREVIEW_SIZE
    strip = Image.new("RGB", (len(panels) * width + (len(panels) + 1) * gap,
                              height + 2 * gap), "#F7F7FA")
    for index, panel in enumerate(panels):
        strip.paste(panel.resize(PREVIEW_SIZE, LANCZOS), (gap + index * (width + gap), gap))
    return strip


def render(raw_dir, out_dir, also_1206_dir=None, preview_dir=None):
    missing = [name for name in RAW_NAMES if not (raw_dir / name).is_file()]
    if missing:
        raise FileNotFoundError(f"Missing simulator PNGs in {raw_dir}: {', '.join(missing)}")
    home, calendar, gallery, map_screen, customizer, day_detail, pairing = (
        normalized_screen(raw_dir / name) for name in RAW_NAMES
    )

    panels = panorama(home, calendar)
    panels.extend((
        standalone_panel(
            gallery,
            lines=("旅行アルバムと", "写真・動画を共有"),
            subtitle="予定と自動でまとまる",
            seed=1.1,
            tint="#FFD6EC",
            palette=("#FFE5D2", "#FCEAE2", "#F7E6F4"),
            flip_bubbles=False,
            phone_width=980,
            phone_top_y=895,
        ),
        standalone_panel(
            map_screen,
            lines=("行った場所が", "思い出マップに"),
            subtitle="写真と場所タグで振り返る",
            seed=2.4,
            tint="#CBE9FF",
            palette=("#EAF4FF", "#F4ECF9", "#FFEADB"),
            flip_bubbles=True,
            phone_width=960,
            phone_top_y=885,
        ),
        standalone_panel(
            customizer,
            lines=("シャボン玉を", "じぶん好みにきせかえ"),
            subtitle="時間や季節イベントで解放",
            seed=4.2,
            tint="#E4D3FF",
            palette=("#F8E4F3", "#ECE8FF", "#FFE8DA"),
            flip_bubbles=False,
            phone_width=980,
            phone_top_y=895,
        ),
        standalone_panel(
            day_detail,
            lines=("1分単位で編集", "写真もメモも1日に"),
            subtitle=None,
            seed=0.6,
            tint="#FFD6EC",
            palette=("#FFE1CA", "#FBEBDE", "#F8E6F1"),
            flip_bubbles=True,
            phone_width=1010,
            phone_top_y=884,
        ),
        standalone_panel(
            pairing,
            lines=("QRコードで", "かんたんペア設定"),
            subtitle="暗号化してiCloudで自動同期",
            seed=3.6,
            tint="#D3DCFF",
            palette=("#FCEADB", "#F7E4EE", "#DDE6FF"),
            flip_bubbles=False,
            phone_width=1060,
            phone_top_y=940,
        ),
    ))

    out_dir.mkdir(parents=True, exist_ok=True)
    for name, panel in zip(PANEL_NAMES, panels):
        panel.save(out_dir / name)

    if also_1206_dir is not None:
        also_1206_dir.mkdir(parents=True, exist_ok=True)
        for name, panel in zip(PANEL_NAMES, panels):
            resized = panel.resize(SIZE_1206, LANCZOS).convert("RGB")
            resized.save(also_1206_dir / name)

    effective_preview_dir = preview_dir or out_dir
    effective_preview_dir.mkdir(parents=True, exist_ok=True)
    preview(panels[:3]).save(effective_preview_dir / PANORAMA_PREVIEW)
    preview(panels, gap=PREVIEW_GAP).save(effective_preview_dir / ALL_PREVIEW)


def mock_screens(raw_dir):
    titles = ("", "カレンダー", "アルバム", "思い出マップ", "シャボン玉きせかえ", "11月15日（日）", "ペア設定")
    backgrounds = ("#FCE8DC", "#C3CFF8", "#F9E9F2", "#DDECFB", "#ECE3FF", "#C3CDF5", "#CED7FA")
    rng = random.Random(42)
    for index, (name, title, background) in enumerate(zip(RAW_NAMES, titles, backgrounds)):
        base = Image.new("RGBA", SIZE, background)
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
            centered_text(draw, (660, 750), "16:42:18", font("Bold", 195))
            draw.rounded_rectangle((350, 925, 970, 1055), radius=64, fill="#FFFAFD")
            centered_text(draw, (660, 990), "はるといっしょにいるよ", font("Bold", 48))
            centered_text(draw, (660, 1123), "付き合って 259日目", font("Medium", 48))
            mascot(base, (509, 1795), 417)
            mascot(base, (792, 1874), 405, pink=True)
            captions = ()
        elif index == 1:
            centered_text(draw, (660, 444), "2026年11月", font("Bold", 86))
            draw.rounded_rectangle((390, 543, 930, 646), radius=50, fill="#F3EEFD")
            centered_text(draw, (660, 594), "今月 75時間30分 · 14日", font("Bold", 46))
            for day, weekday in enumerate("日月火水木金土"):
                centered_text(draw, (133 + day * 175, 763), weekday, font("Medium", 46))
            for first, last in ((7, 9), (18, 19)):
                x = 133 + first % 7 * 175
                y = 910 + first // 7 * 179
                draw.rounded_rectangle((x - 59, y - 59, x + (last - first) * 175 + 59,
                                        y + 59), radius=59, fill="#F5C9DF")
            for day in range(30):
                x, y = 133 + day % 7 * 175, 910 + day // 7 * 179
                if day in (1, 4, 12, 13, 16):
                    draw.ellipse((x - 58, y - 58, x + 58, y + 58), fill="#F5C9DF")
                centered_text(draw, (x, y), str(day + 1), font("Bold", 53))
            captions = ()
        elif index == 2:
            draw.rounded_rectangle((72, 420, 636, 760), radius=48, fill="#FFFAFD")
            centered_text(draw, (354, 590), "箱根温泉旅行", font("Bold", 44))
            draw.rounded_rectangle((684, 420, 1248, 760), radius=48, fill="#FFFAFD")
            centered_text(draw, (966, 590), "代官山ステイ", font("Bold", 44))
            for row in range(3):
                for col in range(3):
                    gx, gy = 72 + col * 400, 860 + row * 400
                    draw.rounded_rectangle((gx, gy, gx + 372, gy + 372), radius=36, fill="#FFE2EC")
            captions = ()
        elif index == 3:
            draw.rounded_rectangle((72, 380, 1248, 2500), radius=56, fill="#DDEFE2")
            draw.rounded_rectangle((120, 1880, 1200, 2400), radius=52, fill="#FFFAFD")
            centered_text(draw, (660, 2140), "横浜みなとみらい", font("Bold", 52))
            captions = ()
        elif index == 4:
            mascot(base, (660, 820), 420)
            for row in range(3):
                for col in range(3):
                    gx, gy = 72 + col * 400, 1260 + row * 390
                    draw.rounded_rectangle((gx, gy, gx + 372, gy + 350), radius=40, fill="#FFFAFD")
            captions = ()
        elif index == 5:
            centered_text(draw, (660, 432), "8時間30分", font("Bold", 105))
            draw.rounded_rectangle((90, 572, 1230, 760), radius=54, fill="#FFFAFC")
            centered_text(draw, (660, 665), "ランチしてから夕方の映画を観た！", font("Medium", 46))
            for index_in_grid, hour in enumerate(range(9, 19)):
                y = 922 + index_in_grid * 154
                draw.text((92, y - 27), f"{hour}:00", font=font("Medium", 38), fill=INK)
                draw.line((260, y, 1210, y), fill="#DED3E7", width=3)
            draw.rounded_rectangle((325, 1080, 1150, 1545), radius=64, fill="#F6CBE1")
            draw.rounded_rectangle((325, 1845, 1150, 2100), radius=64, fill="#E2DDF9")
            centered_text(draw, (738, 1306), "4時間", font("Bold", 65))
            centered_text(draw, (738, 1968), "4時間30分", font("Bold", 65))
            captions = ()
        else:
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
            captions = ((1470, "相手のOurHoursで読み取る"), (1700, "招待URLをコピー"))

        for y, caption in captions:
            draw.rounded_rectangle((93, y, 1227, y + 176), radius=58, fill="#FFFAFD")
            centered_text(draw, (660, y + 88), caption, font("Bold", 49))
        base.convert("RGB").save(raw_dir / name)


def validate_outputs(out_dir, expected_size, check_previews=True, preview_dir=None):
    for name in PANEL_NAMES:
        path = out_dir / name
        assert path.is_file(), f"Missing {path}"
        with Image.open(path) as image:
            image.load()
            assert image.format == "PNG" and image.mode == "RGB" and image.size == expected_size, (path, image.size)
            assert "transparency" not in image.info, path
    if check_previews:
        eff_preview_dir = preview_dir or out_dir
        for name, count, gap in ((PANORAMA_PREVIEW, 3, 0), (ALL_PREVIEW, len(PANEL_NAMES), PREVIEW_GAP)):
            path = eff_preview_dir / name
            assert path.is_file(), f"Missing {path}"
            with Image.open(path) as image:
                image.load()
                assert image.format == "PNG" and image.mode == "RGB", path
                assert image.size == (count * PREVIEW_SIZE[0] + (count + 1) * gap,
                                      PREVIEW_SIZE[1] + 2 * gap), path


def self_test(out_dir):
    with TemporaryDirectory(prefix="ourhours-raw-") as raw_dir:
        raw_dir = Path(raw_dir)
        out_1206 = out_dir / "1206x2622"
        mock_screens(raw_dir)
        render(raw_dir, out_dir, also_1206_dir=out_1206)
    validate_outputs(out_dir, SIZE, check_previews=True)
    validate_outputs(out_1206, SIZE_1206, check_previews=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw-dir", type=Path, help="directory containing the simulator PNGs")
    parser.add_argument("--out-dir", type=Path, help="directory for 1320x2868 promotional screenshots")
    parser.add_argument("--also-1206-dir", type=Path, help="optional directory for 1206x2622 screenshots")
    parser.add_argument("--preview-dir", type=Path, help="optional separate directory for preview strips")
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
            render(args.raw_dir, out_dir, also_1206_dir=args.also_1206_dir, preview_dir=args.preview_dir)
            validate_outputs(out_dir, SIZE, check_previews=True, preview_dir=args.preview_dir)
            if args.also_1206_dir is not None:
                validate_outputs(args.also_1206_dir, SIZE_1206, check_previews=False)
    except OSError as error:
        parser.exit(1, f"{error}\n")
    print(f"Wrote {len(PANEL_NAMES)} screenshots to {out_dir}")


if __name__ == "__main__":
    main()
