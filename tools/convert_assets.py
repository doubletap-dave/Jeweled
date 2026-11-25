#!/usr/bin/env python3
"""
Convert raw PNG assets in assets_src/ to WoW-ready uncompressed 32-bit TGA files
under Jeweled/Media/, and generate assets_src/contact_sheet_64px.png for consistency review.

Modes per asset:
  - 'gem':      extracts clean alpha if background is opaque black (edge BFS flood-fill
                with soft edge feather), crops tightly to subject, centers in square canvas.
  - 'additive': converts black-background glowing sprite to smooth luminance-based alpha
                with un-premultiplied glow color so it composites cleanly over any background.
  - 'opaque':   keeps opaque 32-bit TGA (alpha=255), resized cleanly to power-of-two.
"""

import collections
import os
import sys
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, "assets_src")
MEDIA_DIR = os.path.join(ROOT, "Jeweled", "Media")

# (src_stem, rel_tga_path, (w, h), mode)
MANIFEST = [
    # Azeroth gems (6)
    ("azeroth_ruby",      "gems/azeroth/ruby.tga",      (128, 128), "gem"),
    ("azeroth_sapphire",  "gems/azeroth/sapphire.tga",  (128, 128), "gem"),
    ("azeroth_emerald",   "gems/azeroth/emerald.tga",   (128, 128), "gem"),
    ("azeroth_topaz",     "gems/azeroth/topaz.tga",     (128, 128), "gem"),
    ("azeroth_amethyst",  "gems/azeroth/amethyst.tga",  (128, 128), "gem"),
    ("azeroth_diamond",   "gems/azeroth/diamond.tga",   (128, 128), "gem"),
    # Polestar gems (6)
    ("polestar_gold",      "gems/polestar/gold.tga",      (128, 128), "gem"),
    ("polestar_starlight", "gems/polestar/starlight.tga", (128, 128), "gem"),
    ("polestar_void",      "gems/polestar/void.tga",      (128, 128), "gem"),
    ("polestar_silver",    "gems/polestar/silver.tga",    (128, 128), "gem"),
    ("polestar_ember",     "gems/polestar/ember.tga",     (128, 128), "gem"),
    ("polestar_aurora",    "gems/polestar/aurora.tga",    (128, 128), "gem"),
    # Specials (4)
    ("special_line_h",    "gems/special/line_h.tga",    (128, 128), "additive"),
    ("special_line_v",    "gems/special/line_v.tga",    (128, 128), "additive"),
    ("special_blast",     "gems/special/blast.tga",     (128, 128), "additive"),
    ("special_prismatic", "gems/special/prismatic.tga", (128, 128), "gem"),
    # Icon (1)
    ("icon",              "icon.tga",                   (64, 64),   "gem"),
    # Backgrounds (3)
    ("bg_nightsky",       "backgrounds/nightsky.tga",    (512, 512), "opaque"),
    ("bg_deepmine",       "backgrounds/deepmine.tga",    (512, 512), "opaque"),
    ("bg_arcanevault",    "backgrounds/arcanevault.tga", (512, 512), "opaque"),
    # Effect sprites (5) + badge (1)
    ("fx_sparkle",        "fx/sparkle.tga",             (128, 128), "additive"),
    ("fx_ring",           "fx/ring.tga",                (256, 256), "additive"),
    ("fx_beam",           "fx/beam.tga",                (256, 64),  "additive"),
    ("fx_bolt",           "fx/bolt.tga",                (128, 256), "additive"),
    ("fx_star",           "fx/star.tga",                (32, 32),   "additive"),
    ("fx_badge",          "fx/badge.tga",               (64, 64),   "badge"),
]


def has_real_transparency(img):
    rgba = img.convert("RGBA")
    w, h = rgba.size
    corners = [rgba.getpixel((0, 0))[3], rgba.getpixel((w - 1, 0))[3],
               rgba.getpixel((0, h - 1))[3], rgba.getpixel((w - 1, h - 1))[3]]
    return sum(1 for a in corners if a < 20) >= 3


def remove_black_bg_bfs(img, low_thresh=18, high_thresh=44):
    """Remove contiguous dark background from image edges while preserving dark interior facets."""
    rgba = img.convert("RGBA")
    if has_real_transparency(rgba):
        return rgba
    w, h = rgba.size
    px = rgba.load()

    # Sample average background from corners
    corners = [px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1]]
    bg_r = sum(c[0] for c in corners) / 4.0
    bg_g = sum(c[1] for c in corners) / 4.0
    bg_b = sum(c[2] for c in corners) / 4.0

    def dist(r, g, b):
        return max(abs(r - bg_r), abs(g - bg_g), abs(b - bg_b))

    bg_mask = bytearray(w * h)
    q = collections.deque()

    for x in range(w):
        for y in (0, h - 1):
            r, g, b, _ = px[x, y]
            if dist(r, g, b) <= high_thresh:
                idx = y * w + x
                if not bg_mask[idx]:
                    bg_mask[idx] = 1
                    q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            r, g, b, _ = px[x, y]
            if dist(r, g, b) <= high_thresh:
                idx = y * w + x
                if not bg_mask[idx]:
                    bg_mask[idx] = 1
                    q.append((x, y))

    while q:
        x, y = q.popleft()
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h:
                nidx = ny * w + nx
                if not bg_mask[nidx]:
                    r, g, b, _ = px[nx, ny]
                    if dist(r, g, b) <= low_thresh:
                        bg_mask[nidx] = 1
                        q.append((nx, ny))

    # Apply mask + 1-pixel soft feather on boundary
    for y in range(h):
        for x in range(w):
            idx = y * w + x
            r, g, b, a = px[x, y]
            if bg_mask[idx]:
                px[x, y] = (0, 0, 0, 0)
            else:
                d = dist(r, g, b)
                if d < high_thresh:
                    # Check if adjacent to background
                    adj = False
                    for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                        if 0 <= nx < w and 0 <= ny < h and bg_mask[ny * w + nx]:
                            adj = True
                            break
                    if adj:
                        alpha = int(255 * max(0.0, min(1.0, (d - low_thresh) / max(high_thresh - low_thresh, 1))))
                        px[x, y] = (r, g, b, alpha)
    return rgba


def remove_black_badge(img):
    """For hollow wreath badge: clear both outer AND inner black regions cleanly."""
    rgba = img.convert("RGBA")
    if has_real_transparency(rgba):
        return rgba
    w, h = rgba.size
    px = rgba.load()
    for y in range(h):
        for x in range(w):
            r, g, b, _ = px[x, y]
            v = max(r, g, b)
            if v <= 16:
                px[x, y] = (0, 0, 0, 0)
            elif v < 52:
                a = int(255 * (v - 16) / 36.0)
                scale = 255.0 / max(v, 1)
                px[x, y] = (min(255, int(r * scale * 0.85)), min(255, int(g * scale * 0.85)), min(255, int(b * scale * 0.85)), a)
    return rgba


def black_to_additive_alpha(img):
    """Convert black-background glow/beam/bolt sprite to clean smooth alpha."""
    rgba = img.convert("RGBA")
    if has_real_transparency(rgba):
        return rgba
    w, h = rgba.size
    px = rgba.load()
    for y in range(h):
        for x in range(w):
            r, g, b, _ = px[x, y]
            m = max(r, g, b)
            if m <= 8:
                px[x, y] = (0, 0, 0, 0)
            else:
                # Smoothly un-premultiply glow so bright core stays vivid and edges feather softly
                a = min(255, int(((m - 8) / 247.0) ** 0.82 * 255))
                boost = min(2.2, 255.0 / max(m, 1))
                nr = min(255, int(r * boost))
                ng = min(255, int(g * boost))
                nb = min(255, int(b * boost))
                px[x, y] = (nr, ng, nb, a)
    return rgba


def fit_centered(rgba, target_size, fill_ratio=0.88):
    tw, th = target_size
    bbox = rgba.getbbox()
    if bbox:
        cropped = rgba.crop(bbox)
    else:
        cropped = rgba
    cw, ch = cropped.size
    max_w = max(1, int(tw * fill_ratio))
    max_h = max(1, int(th * fill_ratio))
    scale = min(max_w / cw, max_h / ch)
    nw = max(1, int(round(cw * scale)))
    nh = max(1, int(round(ch * scale)))
    resized = cropped.resize((nw, nh), Image.Resampling.LANCZOS)
    out = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    out.paste(resized, ((tw - nw) // 2, (th - nh) // 2), resized)
    return out


def find_source_file(src_stem):
    for ext in (".png", ".jpg", ".jpeg"):
        p = os.path.join(SRC_DIR, src_stem + ext)
        if os.path.exists(p):
            return p
    raise FileNotFoundError(f"Missing source image for {src_stem} (.png/.jpg)")


def convert_one(src_stem, rel_tga, size, mode):
    src_path = find_source_file(src_stem)
    out_path = os.path.join(MEDIA_DIR, rel_tga)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    img = Image.open(src_path)
    if mode == "opaque":
        out = img.convert("RGBA").resize(size, Image.Resampling.LANCZOS)
        # Ensure opaque alpha
        r, g, b, _ = out.split()
        a = Image.new("L", size, 255)
        out = Image.merge("RGBA", (r, g, b, a))
    elif mode == "gem":
        if src_stem == "icon":
            # Strip the soft outer dark-amber glow halo around the crisp dark-navy chamfered square bezel
            clean = remove_black_bg_bfs(img, low_thresh=88, high_thresh=106)
        else:
            low_t = 34 if src_stem == "azeroth_ruby" else 22
            high_t = 62 if src_stem == "azeroth_ruby" else 46
            clean = remove_black_bg_bfs(img, low_thresh=low_t, high_thresh=high_t)
        out = fit_centered(clean, size, fill_ratio=0.88)
    elif mode == "badge":
        clean = remove_black_badge(img)
        out = fit_centered(clean, size, fill_ratio=0.90)
    elif mode == "additive":
        clean = black_to_additive_alpha(img)
        # Beams and bolts stretch across frame; keep aspect when cropping
        fill = 0.96 if (size[0] != size[1] or "line_" in src_stem) else 0.90
        out = fit_centered(clean, size, fill_ratio=fill)
    else:
        raise ValueError(f"Unknown mode: {mode}")

    # Save uncompressed 32-bit TGA (most reliable format for WoW clients)
    out.save(out_path, format="TGA", compression=None)
    return out_path


def build_contact_sheet():
    """Create a 64px side-by-side contact sheet on dark & light panels for visual QA."""
    cell = 76
    cols = 6
    rows = 4
    w = cols * cell + 24
    h = rows * cell + 36
    sheet = Image.new("RGBA", (w, h), (24, 29, 45, 255))
    draw = ImageDraw.Draw(sheet)

    row_items = [
        ["gems/azeroth/ruby.tga", "gems/azeroth/sapphire.tga", "gems/azeroth/emerald.tga",
         "gems/azeroth/topaz.tga", "gems/azeroth/amethyst.tga", "gems/azeroth/diamond.tga"],
        ["gems/polestar/gold.tga", "gems/polestar/starlight.tga", "gems/polestar/void.tga",
         "gems/polestar/silver.tga", "gems/polestar/ember.tga", "gems/polestar/aurora.tga"],
        ["gems/special/line_h.tga", "gems/special/line_v.tga", "gems/special/blast.tga",
         "gems/special/prismatic.tga", "icon.tga", "fx/badge.tga"],
        ["fx/sparkle.tga", "fx/ring.tga", "fx/beam.tga",
         "fx/bolt.tga", "fx/star.tga", "icon.tga"],
    ]

    for r, items in enumerate(row_items):
        for c, rel in enumerate(items):
            x = 12 + c * cell
            y = 18 + r * cell
            # Last cell in row 4 tests icon on a light panel
            bg_col = (235, 238, 244, 255) if (r == 3 and c == 5) else (16, 20, 32, 255)
            draw.rectangle([x + 2, y + 2, x + 70, y + 70], fill=bg_col, outline=(60, 72, 102, 255))
            tga_path = os.path.join(MEDIA_DIR, rel)
            if os.path.exists(tga_path):
                im = Image.open(tga_path).convert("RGBA")
                im.thumbnail((64, 64), Image.Resampling.LANCZOS)
                sheet.alpha_composite(im, (x + 4 + (64 - im.width) // 2, y + 4 + (64 - im.height) // 2))

    out_sheet = os.path.join(SRC_DIR, "contact_sheet_64px.png")
    sheet.save(out_sheet)
    print(f"Saved contact sheet: {out_sheet}")


def main():
    converted = 0
    missing = []
    for src_stem, rel_tga, size, mode in MANIFEST:
        try:
            convert_one(src_stem, rel_tga, size, mode)
            converted += 1
        except FileNotFoundError:
            missing.append(src_stem)
    print(f"Converted {converted}/{len(MANIFEST)} TGA assets.")
    if missing:
        print("Missing source PNGs:", ", ".join(missing))
        sys.exit(1)
    build_contact_sheet()


if __name__ == "__main__":
    main()
