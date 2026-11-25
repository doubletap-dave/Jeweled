#!/usr/bin/env python3
"""
Generate high-res 4x-supersampled vector/glow PNGs for the 13 assets that were
blocked by the image-generation quota, matching the exact faceted gold-rimmed
aesthetic of the AI-generated gems (deep night-navy shadows, #e6ba66 gold rim,
faceted crown, luminous inner table, upper-left star specular).
"""

import math
import os
import random
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, "assets_src")

GOLD_RIM = (224, 186, 114, 255)
GOLD_LIGHT = (250, 224, 165, 255)
NAVY_SHADOW = (14, 20, 44, 255)


def lerp(a, b, t):
    return a + (b - a) * t


def lerp_col(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return (
        int(round(lerp(c1[0], c2[0], t))),
        int(round(lerp(c1[1], c2[1], t))),
        int(round(lerp(c1[2], c2[2], t))),
        255,
    )


def draw_star_flare(img, cx, cy, r_major, r_minor, color=(255, 252, 240, 255), glow_r=14):
    """Draw a crisp 4-point specular star highlight with soft halo."""
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([cx - glow_r, cy - glow_r, cx + glow_r, cy + glow_r], fill=(color[0], color[1], color[2], 190))
    glow = glow.filter(ImageFilter.GaussianBlur(glow_r * 0.65))
    img.alpha_composite(glow)

    d = ImageDraw.Draw(img)
    pts = [
        (cx, cy - r_major),
        (cx + r_minor, cy - r_minor),
        (cx + r_major, cy),
        (cx + r_minor, cy + r_minor),
        (cx, cy + r_major),
        (cx - r_minor, cy + r_minor),
        (cx - r_major, cy),
        (cx - r_minor, cy - r_minor),
    ]
    d.polygon(pts, fill=color)


def polygon_scale(pts, cx, cy, sx, sy=None):
    if sy is None:
        sy = sx
    return [(cx + (x - cx) * sx, cy + (y - cy) * sy) for x, y in pts]


def render_faceted_gem(shape_pts, base_col, bright_col, dark_col, spec_pos, extra_fn=None):
    """Render a crisp 512x512 faceted gemstone with gold rim and night-navy shadow facets."""
    S = 512
    cx, cy = S / 2.0, S / 2.0
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Outer dark navy bevel rim
    outer = polygon_scale(shape_pts, cx, cy, 1.00)
    rim = polygon_scale(shape_pts, cx, cy, 0.96)
    girdle = polygon_scale(shape_pts, cx, cy, 0.91)
    table = polygon_scale(shape_pts, cx, cy, 0.56)

    d.polygon(outer, fill=(12, 18, 40, 255))
    d.polygon(rim, fill=GOLD_RIM)
    d.polygon(girdle, fill=dark_col)

    # Light direction: upper-left (-0.707, -0.707)
    lx, ly = -0.707, -0.707
    n = len(shape_pts)
    for i in range(n):
        j = (i + 1) % n
        p1, p2 = girdle[i], girdle[j]
        t1, t2 = table[i], table[j]
        # Facet normal approximated by outward midpoint direction
        mx = (p1[0] + p2[0]) * 0.5 - cx
        my = (p1[1] + p2[1]) * 0.5 - cy
        mag = math.hypot(mx, my) or 1.0
        dot = (mx / mag) * lx + (my / mag) * ly  # -1..+1
        # Split quad into two crisp triangular facets for true gem sparkle
        if dot > 0.15:
            c_a = lerp_col(base_col, bright_col, 0.35 + 0.55 * dot)
            c_b = lerp_col(base_col, bright_col, 0.15 + 0.45 * dot)
        elif dot < -0.25:
            c_a = lerp_col(dark_col, NAVY_SHADOW, min(0.85, -dot * 0.85))
            c_b = lerp_col(dark_col, base_col, 0.18)
        else:
            c_a = lerp_col(dark_col, base_col, 0.55 + dot)
            c_b = lerp_col(dark_col, base_col, 0.35 + dot * 0.5)
        d.polygon([p1, p2, t2], fill=c_a)
        d.polygon([p1, t2, t1], fill=c_b)

    # Inner luminous table with radial inner glow (composited, preserving full opacity)
    table_mid = lerp_col(base_col, bright_col, 0.35)
    table_hi = lerp_col(base_col, bright_col, 0.72)
    d.polygon(table, fill=table_mid)
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.polygon(polygon_scale(table, cx, cy, 0.88), fill=(bright_col[0], bright_col[1], bright_col[2], 150))
    gd.polygon(polygon_scale(table, cx, cy, 0.58), fill=(table_hi[0], table_hi[1], table_hi[2], 210))
    glow = glow.filter(ImageFilter.GaussianBlur(16))
    # Clip glow to table polygon using mask, then alpha-composite onto img
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(table, fill=255)
    clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    clipped.paste(glow, (0, 0), mask)
    img = Image.alpha_composite(img, clipped)

    # Crisp table rim highlight line
    d = ImageDraw.Draw(img)
    for i in range(n):
        j = (i + 1) % n
        d.line([table[i], table[j]], fill=(bright_col[0], bright_col[1], bright_col[2], 185), width=3)

    if extra_fn:
        extra_fn(img, table, cx, cy)

    # Upper-left specular flare
    sx, sy = spec_pos
    draw_star_flare(img, sx, sy, r_major=42, r_minor=7, color=(255, 253, 246, 255), glow_r=18)
    return img


def emerald_pts():
    """Chamfered rectangle (emerald cut)."""
    cx, cy = 256, 256
    w, h, ch = 158, 206, 48
    return [
        (cx - w + ch, cy - h),
        (cx + w - ch, cy - h),
        (cx + w, cy - h + ch),
        (cx + w, cy + h - ch),
        (cx + w - ch, cy + h),
        (cx - w + ch, cy + h),
        (cx - w, cy + h - ch),
        (cx - w, cy - h + ch),
    ]


def princess_pts():
    """Square princess cut with subtle chamfered corners."""
    cx, cy = 256, 256
    w, ch = 186, 22
    return [
        (cx - w + ch, cy - w),
        (cx + w - ch, cy - w),
        (cx + w, cy - w + ch),
        (cx + w, cy + w - ch),
        (cx + w - ch, cy + w),
        (cx - w + ch, cy + w),
        (cx - w, cy + w - ch),
        (cx - w, cy - w + ch),
    ]


def pear_pts():
    """Teardrop pear cut (pointed top, rounded bottom)."""
    pts = [(256, 46)]
    # Right curve down to bottom, then left curve back up
    angles = [
        (-70, 128, 175),
        (-45, 165, 240),
        (-15, 176, 305),
        (20,  166, 368),
        (55,  126, 424),
        (80,  62,  456),
        (90,  0,   466),
    ]
    for _, dx, y in angles:
        if dx > 0:
            pts.append((256 + dx, y))
        else:
            pts.append((256, y))
    for _, dx, y in reversed(angles[:-1]):
        pts.append((256 - dx, y))
    return pts


def marquise_pts():
    """Pointed vertical eye/marquise cut."""
    pts = []
    steps = 16
    for i in range(steps):
        ang = -math.pi / 2 + 2 * math.pi * i / steps
        # Pointed at top and bottom using sin/cos power shaping
        x = 256 + 148 * (math.cos(ang) ** 1) * (abs(math.cos(ang)) ** 0.35)
        y = 256 + 216 * math.sin(ang)
        pts.append((x, y))
    return pts


def generate_missing_gems():
    # 1. Azeroth Emerald (vivid green emerald-cut)
    im = render_faceted_gem(
        emerald_pts(),
        base_col=(24, 178, 92),
        bright_col=(150, 255, 188),
        dark_col=(8, 72, 42),
        spec_pos=(162, 138),
    )
    im.save(os.path.join(SRC_DIR, "azeroth_emerald.png"))

    # 2. Azeroth Topaz (warm amber-gold princess-cut)
    im = render_faceted_gem(
        princess_pts(),
        base_col=(236, 168, 38),
        bright_col=(255, 238, 152),
        dark_col=(118, 66, 14),
        spec_pos=(156, 156),
    )
    im.save(os.path.join(SRC_DIR, "azeroth_topaz.png"))

    # 3. Azeroth Amethyst (violet purple pear-cut teardrop)
    im = render_faceted_gem(
        pear_pts(),
        base_col=(152, 68, 224),
        bright_col=(230, 178, 255),
        dark_col=(56, 20, 96),
        spec_pos=(196, 220),
    )
    im.save(os.path.join(SRC_DIR, "azeroth_amethyst.png"))

    # 4. Azeroth Diamond (ice-white marquise-cut with rainbow edge refraction)
    def diamond_refract(img, table, cx, cy):
        d = ImageDraw.Draw(img)
        # Subtle cyan/pink prismatic glints along inner facets
        d.line([table[2], table[3]], fill=(140, 235, 255, 210), width=5)
        d.line([table[10], table[11]], fill=(240, 175, 255, 200), width=5)
        draw_star_flare(img, cx, cy, r_major=36, r_minor=6, color=(240, 248, 255, 220), glow_r=16)

    im = render_faceted_gem(
        marquise_pts(),
        base_col=(212, 232, 250),
        bright_col=(255, 255, 255),
        dark_col=(92, 118, 158),
        spec_pos=(208, 162),
        extra_fn=diamond_refract,
    )
    im.save(os.path.join(SRC_DIR, "azeroth_diamond.png"))

    # 5. Polestar Ember (warm ember-orange pear-cut with glowing coal core)
    def ember_core(img, table, cx, cy):
        glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow)
        gd.ellipse([cx - 54, cy - 20, cx + 54, cy + 88], fill=(255, 210, 90, 220))
        glow = glow.filter(ImageFilter.GaussianBlur(22))
        img.alpha_composite(glow)

    im = render_faceted_gem(
        pear_pts(),
        base_col=(232, 96, 26),
        bright_col=(255, 206, 98),
        dark_col=(88, 24, 16),
        spec_pos=(196, 220),
        extra_fn=ember_core,
    )
    im.save(os.path.join(SRC_DIR, "polestar_ember.png"))

    # 6. Polestar Aurora (teal-green-violet shifting marquise-cut)
    def aurora_shift(img, table, cx, cy):
        ov = Image.new("RGBA", img.size, (0, 0, 0, 0))
        od = ImageDraw.Draw(ov)
        od.polygon([(cx - 80, cy - 120), (cx + 80, cy - 60), (cx + 60, cy + 40), (cx - 60, cy - 20)],
                   fill=(60, 245, 205, 115))
        od.polygon([(cx - 60, cy + 20), (cx + 70, cy + 60), (cx + 20, cy + 140), (cx - 40, cy + 110)],
                   fill=(155, 95, 255, 130))
        ov = ov.filter(ImageFilter.GaussianBlur(18))
        mask = Image.new("L", img.size, 0)
        ImageDraw.Draw(mask).polygon(table, fill=255)
        clipped_ov = Image.new("RGBA", img.size, (0, 0, 0, 0))
        clipped_ov.paste(ov, (0, 0), mask)
        img.alpha_composite(clipped_ov)

    im = render_faceted_gem(
        marquise_pts(),
        base_col=(28, 188, 172),
        bright_col=(145, 255, 232),
        dark_col=(28, 42, 86),
        spec_pos=(208, 162),
        extra_fn=aurora_shift,
    )
    im.save(os.path.join(SRC_DIR, "polestar_aurora.png"))


def generate_special_blast():
    """Symmetrical starburst glowing orange-gold crack overlay (transparent)."""
    S = 512
    cx, cy = S / 2.0, S / 2.0
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    d = ImageDraw.Draw(img)

    rng = random.Random(77)
    rays = 10
    for i in range(rays):
        ang = (2 * math.pi * i / rays) + rng.uniform(-0.1, 0.1)
        length = rng.uniform(165, 225)
        pts = [(cx, cy)]
        segs = 4
        for s in range(1, segs + 1):
            frac = s / segs
            jitter = rng.uniform(-16, 16) if s < segs else 0
            px = cx + math.cos(ang) * length * frac - math.sin(ang) * jitter
            py = cy + math.sin(ang) * length * frac + math.cos(ang) * jitter
            pts.append((px, py))
        gd.line(pts, fill=(255, 130, 28, 230), width=22)
        d.line(pts, fill=(255, 210, 95, 255), width=8)
        d.line(pts, fill=(255, 250, 230, 255), width=3)

    gd.ellipse([cx - 68, cy - 68, cx + 68, cy + 68], fill=(255, 165, 45, 240))
    glow = glow.filter(ImageFilter.GaussianBlur(18))
    out = Image.alpha_composite(glow, img)
    draw_star_flare(out, cx, cy, r_major=68, r_minor=18, color=(255, 252, 235, 255), glow_r=36)
    out.save(os.path.join(SRC_DIR, "special_blast.png"))


def generate_fx_sprites():
    # 1. fx_sparkle (256x256 -> 128x128)
    S = 256
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw_star_flare(im, 128, 128, r_major=114, r_minor=16, color=(255, 246, 210, 255), glow_r=44)
    draw_star_flare(im, 128, 128, r_major=70, r_minor=9, color=(255, 255, 255, 255), glow_r=16)
    im.save(os.path.join(SRC_DIR, "fx_sparkle.png"))

    # 2. fx_ring (512x512 -> 256x256)
    S = 512
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    core = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([44, 44, S - 44, S - 44], outline=(235, 186, 98, 230), width=26)
    glow = glow.filter(ImageFilter.GaussianBlur(14))
    ImageDraw.Draw(core).ellipse([44, 44, S - 44, S - 44], outline=(255, 244, 200, 255), width=8)
    out = Image.alpha_composite(glow, core)
    out.save(os.path.join(SRC_DIR, "fx_ring.png"))

    # 3. fx_beam (512x128 -> 256x64)
    W, H = 512, 128
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    core = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cy = H / 2.0
    # Tapered diamond/beam polygon
    beam_outer = [(8, cy), (70, cy - 30), (W - 70, cy - 30), (W - 8, cy), (W - 70, cy + 30), (70, cy + 30)]
    beam_inner = [(18, cy), (75, cy - 11), (W - 75, cy - 11), (W - 18, cy), (W - 75, cy + 11), (75, cy + 11)]
    ImageDraw.Draw(glow).polygon(beam_outer, fill=(245, 195, 92, 230))
    glow = glow.filter(ImageFilter.GaussianBlur(14))
    ImageDraw.Draw(core).polygon(beam_inner, fill=(255, 252, 238, 255))
    out = Image.alpha_composite(glow, core)
    out.save(os.path.join(SRC_DIR, "fx_beam.png"))

    # 4. fx_bolt (256x512 -> 128x256)
    W, H = 256, 512
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    core = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    pts = [
        (128, 12), (102, 82), (156, 134), (96, 214),
        (164, 276), (106, 356), (150, 418), (128, 500),
    ]
    branch1 = [(156, 134), (192, 166), (210, 206)]
    branch2 = [(96, 214), (58, 252), (46, 294)]
    gd = ImageDraw.Draw(glow)
    cd = ImageDraw.Draw(core)
    gd.line(pts, fill=(95, 205, 255, 240), width=28, joint="curve")
    gd.line(branch1, fill=(95, 205, 255, 180), width=14)
    gd.line(branch2, fill=(95, 205, 255, 180), width=14)
    glow = glow.filter(ImageFilter.GaussianBlur(12))
    cd.line(pts, fill=(225, 248, 255, 255), width=10)
    cd.line(pts, fill=(255, 255, 255, 255), width=4)
    cd.line(branch1, fill=(215, 245, 255, 220), width=4)
    cd.line(branch2, fill=(215, 245, 255, 220), width=4)
    out = Image.alpha_composite(glow, core)
    out.save(os.path.join(SRC_DIR, "fx_bolt.png"))

    # 5. fx_star (128x128 -> 32x32)
    S = 128
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw_star_flare(im, 64, 64, r_major=52, r_minor=14, color=(245, 204, 110, 255), glow_r=22)
    draw_star_flare(im, 64, 64, r_major=32, r_minor=8, color=(255, 252, 232, 255), glow_r=8)
    im.save(os.path.join(SRC_DIR, "fx_star.png"))

    # 6. fx_badge (256x256 -> 64x64): thin circular muted gold laurel-wreath frame
    S = 256
    cx, cy = S / 2.0, S / 2.0
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # Thin circular stem ring
    r_ring = 96
    d.ellipse([cx - r_ring, cy - r_ring, cx + r_ring, cy + r_ring], outline=(196, 158, 86, 255), width=6)
    # Symmetrical laurel leaves around left and right arcs
    for side in (-1, 1):
        for k in range(11):
            # Angle from bottom (+75 deg) to top (-75 deg)
            deg = 78 - k * 14.5
            rad = math.radians(deg)
            lx = cx + side * r_ring * math.cos(rad)
            ly = cy + r_ring * math.sin(rad)
            # Tangent angle pointing upward along ring
            tang = math.atan2(-math.cos(rad), -side * math.sin(rad))
            for flip in (-0.52, 0.52):
                la = tang + flip
                tip_x = lx + math.cos(la) * 20
                tip_y = ly + math.sin(la) * 20
                perp_x = -math.sin(la) * 6.5
                perp_y = math.cos(la) * 6.5
                mid_x = (lx + tip_x) * 0.5
                mid_y = (ly + tip_y) * 0.5
                leaf = [(lx, ly), (mid_x + perp_x, mid_y + perp_y), (tip_x, tip_y), (mid_x - perp_x, mid_y - perp_y)]
                col = (232, 192, 114, 255) if flip > 0 else (186, 146, 76, 255)
                d.polygon(leaf, fill=col)
    # Top emblem diamond clasp
    d.polygon([(cx, cy - r_ring - 12), (cx + 10, cy - r_ring), (cx, cy - r_ring + 12), (cx - 10, cy - r_ring)],
              fill=(250, 224, 155, 255))
    im.save(os.path.join(SRC_DIR, "fx_badge.png"))


def main():
    os.makedirs(SRC_DIR, exist_ok=True)
    generate_missing_gems()
    generate_special_blast()
    generate_fx_sprites()
    print("Generated 13 supersampled vector/glow source PNGs in assets_src/")


if __name__ == "__main__":
    main()
