#!/usr/bin/env python3
"""
True 3D-faceted glossy crystal gemstone renderer for Jeweled (classic Bejeweled 2/3 aesthetic).
Constructs real 3D polyhedral gem cuts (table, star facets, crown/bezel facets, upper-girdle
facets, and internal back-pavilion facets) and shades every facet with:
  - Exact 3D surface normals (no flat 2D cartoons, zero metal bezels/rims)
  - Total internal reflection (light entering top-left blazes out of opposite pavilion facets)
  - High-gloss Blinn-Phong white specular reflections + crisp glass ridge highlights
  - Translucent center table revealing faceted internal crystal fire underneath
  - Classic Bejeweled silhouettes (Square, Downward Triangle, Octagon, Diamond/Lozenge, Pear, Round)
Renders at 512x512 (4x supersampled) -> crisp 128x128 uncompressed 32-bit TGA.
"""

import math
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, "assets_src")
MEDIA_DIR = os.path.join(ROOT, "Jeweled", "Media")

S = 512
CX, CY = S * 0.5, S * 0.5


def v_sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def v_add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def v_norm(v):
    m = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    if m < 1e-9:
        return (0.0, 0.0, 1.0)
    return (v[0] / m, v[1] / m, v[2] / m)


def v_cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def v_dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def clamp(x, lo=0.0, hi=1.0):
    return lo if x < lo else (hi if x > hi else x)


def lerp(a, b, t):
    return a + (b - a) * t


def mix_rgb(c1, c2, t):
    t = clamp(t)
    return (
        int(round(lerp(c1[0], c2[0], t))),
        int(round(lerp(c1[1], c2[1], t))),
        int(round(lerp(c1[2], c2[2], t))),
    )


# Studio 3-point gemologist lighting
L_KEY = v_norm((-0.58, -0.66, 0.72))     # Primary bright studio key light (upper-left)
L_FILL = v_norm((0.52, 0.58, 0.62))      # Internal caustic bounce light (lower-right fire!)
L_RIM = v_norm((0.40, -0.70, 0.45))      # Crisp top-right glint light
V_EYE = (0.0, 0.0, 1.0)
H_KEY = v_norm(v_add(L_KEY, V_EYE))
H_FILL = v_norm(v_add(L_FILL, V_EYE))
H_RIM = v_norm(v_add(L_RIM, V_EYE))


def to_px(v):
    return (CX + v[0], CY + v[1])


def facet_normal(v0, v1, v2):
    n = v_norm(v_cross(v_sub(v1, v0), v_sub(v2, v0)))
    # Ensure front-facing normal points toward +Z
    if n[2] < 0:
        n = (-n[0], -n[1], -n[2])
    return n


def shade_crown_facet(v0, v1, v2, pal, is_pavilion=False, facet_idx=0):
    """High-contrast glossy Bejeweled crystal facet shading."""
    n = facet_normal(v0, v1, v2)
    deep, mid, bright, fire = pal["deep"], pal["mid"], pal["bright"], pal["fire"]

    nd_key = max(0.0, v_dot(n, L_KEY))
    nd_fill = max(0.0, v_dot(n, L_FILL))
    spec_key = max(0.0, v_dot(n, H_KEY)) ** 18
    spec_rim = max(0.0, v_dot(n, H_RIM)) ** 16
    spec_fill = max(0.0, v_dot(n, H_FILL)) ** 10

    if is_pavilion:
        # High-contrast alternating internal pavilion reflections (classic Bejeweled sparkle!)
        alt = 0.24 if (facet_idx % 2 == 0) else -0.22
        fire_amt = clamp(nd_fill * 0.92 + spec_fill * 0.85 + alt)
        if fire_amt < 0.42:
            col = mix_rgb(deep, mid, fire_amt / 0.42)
        elif fire_amt < 0.78:
            col = mix_rgb(mid, bright, (fire_amt - 0.42) / 0.36)
        else:
            col = mix_rgb(bright, fire, (fire_amt - 0.78) / 0.22)
        if pal.get("prismatic"):
            disp = pal["prismatic"][facet_idx % len(pal["prismatic"])]
            col = mix_rgb(col, disp, 0.34 * clamp(nd_fill + spec_fill))
        return col

    # Exterior crown / bezel facet with bold high-dynamic-range crystal contrast
    micro = 0.12 if (facet_idx % 2 == 0) else -0.10
    diffuse = clamp(nd_key * 0.86 + nd_fill * 0.22 + micro)

    if diffuse < 0.48:
        col = mix_rgb(deep, mid, (diffuse / 0.48) ** 1.15)
    else:
        col = mix_rgb(mid, bright, ((diffuse - 0.48) / 0.52) ** 0.95)

    # Fiery internal light bouncing out of lower-right bevels
    if nd_fill > 0.58:
        col = mix_rgb(col, fire, clamp((nd_fill - 0.58) * 1.45))

    if pal.get("prismatic"):
        disp = pal["prismatic"][facet_idx % len(pal["prismatic"])]
        col = mix_rgb(col, disp, 0.28 * clamp(spec_rim + nd_fill * 0.6))

    # Razor-crisp glossy white specular reflection on top-left crystal facets
    spec = clamp(spec_key * 1.35 + spec_rim * 0.55)
    col = mix_rgb(col, (255, 255, 255), spec * 0.94)
    return col


def build_ring_2d(pts_2d, scale, z, rot_offset=0.0):
    out = []
    ca, sa = math.cos(rot_offset), math.sin(rot_offset)
    for x, y in pts_2d:
        rx = (x * ca - y * sa) * scale
        ry = (x * sa + y * ca) * scale
        out.append((rx, ry, z))
    return out


def interpolate_midpoints(ring, z_override=None):
    n = len(ring)
    mids = []
    for i in range(n):
        a, b = ring[i], ring[(i + 1) % n]
        z = z_override if z_override is not None else (a[2] + b[2]) * 0.5
        mids.append(((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5, z))
    return mids


def draw_star_sparkle(img, x, y, r_maj, r_min, glow_r=14, col=(255, 255, 255, 255)):
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([x - glow_r, y - glow_r, x + glow_r, y + glow_r], fill=(col[0], col[1], col[2], 185))
    glow = glow.filter(ImageFilter.GaussianBlur(glow_r * 0.65))
    img.alpha_composite(glow)

    d = ImageDraw.Draw(img)
    pts = [
        (x, y - r_maj), (x + r_min, y - r_min),
        (x + r_maj, y), (x + r_min, y + r_min),
        (x, y + r_maj), (x - r_min, y + r_min),
        (x - r_maj, y), (x - r_min, y - r_min),
    ]
    d.polygon(pts, fill=col)


def render_bejeweled_gem(girdle_2d, pal, style="brilliant", table_scale=0.56, mid_scale=0.80, spec_hint=(-68, -72)):
    """Render a gleaming, pure naked 3D faceted crystal gemstone (512x512 RGBA)."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    n = len(girdle_2d)
    girdle = build_ring_2d(girdle_2d, 1.00, 0.0)

    # Outer crisp silhouette mask for clipping internal glows & glassy reflections
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon([to_px(v) for v in girdle], fill=255)

    if style == "step":
        # Bold 2-tier Bejeweled cushion/octagon bevel cut (clean, chunky facets at 44px!)
        tier1 = build_ring_2d(girdle_2d, 0.78, 46.0)
        table = build_ring_2d(girdle_2d, table_scale, 84.0)
        pav_mid = build_ring_2d(girdle_2d, 0.32, -55.0)
        apex = (0.0, 0.0, -110.0)

        rings = [girdle, tier1, table]
        f_idx = 0
        for r_i in range(len(rings) - 1):
            r_out, r_in = rings[r_i], rings[r_i + 1]
            for i in range(n):
                j = (i + 1) % n
                c1 = shade_crown_facet(r_out[i], r_out[j], r_in[j], pal, False, f_idx)
                c2 = shade_crown_facet(r_out[i], r_in[j], r_in[i], pal, False, f_idx + 1)
                d.polygon([to_px(r_out[i]), to_px(r_out[j]), to_px(r_in[j])], fill=c1 + (255,))
                d.polygon([to_px(r_out[i]), to_px(r_in[j]), to_px(r_in[i])], fill=c2 + (255,))
                f_idx += 2

        # Translucent Table revealing crisp internal back-pavilion facets underneath!
        for i in range(n):
            j = (i + 1) % n
            c1 = shade_crown_facet(table[i], table[j], pav_mid[j], pal, True, i * 2)
            c2 = shade_crown_facet(table[i], pav_mid[j], pav_mid[i], pal, True, i * 2 + 1)
            c3 = shade_crown_facet(pav_mid[i], pav_mid[j], apex, pal, True, i * 3 + 5)
            d.polygon([to_px(table[i]), to_px(table[j]), to_px(pav_mid[j])], fill=c1 + (255,))
            d.polygon([to_px(table[i]), to_px(pav_mid[j]), to_px(pav_mid[i])], fill=c2 + (255,))
            d.polygon([to_px(pav_mid[i]), to_px(pav_mid[j]), to_px(apex)], fill=c3 + (255,))

        ridge_rings = [tier1, table]

    else:
        # Brilliant / Kite-star cut (classic Bejeweled Round, Diamond/Lozenge, Trillion, Pear!)
        mid_ring = interpolate_midpoints(build_ring_2d(girdle_2d, mid_scale, 46.0))
        table = build_ring_2d(girdle_2d, table_scale, 84.0)
        pav_star = interpolate_midpoints(build_ring_2d(girdle_2d, table_scale * 0.56, -54.0))
        apex = (0.0, 0.0, -115.0)

        f_idx = 0
        for i in range(n):
            j = (i + 1) % n
            prev_i = (i - 1) % n
            # Upper girdle triangles + kite bezel facets + star facets
            # Girdle[i] -> Girdle[j] -> Mid[i]
            c_ug = shade_crown_facet(girdle[i], girdle[j], mid_ring[i], pal, False, f_idx)
            d.polygon([to_px(girdle[i]), to_px(girdle[j]), to_px(mid_ring[i])], fill=c_ug + (255,))
            # Kite left & right halves: Girdle[i] -> Mid[prev_i] -> Table[i] & Girdle[i] -> Table[i] -> Mid[i]
            c_kl = shade_crown_facet(girdle[i], mid_ring[prev_i], table[i], pal, False, f_idx + 1)
            c_kr = shade_crown_facet(girdle[i], table[i], mid_ring[i], pal, False, f_idx + 2)
            d.polygon([to_px(girdle[i]), to_px(mid_ring[prev_i]), to_px(table[i])], fill=c_kl + (255,))
            d.polygon([to_px(girdle[i]), to_px(table[i]), to_px(mid_ring[i])], fill=c_kr + (255,))
            # Star facet: Table[i] -> Table[j] -> Mid[i]
            c_st = shade_crown_facet(table[i], table[j], mid_ring[i], pal, False, f_idx + 3)
            d.polygon([to_px(table[i]), to_px(table[j]), to_px(mid_ring[i])], fill=c_st + (255,))
            f_idx += 4

        # Internal pavilion crystal geometry gleaming right through the clear polished table!
        for i in range(n):
            j = (i + 1) % n
            prev_i = (i - 1) % n
            c_p1 = shade_crown_facet(table[i], table[j], pav_star[i], pal, True, i * 3)
            c_p2 = shade_crown_facet(table[i], pav_star[i], apex, pal, True, i * 3 + 1)
            c_p3 = shade_crown_facet(table[i], apex, pav_star[prev_i], pal, True, i * 3 + 2)
            d.polygon([to_px(table[i]), to_px(table[j]), to_px(pav_star[i])], fill=c_p1 + (255,))
            d.polygon([to_px(table[i]), to_px(pav_star[i]), to_px(apex)], fill=c_p2 + (255,))
            d.polygon([to_px(table[i]), to_px(apex), to_px(pav_star[prev_i])], fill=c_p3 + (255,))

        ridge_rings = [table]

    # 3. Internal jewel-fire glow (subtle luminous heart + caustic glow on lower-right, clipped to gem)
    fire_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fire_layer)
    fc = pal["fire"]
    bc = pal["bright"]
    # Lower-right internal refraction caustic pool
    fd.ellipse([CX - 60, CY - 35, CX + 130, CY + 145], fill=(fc[0], fc[1], fc[2], 125))
    # Bright luminous core
    fd.ellipse([CX - 75, CY - 75, CX + 75, CY + 75], fill=(bc[0], bc[1], bc[2], 70))
    fire_layer = fire_layer.filter(ImageFilter.GaussianBlur(34))
    clipped_fire = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    clipped_fire.paste(fire_layer, (0, 0), mask)
    img = Image.alpha_composite(img, clipped_fire)

    # 4. Glossy glass table reflection (crisp subtle translucent upper-left sheen across the table)
    sheen = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sheen)
    t_pts = [to_px(v) for v in table]
    # Soft bright upper-left glass glaze on the table
    sd.polygon(t_pts, fill=(255, 255, 255, 28))
    # Crisp bright angled glass catchlight band across upper-left of table
    table_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(table_mask).polygon(t_pts, fill=255)
    sd.polygon([(CX - 180, CY - 180), (CX + 80, CY - 180), (CX - 180, CY + 55)], fill=(255, 255, 255, 82))
    sheen = sheen.filter(ImageFilter.GaussianBlur(4))
    clipped_sheen = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    clipped_sheen.paste(sheen, (0, 0), table_mask)
    img = Image.alpha_composite(img, clipped_sheen)

    # 5. Razor-sharp glass facet ridge highlights (properly alpha-composited, NEVER dark seams!)
    edge_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ed = ImageDraw.Draw(edge_layer)
    for ring in ridge_rings:
        rn = len(ring)
        for i in range(rn):
            j = (i + 1) % rn
            p1, p2 = to_px(ring[i]), to_px(ring[j])
            mx, my = (p1[0] + p2[0]) * 0.5 - CX, (p1[1] + p2[1]) * 0.5 - CY
            dot = (mx * -0.7 + my * -0.7) / (math.hypot(mx, my) + 1e-5)
            alpha = int(clamp(0.42 + dot * 0.52, 0.16, 0.94) * 255)
            ed.line([p1, p2], fill=(255, 255, 255, alpha), width=3)

    # Subtle pure-crystal outer bevel highlight (bright crystal edge top-left, deep crystal edge bottom-right)
    for i in range(n):
        j = (i + 1) % n
        p1, p2 = to_px(girdle[i]), to_px(girdle[j])
        mx, my = (p1[0] + p2[0]) * 0.5 - CX, (p1[1] + p2[1]) * 0.5 - CY
        dot = (mx * -0.7 + my * -0.7) / (math.hypot(mx, my) + 1e-5)
        if dot > 0.0:
            edge_c = mix_rgb(pal["bright"], (255, 255, 255), dot * 0.85)
            ed.line([p1, p2], fill=edge_c + (220,), width=4)
        else:
            edge_c = mix_rgb(pal["deep"], pal["mid"], 0.18)
            ed.line([p1, p2], fill=edge_c + (180,), width=3)

    img = Image.alpha_composite(img, edge_layer)

    # 6. Crisp gemologist specular star flare on upper-left crown facet!
    sx, sy = CX + spec_hint[0], CY + spec_hint[1]
    draw_star_sparkle(img, sx, sy, r_maj=44, r_min=6.5, glow_r=18)

    # Re-apply exact silhouette alpha mask so exterior stays 100% razor clean
    r_ch, g_ch, b_ch, a_ch = img.split()
    clean_a = Image.composite(a_ch, Image.new("L", (S, S), 0), mask)
    img = Image.merge("RGBA", (r_ch, g_ch, b_ch, clean_a))
    return img


# ---------------------------------------------------------------------------
# Classic Bejeweled 6 distinct gem silhouettes (2D girdle polygons centered at 0,0)
# ---------------------------------------------------------------------------

def shape_square_cushion():
    """Classic Bejeweled Red Square (cushion-cut with subtle faceted corners)."""
    r = 196
    c = 36
    return [
        (-r + c, -r), (r - c, -r),
        (r, -r + c),  (r, r - c),
        (r - c, r),   (-r + c, r),
        (-r, r - c),  (-r, -r + c),
    ]


def shape_down_triangle():
    """Classic Bejeweled Blue Downward Triangle (trillion-cut with crisp chamfered tips)."""
    # Slightly raised centroid so triangle feels visually balanced in square cell
    top_y = -182
    bot_y = 202
    half_w = 208
    # 9-point rounded/beveled trillion silhouette
    return [
        (-half_w + 30, top_y),
        (0, top_y - 12),
        (half_w - 30, top_y),
        (half_w, top_y + 28),
        (half_w * 0.56, 20),
        (24, bot_y - 12),
        (0, bot_y),
        (-24, bot_y - 12),
        (-half_w * 0.56, 20),
        (-half_w, top_y + 28),
    ]


def shape_octagon():
    """Classic Bejeweled Green Octagon (emerald/octagon cut)."""
    r = 206
    pts = []
    for i in range(8):
        ang = math.radians(22.5 + i * 45.0)
        pts.append((math.cos(ang) * r, math.sin(ang) * r))
    return pts


def shape_diamond_lozenge():
    """Classic Bejeweled Yellow Diamond / Rhombus (lozenge cut)."""
    rx, ry = 194, 212
    # 8-point crisp faceted diamond with beveled tips
    return [
        (0, -ry),
        (rx * 0.54, -ry * 0.50),
        (rx, 0),
        (rx * 0.54, ry * 0.50),
        (0, ry),
        (-rx * 0.54, ry * 0.50),
        (-rx, 0),
        (-rx * 0.54, -ry * 0.50),
    ]


def shape_pear():
    """Classic Amethyst Teardrop / Pear cut (pointed top, lush faceted bottom)."""
    return [
        (0, -214),
        (64, -148),
        (134, -56),
        (174, 34),
        (166, 114),
        (114, 178),
        (42, 208),
        (0, 214),
        (-42, 208),
        (-114, 178),
        (-166, 114),
        (-174, 34),
        (-134, -56),
        (-64, -148),
    ]


def shape_round_brilliant():
    """Classic Bejeweled White Round Brilliant Diamond (16-sided crisp circular cut)."""
    r = 204
    pts = []
    for i in range(16):
        ang = (2.0 * math.pi * i / 16.0) - math.pi * 0.5
        pts.append((math.cos(ang) * r, math.sin(ang) * r))
    return pts


# ---------------------------------------------------------------------------
# Palettes (rich, saturated Bejeweled crystal colors — deep, mid, bright, internal fire)
# ---------------------------------------------------------------------------

AZEROTH_SPECS = [
    ("gems/azeroth/ruby.tga", "azeroth_ruby", shape_square_cushion(), "step", 0.54, 0.80, (-76, -76), {
        "deep": (72, 2, 12),
        "mid": (212, 10, 32),
        "bright": (255, 76, 94),
        "fire": (255, 192, 156),
    }),
    ("gems/azeroth/sapphire.tga", "azeroth_sapphire", shape_down_triangle(), "brilliant", 0.52, 0.80, (-66, -92), {
        "deep": (5, 18, 108),
        "mid": (18, 96, 245),
        "bright": (108, 198, 255),
        "fire": (190, 245, 255),
    }),
    ("gems/azeroth/emerald.tga", "azeroth_emerald", shape_octagon(), "step", 0.54, 0.80, (-74, -76), {
        "deep": (2, 56, 22),
        "mid": (10, 178, 72),
        "bright": (104, 255, 152),
        "fire": (210, 255, 178),
    }),
    ("gems/azeroth/topaz.tga", "azeroth_topaz", shape_diamond_lozenge(), "brilliant", 0.54, 0.82, (-56, -66), {
        "deep": (118, 48, 2),
        "mid": (244, 172, 8),
        "bright": (255, 238, 104),
        "fire": (255, 252, 210),
    }),
    ("gems/azeroth/amethyst.tga", "azeroth_amethyst", shape_pear(), "brilliant", 0.54, 0.80, (-54, -10), {
        "deep": (48, 6, 96),
        "mid": (166, 32, 238),
        "bright": (236, 138, 255),
        "fire": (255, 210, 255),
    }),
    ("gems/azeroth/diamond.tga", "azeroth_diamond", shape_round_brilliant(), "brilliant", 0.55, 0.80, (-74, -76), {
        "deep": (76, 96, 136),
        "mid": (184, 204, 228),
        "bright": (244, 250, 255),
        "fire": (255, 255, 255),
        "prismatic": [(140, 228, 255), (255, 178, 230), (255, 238, 155), (175, 195, 255)],
    }),
]

POLESTAR_SPECS = [
    ("gems/polestar/gold.tga", "polestar_gold", shape_square_cushion(), "step", 0.52, 0.80, (-82, -82), {
        "deep": (116, 72, 16),
        "mid": (228, 182, 86),
        "bright": (255, 228, 152),
        "fire": (255, 248, 214),
    }),
    ("gems/polestar/starlight.tga", "polestar_starlight", shape_down_triangle(), "brilliant", 0.52, 0.80, (-68, -94), {
        "deep": (34, 72, 146),
        "mid": (122, 186, 252),
        "bright": (212, 238, 255),
        "fire": (245, 252, 255),
    }),
    ("gems/polestar/void.tga", "polestar_void", shape_octagon(), "step", 0.52, 0.80, (-76, -78), {
        "deep": (24, 22, 76),
        "mid": (84, 76, 188),
        "bright": (162, 156, 255),
        "fire": (212, 198, 255),
    }),
    ("gems/polestar/silver.tga", "polestar_silver", shape_diamond_lozenge(), "brilliant", 0.54, 0.82, (-58, -68), {
        "deep": (88, 98, 120),
        "mid": (184, 198, 218),
        "bright": (238, 244, 252),
        "fire": (255, 255, 255),
    }),
    ("gems/polestar/ember.tga", "polestar_ember", shape_pear(), "brilliant", 0.54, 0.80, (-56, -12), {
        "deep": (124, 26, 6),
        "mid": (244, 102, 18),
        "bright": (255, 186, 76),
        "fire": (255, 236, 155),
    }),
    ("gems/polestar/aurora.tga", "polestar_aurora", shape_round_brilliant(), "brilliant", 0.55, 0.80, (-74, -76), {
        "deep": (8, 86, 98),
        "mid": (24, 206, 192),
        "bright": (142, 255, 238),
        "fire": (205, 255, 250),
        "prismatic": [(90, 255, 220), (175, 130, 255), (120, 235, 255), (120, 255, 180)],
    }),
]


def save_gem_tga(img_512, rel_tga, src_stem):
    os.makedirs(SRC_DIR, exist_ok=True)
    img_512.save(os.path.join(SRC_DIR, f"{src_stem}.png"))
    # Crop tightly and center into 128x128 with 90% fill for crisp board readability
    bbox = img_512.getbbox()
    cropped = img_512.crop(bbox) if bbox else img_512
    cw, ch = cropped.size
    max_d = int(128 * 0.90)
    scale = min(max_d / cw, max_d / ch)
    nw, nh = max(1, int(round(cw * scale))), max(1, int(round(ch * scale)))
    resized = cropped.resize((nw, nh), Image.Resampling.LANCZOS)
    out = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    out.paste(resized, ((128 - nw) // 2, (128 - nh) // 2), resized)

    out_path = os.path.join(MEDIA_DIR, rel_tga)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    out.save(out_path, format="TGA", compression=None)
    return out


def build_contact_sheet():
    cell = 76
    cols = 6
    rows = 3
    w = cols * cell + 24
    h = rows * cell + 30
    sheet = Image.new("RGBA", (w, h), (22, 27, 42, 255))
    draw = ImageDraw.Draw(sheet)

    grid_rows = [
        [s[0] for s in AZEROTH_SPECS],
        [s[0] for s in POLESTAR_SPECS],
        ["gems/special/prismatic.tga", "icon.tga", "fx/sparkle.tga", "fx/ring.tga", "fx/badge.tga", "icon.tga"],
    ]
    for r, items in enumerate(grid_rows):
        for c, rel in enumerate(items):
            x = 12 + c * cell
            y = 14 + r * cell
            bg_col = (235, 238, 244, 255) if (r == 2 and c == 5) else (14, 18, 30, 255)
            draw.rectangle([x + 2, y + 2, x + 70, y + 70], fill=bg_col, outline=(56, 68, 96, 255))
            p = os.path.join(MEDIA_DIR, rel)
            if os.path.exists(p):
                im = Image.open(p).convert("RGBA")
                im.thumbnail((64, 64), Image.Resampling.LANCZOS)
                sheet.alpha_composite(im, (x + 4 + (64 - im.width) // 2, y + 4 + (64 - im.height) // 2))

    out_sheet = os.path.join(SRC_DIR, "contact_sheet_64px.png")
    sheet.save(out_sheet)
    print(f"Saved updated contact sheet: {out_sheet}")


def main():
    for rel_tga, stem, pts, style, t_sc, m_sc, spec, pal in AZEROTH_SPECS + POLESTAR_SPECS:
        img = render_bejeweled_gem(pts, pal, style=style, table_scale=t_sc, mid_scale=m_sc, spec_hint=spec)
        save_gem_tga(img, rel_tga, stem)
        print(f"  rendered {rel_tga}")
    build_contact_sheet()


if __name__ == "__main__":
    main()
