#!/usr/bin/env python3
"""
Verify all 26 TGA art assets and 16 quiet OGG sound assets for Jeweled.
Checks:
  - Exact file existence
  - Valid uncompressed TGA header, exact power-of-two dimensions, alpha presence where required
  - Valid Ogg Vorbis 44.1 kHz mono via ffprobe/ffmpeg, peak <= -5.0 dBFS, total payload < 500 KB
"""

import os
import re
import struct
import subprocess
import sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA_DIR = os.path.join(ROOT, "Jeweled", "Media")

EXPECTED_TGAS = [
    ("gems/azeroth/ruby.tga",      (128, 128), True),
    ("gems/azeroth/sapphire.tga",  (128, 128), True),
    ("gems/azeroth/emerald.tga",   (128, 128), True),
    ("gems/azeroth/topaz.tga",     (128, 128), True),
    ("gems/azeroth/amethyst.tga",  (128, 128), True),
    ("gems/azeroth/diamond.tga",   (128, 128), True),
    ("gems/polestar/gold.tga",      (128, 128), True),
    ("gems/polestar/starlight.tga", (128, 128), True),
    ("gems/polestar/void.tga",      (128, 128), True),
    ("gems/polestar/silver.tga",    (128, 128), True),
    ("gems/polestar/ember.tga",     (128, 128), True),
    ("gems/polestar/aurora.tga",    (128, 128), True),
    ("gems/special/line_h.tga",    (128, 128), True),
    ("gems/special/line_v.tga",    (128, 128), True),
    ("gems/special/blast.tga",     (128, 128), True),
    ("gems/special/prismatic.tga", (128, 128), True),
    ("icon.tga",                   (64, 64),   True),
    ("backgrounds/nightsky.tga",    (512, 512), False),
    ("backgrounds/deepmine.tga",    (512, 512), False),
    ("backgrounds/arcanevault.tga", (512, 512), False),
    ("fx/sparkle.tga",             (128, 128), True),
    ("fx/ring.tga",                (256, 256), True),
    ("fx/beam.tga",                (256, 64),  True),
    ("fx/bolt.tga",                (128, 256), True),
    ("fx/star.tga",                (32, 32),   True),
    ("fx/badge.tga",               (64, 64),   True),
    ("fx/glint.tga",               (128, 128), True),
    ("fx/shard.tga",               (64, 64),   True),
    ("fx/anim_prism.tga",          (512, 256), True),
    ("fx/chev_h.tga",              (128, 128), True),
    ("fx/chev_v.tga",              (128, 128), True),
    ("fx/fire_1.tga",              (256, 128), True),
    ("fx/fire_2.tga",              (256, 128), True),
    ("fx/fire_3.tga",              (256, 128), True),
    ("fx/fire_4.tga",              (256, 128), True),
    ("fx/fire_5.tga",              (256, 128), True),
    ("fx/fire_6.tga",              (256, 128), True),
    ("fx/bolt_h_1.tga",            (256, 128), True),
    ("fx/bolt_h_2.tga",            (256, 128), True),
    ("fx/bolt_h_3.tga",            (256, 128), True),
    ("fx/bolt_h_4.tga",            (256, 128), True),
    ("fx/bolt_h_5.tga",            (256, 128), True),
    ("fx/bolt_h_6.tga",            (256, 128), True),
    ("fx/bolt_v_1.tga",            (256, 128), True),
    ("fx/bolt_v_2.tga",            (256, 128), True),
    ("fx/bolt_v_3.tga",            (256, 128), True),
    ("fx/bolt_v_4.tga",            (256, 128), True),
    ("fx/bolt_v_5.tga",            (256, 128), True),
    ("fx/bolt_v_6.tga",            (256, 128), True),
]

EXPECTED_OGGS = [
    "swap.ogg", "error.ogg",
    "match1.ogg", "match2.ogg", "match3.ogg", "cascade4.ogg", "cascade5.ogg",
    "special_line.ogg", "special_blast.ogg", "special_prism.ogg",
    "reshuffle.ogg", "click.ogg", "record.ogg", "achievement.ogg", "go.ogg", "land.ogg",
]


def is_pow2(n):
    return n > 0 and (n & (n - 1)) == 0


def check_tgas():
    errors = []
    for rel, expected_size, needs_alpha in EXPECTED_TGAS:
        path = os.path.join(MEDIA_DIR, rel)
        if not os.path.exists(path):
            errors.append(f"MISSING TGA: {rel}")
            continue
        with open(path, "rb") as f:
            hdr = f.read(18)
        if len(hdr) < 18:
            errors.append(f"CORRUPT TGA header: {rel}")
            continue
        image_type = hdr[2]
        width, height, bpp = struct.unpack("<HHB", hdr[12:17])
        if image_type != 2:
            errors.append(f"NON-UNCOMPRESSED TGA (type={image_type}): {rel}")
        if (width, height) != expected_size:
            errors.append(f"WRONG SIZE {width}x{height} != {expected_size}: {rel}")
        if not (is_pow2(width) and is_pow2(height)):
            errors.append(f"NOT POW2: {rel}")
        if bpp != 32:
            errors.append(f"BPP {bpp} != 32: {rel}")

        im = Image.open(path).convert("RGBA")
        alpha_band = im.getchannel("A")
        amin, amax = alpha_band.getextrema()
        if needs_alpha:
            if amin > 15:
                errors.append(f"NO TRANSPARENCY (min_alpha={amin}): {rel}")
            if amax < 180:
                errors.append(f"EMPTY/FAINT IMAGE (max_alpha={amax}): {rel}")
        else:
            if amin < 250:
                errors.append(f"OPAQUE BG HAS TRANSPARENCY (min_alpha={amin}): {rel}")
    return errors


def check_oggs():
    errors = []
    total_bytes = 0
    for name in EXPECTED_OGGS:
        path = os.path.join(MEDIA_DIR, "snd", name)
        if not os.path.exists(path):
            errors.append(f"MISSING OGG: {name}")
            continue
        total_bytes += os.path.getsize(path)
        proc = subprocess.run(
            ["ffmpeg", "-i", path, "-af", "volumedetect", "-f", "null", "-"],
            capture_output=True, text=True
        )
        stderr = proc.stderr
        if "Audio: vorbis" not in stderr:
            errors.append(f"NOT VORBIS: {name}")
        if "44100 Hz, mono" not in stderr:
            errors.append(f"NOT 44100 Hz mono: {name}")
        m = re.search(r"max_volume:\s*(-?[0-9.]+)\s*dB", stderr)
        if m:
            max_db = float(m.group(1))
            if max_db > -5.0:
                errors.append(f"TOO LOUD ({max_db:.1f} dB > -5.0 dB): {name}")
        else:
            errors.append(f"COULD NOT DETECT VOLUME: {name}")
    if total_bytes > 500 * 1024:
        errors.append(f"SOUND PAYLOAD TOO LARGE: {total_bytes/1024:.1f} KB > 500 KB")
    return errors, total_bytes


def main():
    tga_errs = check_tgas()
    ogg_errs, total_audio = check_oggs()

    print(f"TGA check: {len(EXPECTED_TGAS) - len(tga_errs)}/{len(EXPECTED_TGAS)} passed")
    print(f"OGG check: {len(EXPECTED_OGGS) - len(ogg_errs)}/{len(EXPECTED_OGGS)} passed (total {total_audio/1024:.1f} KB / 500 KB)")

    all_errs = tga_errs + ogg_errs
    if all_errs:
        print("\nFAILURES:")
        for e in all_errs:
            print("  -", e)
        sys.exit(1)
    print("\nALL ASSETS VERIFIED OK")


if __name__ == "__main__":
    main()
