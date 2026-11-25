#!/usr/bin/env python3
"""
Generate shape-matched animated elemental flipbooks flowing OUTSIDE the exact
contour of each of our 6 classic Bejeweled gem shapes (1=Square, 2=Triangle,
3=Octagon, 4=Diamond, 5=Pear, 6=Round):
  - fx/fire_1.tga .. fire_6.tga       (256x128, 4x2 = 8 frames of 64x64)
  - fx/bolt_h_1.tga .. bolt_h_6.tga   (256x128, 4x2 = 8 frames of 64x64)
  - fx/bolt_v_1.tga .. bolt_v_6.tga   (256x128, 4x2 = 8 frames of 64x64)
  - fx/anim_prism.tga                 (512x256, 4x2 = 8 frames of 128x128, masked inside orb)
  - fx/chev_h.tga, fx/chev_v.tga      (128x128, crisp directional arrowheads)
  - fx/glint.tga (128x128), fx/shard.tga (64x64)
Also saves assets_src/anim_fx_preview.png showing all 6 shapes with their exact
outer fire and outer crackling lightning.
"""

import colorsys
import math
import os
import random
import sys
from PIL import Image, ImageDraw, ImageFilter

TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS_DIR)
SRC_DIR = os.path.join(ROOT, "assets_src")
FX_DIR = os.path.join(ROOT, "Jeweled", "Media", "fx")

sys.path.insert(0, TOOLS_DIR)
import gen_bejeweled_gems as gemgen

SHAPES = [
    (1, "square",   gemgen.shape_square_cushion(),  "gems/azeroth/ruby.tga"),
    (2, "triangle", gemgen.shape_down_triangle(),   "gems/azeroth/sapphire.tga"),
    (3, "octagon",  gemgen.shape_octagon(),         "gems/azeroth/emerald.tga"),
    (4, "diamond",  gemgen.shape_diamond_lozenge(), "gems/azeroth/topaz.tga"),
    (5, "pear",     gemgen.shape_pear(),            "gems/azeroth/amethyst.tga"),
    (6, "round",    gemgen.shape_round_brilliant(), "gems/azeroth/diamond.tga"),
]


def normalize_polygon_to_canvas(pts_2d, canvas_size=256, gem_fill=0.72):
    """Map gem 2D girdle polygon identically to how the gem sits inside the larger FX frame.
    Since btn.spec is sized (cellSize + 10) vs btn.gem (cellSize - 6), the gem fills ~72%
    of the FX frame width/height, leaving crisp room around all edges for outer flames & arcs!
    """
    xs = [p[0] for p in pts_2d]
    ys = [p[1] for p in pts_2d]
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    w = max(1e-5, max_x - min_x)
    h = max(1e-5, max_y - min_y)
    cx_src = (min_x + max_x) * 0.5
    cy_src = (min_y + max_y) * 0.5
    max_d = canvas_size * gem_fill
    scale = min(max_d / w, max_d / h)
    c = canvas_size * 0.5
    return [(c + (x - cx_src) * scale, c + (y - cy_src) * scale) for x, y in pts_2d]


def sample_perimeter(poly, num_samples=48):
    """Sample evenly spaced points + outward unit normals along a closed clockwise polygon."""
    n = len(poly)
    segs = []
    total = 0.0
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        L = math.hypot(x2 - x1, y2 - y1)
        segs.append((x1, y1, x2, y2, L))
        total += L

    cx = sum(p[0] for p in poly) / n
    cy = sum(p[1] for p in poly) / n

    samples = []
    step = total / num_samples
    dist_acc = 0.0
    seg_idx = 0
    seg_pos = 0.0
    for _ in range(num_samples):
        while seg_idx < n - 1 and seg_pos > segs[seg_idx][4]:
            seg_pos -= segs[seg_idx][4]
            seg_idx += 1
        x1, y1, x2, y2, L = segs[seg_idx]
        t = seg_pos / max(L, 1e-6)
        px = x1 + (x2 - x1) * t
        py = y1 + (y2 - y1) * t
        # Edge tangent -> outward normal pointing away from centroid
        tx = (x2 - x1) / max(L, 1e-6)
        ty = (y2 - y1) / max(L, 1e-6)
        nx, ny = ty, -tx
        if (px - cx) * nx + (py - cy) * ny < 0:
            nx, ny = -nx, -ny
        samples.append((px, py, nx, ny))
        seg_pos += step
        dist_acc += step
    return samples, (cx, cy)


def make_shape_fire_frame(poly_256, shape_id, frame_idx, total_frames=8):
    """Render flames flowing OUTWARD & UPWARD off the exact edges of `poly_256`."""
    S = 256
    phase = 2.0 * math.pi * frame_idx / total_frames
    samples, (cx, cy) = sample_perimeter(poly_256, num_samples=32)

    outer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    mid = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    core = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    od, md, cd = ImageDraw.Draw(outer), ImageDraw.Draw(mid), ImageDraw.Draw(core)

    # 1. Contour-hugging fiery glow outlining the exact gem shape!
    closed = poly_256 + [poly_256[0]]
    od.line(closed, fill=(255, 65, 8, 225), width=20, joint="curve")
    md.line(closed, fill=(255, 165, 22, 235), width=10, joint="curve")
    cd.line(closed, fill=(255, 245, 165, 225), width=4, joint="curve")

    # 2. Organic flame tongues erupting outward & curving upward right off the perimeter!
    for i, (px, py, nx, ny) in enumerate(samples):
        if i % 2 != 0:
            continue
        p_off = i * 0.9 + shape_id * 1.7
        # Stronger, taller flames off the upper & side edges, gentler flickering licks along bottom
        up_weight = max(0.32, 0.70 - ny * 0.48)
        flicker = 0.78 + 0.30 * math.sin(phase + p_off) + 0.14 * math.cos(phase * 2.0 - p_off * 1.3)
        reach = (24 + 26 * up_weight) * flicker

        # Flow direction: blend outward normal with upward fire draft (0, -1)
        dx = nx * 0.68 + math.sin(phase + p_off * 1.4) * 0.25
        dy = ny * 0.45 - 0.82
        dm = math.hypot(dx, dy) or 1.0
        dx, dy = dx / dm, dy / dm

        # Tangent perpendicular to flow
        tx, ty = -dy, dx

        def tongue(w_base, r_scale):
            r = reach * r_scale
            tip_x = px + dx * r + math.sin(phase + p_off * 1.9) * 5
            tip_y = py + dy * r
            mid_x = px + dx * (r * 0.48)
            mid_y = py + dy * (r * 0.48)
            return [
                (px - tx * w_base, py - ty * w_base),
                (mid_x - tx * (w_base * 0.62), mid_y - ty * (w_base * 0.62)),
                (tip_x, tip_y),
                (mid_x + tx * (w_base * 0.62), mid_y + ty * (w_base * 0.62)),
                (px + tx * w_base, py + ty * w_base),
            ]

        od.polygon(tongue(13, 1.12), fill=(255, 62, 8, 225))
        md.polygon(tongue(8.5, 0.84), fill=(255, 162, 22, 240))
        cd.polygon(tongue(4.5, 0.54), fill=(255, 244, 155, 245))

    # 3. Tiny rising ember sparks lifting off the upper edges
    for k in range(5):
        t = ((frame_idx / total_frames) + k * 0.20) % 1.0
        sp = samples[(k * 7 + shape_id * 3) % len(samples)]
        ex = sp[0] + sp[2] * (8 + t * 22) + math.sin(t * 5.0 + k) * 6
        ey = sp[1] - t * 34
        r_sp = max(2, int(4.5 * (1.0 - t * 0.6)))
        a = int(245 * math.sin(t * math.pi))
        cd.ellipse([ex - r_sp, ey - r_sp, ex + r_sp, ey + r_sp], fill=(255, 240, 145, a))

    outer = outer.filter(ImageFilter.GaussianBlur(7))
    mid = mid.filter(ImageFilter.GaussianBlur(3))
    core = core.filter(ImageFilter.GaussianBlur(1.2))
    out = Image.alpha_composite(outer, mid)
    out = Image.alpha_composite(out, core)

    # Clear the interior of the gem polygon (shrunk 8% inward) so flames sit strictly
    # ON THE OUTSIDE EDGE and never muddy the gem's crystal facets!
    inner_poly = [(cx + (x - cx) * 0.88, cy + (y - cy) * 0.88) for x, y in poly_256]
    inner_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(inner_mask).polygon(inner_poly, fill=255)
    inner_mask = inner_mask.filter(ImageFilter.GaussianBlur(5))
    r_c, g_c, b_c, a_c = out.split()
    a_px = a_c.load()
    m_px = inner_mask.load()
    for y in range(S):
        for x in range(S):
            m = m_px[x, y]
            if m > 0:
                a_px[x, y] = int(a_px[x, y] * (1.0 - m / 255.0))
    out = Image.merge("RGBA", (r_c, g_c, b_c, a_c))
    return out.resize((64, 64), Image.Resampling.LANCZOS)


def make_shape_lightning_frame(poly_256, shape_id, frame_idx, horizontal=True):
    """Render sharp crackling electric arcs hugging & jumping OUTSIDE the exact gem contour."""
    S = 256
    rng = random.Random(33100 + shape_id * 1009 + frame_idx * 211 + (0 if horizontal else 5555))
    samples, (cx, cy) = sample_perimeter(poly_256, num_samples=48)

    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    mid = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    core = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd, md, cd = ImageDraw.Draw(glow), ImageDraw.Draw(mid), ImageDraw.Draw(core)

    def draw_bolt(pts, w_g, w_m, w_c, inten=1.0):
        gd.line(pts, fill=(35, 195, 255, int(235 * inten)), width=w_g)
        md.line(pts, fill=(155, 242, 255, int(248 * inten)), width=w_m)
        cd.line(pts, fill=(255, 255, 255, int(255 * inten)), width=w_c)

    # 1. Chaotic crackling electric arcs racing along segments of the gem's exact outer perimeter!
    num_arcs = 5
    for a in range(num_arcs):
        start_i = rng.randint(0, len(samples) - 1)
        arc_len = rng.randint(6, 13)
        pts = []
        for s in range(arc_len):
            px, py, nx, ny = samples[(start_i + s) % len(samples)]
            # Jump slightly OUTSIDE the gem contour (3..19px outward) with jagged crackle
            env = math.sin((s / max(1, arc_len - 1)) * math.pi)
            out_d = 3.0 + rng.uniform(1.0, 17.0) * (0.35 + 0.65 * env)
            tang_j = rng.uniform(-5.0, 5.0)
            pts.append((px + nx * out_d - ny * tang_j, py + ny * out_d + nx * tang_j))
        inten = 0.72 + 0.28 * rng.random()
        draw_bolt(pts, 13, 6, 3, inten)

        # Sharp outward snapping fork jumping off the gem edge!
        if rng.random() < 0.85 and len(pts) >= 4:
            bi = rng.randint(1, len(pts) - 2)
            bx, by = pts[bi]
            # Shoot generally outward from centroid
            ang = math.atan2(by - cy, bx - cx) + rng.uniform(-0.65, 0.65)
            mx = bx + math.cos(ang) * rng.uniform(10, 18)
            my = by + math.sin(ang) * rng.uniform(10, 18)
            ang2 = ang + rng.uniform(-0.85, 0.85)
            ex = mx + math.cos(ang2) * rng.uniform(8, 16)
            ey = my + math.sin(ang2) * rng.uniform(8, 16)
            draw_bolt([(bx, by), (mx, my), (ex, ey)], 8, 4, 2, inten * 0.85)

    # 2. Bright crackling electric arcs snapping outward along the clear axis toward the chevrons
    for side in (-1, 1):
        # Pick the perimeter sample furthest along +axis or -axis
        best_s = max(samples, key=lambda s: (s[0] - cx) * side if horizontal else (s[1] - cy) * side)
        bx, by = best_s[0], best_s[1]
        pts = [(bx, by)]
        for step in range(1, 5):
            frac = step / 4.0
            if horizontal:
                nx_p = bx + side * (frac * 28)
                ny_p = by + rng.uniform(-14, 14) * math.sin(frac * math.pi)
            else:
                nx_p = bx + rng.uniform(-14, 14) * math.sin(frac * math.pi)
                ny_p = by + side * (frac * 28)
            pts.append((nx_p, ny_p))
        draw_bolt(pts, 11, 5, 2, 0.92)

    # 3. Tiny bright popping sparks outside the perimeter
    for _ in range(5):
        sp = samples[rng.randint(0, len(samples) - 1)]
        d_out = rng.uniform(6, 22)
        sx = sp[0] + sp[2] * d_out
        sy = sp[1] + sp[3] * d_out
        r_sp = rng.randint(2, 4)
        gd.ellipse([sx - r_sp * 2.5, sy - r_sp * 2.5, sx + r_sp * 2.5, sy + r_sp * 2.5], fill=(60, 220, 255, 220))
        cd.ellipse([sx - r_sp, sy - r_sp, sx + r_sp, sy + r_sp], fill=(255, 255, 255, 255))

    glow = glow.filter(ImageFilter.GaussianBlur(6))
    mid = mid.filter(ImageFilter.GaussianBlur(2))
    out = Image.alpha_composite(glow, mid)
    out = Image.alpha_composite(out, core)

    # Keep interior of gem clean so electricity crackles ON THE OUTSIDE of the silhouette!
    inner_poly = [(cx + (x - cx) * 0.90, cy + (y - cy) * 0.90) for x, y in poly_256]
    inner_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(inner_mask).polygon(inner_poly, fill=255)
    inner_mask = inner_mask.filter(ImageFilter.GaussianBlur(4))
    r_c, g_c, b_c, a_c = out.split()
    a_px = a_c.load()
    m_px = inner_mask.load()
    for y in range(S):
        for x in range(S):
            m = m_px[x, y]
            if m > 0:
                a_px[x, y] = int(a_px[x, y] * (1.0 - m / 255.0))
    out = Image.merge("RGBA", (r_c, g_c, b_c, a_c))
    return out.resize((64, 64), Image.Resampling.LANCZOS)


def make_directional_chevrons(horizontal=True):
    S = 256
    cx, cy = S * 0.5, S * 0.5
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    mid = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    core = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd, md, cd = ImageDraw.Draw(glow), ImageDraw.Draw(mid), ImageDraw.Draw(core)

    def pt(along, across):
        return (along, across) if horizontal else (across, along)

    for side in (-1, 1):
        tip_d = 122
        base_d = 94
        half_w = 24
        notch_d = 101
        outer_poly = [
            pt(cx + side * base_d, cy - half_w),
            pt(cx + side * tip_d,  cy),
            pt(cx + side * base_d, cy + half_w),
            pt(cx + side * notch_d, cy),
        ]
        inner_poly = [
            pt(cx + side * (base_d + 5), cy - half_w * 0.52),
            pt(cx + side * (tip_d - 4),  cy),
            pt(cx + side * (base_d + 5), cy + half_w * 0.52),
            pt(cx + side * (notch_d + 3), cy),
        ]
        gd.polygon(outer_poly, fill=(35, 195, 255, 235))
        md.polygon(outer_poly, fill=(165, 244, 255, 245))
        cd.polygon(inner_poly, fill=(255, 255, 255, 255))

    glow = glow.filter(ImageFilter.GaussianBlur(7))
    mid = mid.filter(ImageFilter.GaussianBlur(2))
    out = Image.alpha_composite(glow, mid)
    out = Image.alpha_composite(out, core)
    return out.resize((128, 128), Image.Resampling.LANCZOS)


def make_prism_shimmer_frame(frame_idx, total_frames=8):
    S = 256
    phase = frame_idx / float(total_frames)
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    for b in range(4):
        hue = (phase + b * 0.25) % 1.0
        rr, gg, bb = colorsys.hsv_to_rgb(hue, 0.72, 1.0)
        col = (int(rr * 255), int(gg * 255), int(bb * 255), 115)
        shift = ((phase + b * 0.25) % 1.0) * (S * 1.6) - S * 0.3
        d.line([(shift - 110, S + 20), (shift + 110, -20)], fill=col, width=48)

    pulse = 0.5 + 0.5 * math.sin(phase * 2.0 * math.pi)
    r_c = int(40 + 14 * pulse)
    d.ellipse([S * 0.5 - r_c, S * 0.5 - r_c, S * 0.5 + r_c, S * 0.5 + r_c],
              fill=(255, 255, 255, int(195 + 45 * pulse)))
    img = img.filter(ImageFilter.GaussianBlur(12))
    return img.resize((128, 128), Image.Resampling.LANCZOS)


def build_sheet(frames, cols=4, rows=2, frame_size=64):
    sheet = Image.new("RGBA", (cols * frame_size, rows * frame_size), (0, 0, 0, 0))
    for i, fr in enumerate(frames):
        col = i % cols
        row = i // cols
        sheet.paste(fr, (col * frame_size, row * frame_size))
    return sheet


def main():
    os.makedirs(FX_DIR, exist_ok=True)
    os.makedirs(SRC_DIR, exist_ok=True)

    chev_h = make_directional_chevrons(horizontal=True)
    chev_v = make_directional_chevrons(horizontal=False)
    chev_h.save(os.path.join(FX_DIR, "chev_h.tga"), format="TGA", compression=None)
    chev_v.save(os.path.join(FX_DIR, "chev_v.tga"), format="TGA", compression=None)

    prism_frames = [make_prism_shimmer_frame(i) for i in range(8)]
    build_sheet(prism_frames, cols=4, rows=2, frame_size=128).save(
        os.path.join(FX_DIR, "anim_prism.tga"), format="TGA", compression=None
    )

    # Generate contour-matched outer Fire, Row Lightning, and Col Lightning for all 6 shapes!
    preview_rows = []
    for shape_id, name, raw_pts, sample_rel in SHAPES:
        poly = normalize_polygon_to_canvas(raw_pts, canvas_size=256, gem_fill=0.72)

        f_frames = [make_shape_fire_frame(poly, shape_id, i, 8) for i in range(8)]
        lh_frames = [make_shape_lightning_frame(poly, shape_id, i, horizontal=True) for i in range(8)]
        lv_frames = [make_shape_lightning_frame(poly, shape_id, i, horizontal=False) for i in range(8)]

        build_sheet(f_frames, 4, 2, 64).save(os.path.join(FX_DIR, f"fire_{shape_id}.tga"), format="TGA", compression=None)
        build_sheet(lh_frames, 4, 2, 64).save(os.path.join(FX_DIR, f"bolt_h_{shape_id}.tga"), format="TGA", compression=None)
        build_sheet(lv_frames, 4, 2, 64).save(os.path.join(FX_DIR, f"bolt_v_{shape_id}.tga"), format="TGA", compression=None)
        print(f"  wrote shape {shape_id} ({name}): fire_{shape_id}, bolt_h_{shape_id}, bolt_v_{shape_id}")

        gem_im = Image.open(os.path.join(ROOT, "Jeweled", "Media", sample_rel)).convert("RGBA")
        preview_rows.append((gem_im, f_frames[2], lh_frames[2], lv_frames[2]))

    # Build QA preview: 6 columns (all 6 shapes) x 3 rows (Outer Fire, Outer Row Lightning, Outer Col Lightning)
    cell = 78
    prev = Image.new("RGBA", (6 * cell + 16, 3 * cell + 16), (18, 22, 36, 255))
    for c, (gem_im, f_fr, lh_fr, lv_fr) in enumerate(preview_rows):
        g_sz = int(68 * 0.78)
        g_res = gem_im.resize((g_sz, g_sz), Image.Resampling.LANCZOS)
        off = (68 - g_sz) // 2

        for r, (fx_fr, dir_ov) in enumerate([(f_fr, None), (lh_fr, chev_h), (lv_fr, chev_v)]):
            tile = Image.new("RGBA", (68, 68), (12, 16, 26, 255))
            tile.alpha_composite(g_res, (off, off))
            tile.alpha_composite(fx_fr.resize((68, 68), Image.Resampling.LANCZOS), (0, 0))
            if dir_ov is not None:
                tile.alpha_composite(dir_ov.resize((68, 68), Image.Resampling.LANCZOS), (0, 0))
            prev.paste(tile, (8 + c * cell, 8 + r * cell))

    prev_path = os.path.join(SRC_DIR, "anim_fx_preview.png")
    prev.save(prev_path)
    print(f"Saved 6-shape outer FX preview: {prev_path}")


if __name__ == "__main__":
    main()
