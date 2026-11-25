#!/usr/bin/env python3
"""
Synthesize all 16 quiet CC0 .ogg sound effects for Jeweled (WoW Forever 1.60.1).
Specs (§7.12):
  - Ogg Vorbis (.ogg), mono, 44.1 kHz
  - Normalized quiet (peak around -6 dBFS, deliberately soft — especially go.ogg)
  - Event sounds < 0.5s, jingles < 2.0s, total payload < 500 KB
Uses only Python stdlib + ffmpeg.
"""

import math
import os
import random
import struct
import subprocess
import tempfile
import wave

SAMPLE_RATE = 44100
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Jeweled", "Media", "snd")

# Peak amplitude target: -6 dBFS => 10^(-6/20) ~= 0.501 (keep slightly under -6 dBFS so Ogg peaks stay safe)
TARGET_PEAK = 0.45


def env_ad(t, attack, decay):
    if t < 0:
        return 0.0
    if attack > 0 and t < attack:
        return t / attack
    return math.exp(-(t - attack) / max(decay, 1e-4))


def bell_tone(freq, dur, attack=0.004, decay=0.14, shimmer=0.25, gain=1.0):
    """Warm crystalline gemstone chime using pure sine + harmonic overtones."""
    n = int(SAMPLE_RATE * dur)
    buf = [0.0] * n
    for i in range(n):
        t = i / SAMPLE_RATE
        e1 = env_ad(t, attack, decay)
        e2 = env_ad(t, attack, decay * 0.55)
        e3 = env_ad(t, attack, decay * 0.25)
        # Fundamental + octave + crystalline fifth overtone
        s = (
            0.70 * math.sin(2.0 * math.pi * freq * t) * e1
            + 0.22 * math.sin(2.0 * math.pi * freq * 2.0 * t) * e2
            + shimmer * 0.14 * math.sin(2.0 * math.pi * freq * 3.01 * t) * e3
        )
        buf[i] = s * gain
    return buf


def mix_into(dest, src, offset_sec=0.0, gain=1.0):
    start = int(offset_sec * SAMPLE_RATE)
    end = start + len(src)
    if end > len(dest):
        dest.extend([0.0] * (end - len(dest)))
    for i, v in enumerate(src):
        idx = start + i
        if idx >= 0:
            dest[idx] += v * gain


def normalize_and_fade(buf, target_peak=TARGET_PEAK, fade_out=0.015):
    peak = max((abs(x) for x in buf), default=0.0)
    if peak > 1e-9:
        scale = target_peak / peak
        buf = [x * scale for x in buf]
    fade_n = min(len(buf), int(fade_out * SAMPLE_RATE))
    for i in range(fade_n):
        buf[len(buf) - 1 - i] *= i / max(fade_n, 1)
    return buf


def gen_swap():
    """Soft glassy click-slide, ~0.14s."""
    dur = 0.14
    n = int(SAMPLE_RATE * dur)
    buf = [0.0] * n
    rng = random.Random(101)
    lp = 0.0
    for i in range(n):
        t = i / SAMPLE_RATE
        # Subtle upward pitch glide + tiny glass click
        freq = 540.0 + 380.0 * (t / dur)
        e = env_ad(t, 0.003, 0.045)
        noise = rng.uniform(-1.0, 1.0)
        lp = 0.78 * lp + 0.22 * noise
        buf[i] = (0.65 * math.sin(2.0 * math.pi * freq * t) + 0.35 * lp) * e
    return normalize_and_fade(buf, target_peak=0.32)


def gen_error():
    """Soft dull low thud, ~0.16s."""
    dur = 0.16
    n = int(SAMPLE_RATE * dur)
    buf = [0.0] * n
    for i in range(n):
        t = i / SAMPLE_RATE
        freq = 165.0 - 55.0 * (t / dur)
        e = env_ad(t, 0.005, 0.055)
        buf[i] = (math.sin(2.0 * math.pi * freq * t) + 0.35 * math.sin(2.0 * math.pi * freq * 1.48 * t)) * e
    return normalize_and_fade(buf, target_peak=0.35)


def gen_chime_seq(freqs, step_sec, note_dur, decay, peak=TARGET_PEAK, shimmer=0.25):
    total = step_sec * max(len(freqs) - 1, 0) + note_dur
    buf = [0.0] * int(SAMPLE_RATE * total)
    for idx, f in enumerate(freqs):
        tone = bell_tone(f, note_dur, attack=0.004, decay=decay, shimmer=shimmer)
        mix_into(buf, tone, idx * step_sec)
    return normalize_and_fade(buf, target_peak=peak)


def gen_special_line():
    """Short crystalline energy zap, ~0.30s."""
    dur = 0.30
    n = int(SAMPLE_RATE * dur)
    buf = [0.0] * n
    rng = random.Random(202)
    phase = 0.0
    for i in range(n):
        t = i / SAMPLE_RATE
        freq = 1500.0 * math.exp(-t * 4.5) + 420.0
        phase += 2.0 * math.pi * freq / SAMPLE_RATE
        e = env_ad(t, 0.004, 0.095)
        spark = rng.uniform(-1.0, 1.0) * 0.18 * env_ad(t, 0.002, 0.05)
        buf[i] = (0.72 * math.sin(phase) + 0.25 * math.sin(phase * 2.0)) * e + spark
    return normalize_and_fade(buf, target_peak=0.40)


def gen_special_blast():
    """Deep soft pop/boom + warm gold chime tail, ~0.38s."""
    dur = 0.38
    n = int(SAMPLE_RATE * dur)
    buf = [0.0] * n
    rng = random.Random(303)
    lp = 0.0
    phase = 0.0
    for i in range(n):
        t = i / SAMPLE_RATE
        freq = 150.0 * math.exp(-t * 9.0) + 52.0
        phase += 2.0 * math.pi * freq / SAMPLE_RATE
        e_sub = env_ad(t, 0.003, 0.11)
        lp = 0.88 * lp + 0.12 * rng.uniform(-1.0, 1.0)
        e_air = env_ad(t, 0.002, 0.07)
        buf[i] = 0.78 * math.sin(phase) * e_sub + 0.45 * lp * e_air
    mix_into(buf, bell_tone(587.33, 0.28, decay=0.09, gain=0.28), 0.02)
    return normalize_and_fade(buf, target_peak=0.43)


def gen_special_prism():
    """Shimmering rainbow arpeggio, ~0.58s."""
    freqs = [523.25, 659.25, 783.99, 1046.50, 1318.51, 1567.98]
    return gen_chime_seq(freqs, step_sec=0.055, note_dur=0.28, decay=0.14, peak=0.42, shimmer=0.45)


def gen_reshuffle():
    """Quick gentle crystalline shimmer wave, ~0.38s."""
    freqs = [440.0, 554.37, 659.25, 880.0, 659.25]
    return gen_chime_seq(freqs, step_sec=0.045, note_dur=0.18, decay=0.08, peak=0.33, shimmer=0.35)


def gen_click():
    """Soft UI tick, ~0.08s."""
    dur = 0.08
    n = int(SAMPLE_RATE * dur)
    buf = [0.0] * n
    for i in range(n):
        t = i / SAMPLE_RATE
        e = env_ad(t, 0.001, 0.018)
        buf[i] = (0.7 * math.sin(2.0 * math.pi * 1100.0 * t) + 0.3 * math.sin(2.0 * math.pi * 2400.0 * t)) * e
    return normalize_and_fade(buf, target_peak=0.28)


def gen_record():
    """Short triumphant warm fanfare, ~1.05s."""
    notes = [
        (523.25, 0.00, 0.35, 0.16),
        (659.25, 0.11, 0.35, 0.16),
        (783.99, 0.22, 0.40, 0.20),
        (1046.50, 0.36, 0.68, 0.30),
        (783.99, 0.36, 0.65, 0.28),
        (1318.51, 0.42, 0.60, 0.26),
    ]
    buf = [0.0] * int(SAMPLE_RATE * 1.05)
    for freq, off, dur, dec in notes:
        mix_into(buf, bell_tone(freq, dur, decay=dec, shimmer=0.35), off, 0.75)
    return normalize_and_fade(buf, target_peak=0.42)


def gen_achievement():
    """Warm WoW-inspired double bell ding, ~0.55s."""
    buf = [0.0] * int(SAMPLE_RATE * 0.55)
    mix_into(buf, bell_tone(880.0, 0.45, decay=0.18, shimmer=0.30), 0.00, 0.85)
    mix_into(buf, bell_tone(1318.51, 0.48, decay=0.22, shimmer=0.35), 0.07, 0.90)
    return normalize_and_fade(buf, target_peak=0.40)


def gen_go():
    """Bright single takeoff chime, DELIBERATELY QUIET (2008 fishing lesson), ~0.35s."""
    buf = bell_tone(783.99, 0.35, attack=0.008, decay=0.14, shimmer=0.20)
    mix_into(buf, bell_tone(1174.66, 0.30, attack=0.010, decay=0.11, shimmer=0.15), 0.03, 0.45)
    return normalize_and_fade(buf, target_peak=0.25)


def gen_land():
    """Short pleasant two-note landing jingle, ~0.80s."""
    buf = [0.0] * int(SAMPLE_RATE * 0.80)
    mix_into(buf, bell_tone(659.25, 0.40, decay=0.16, shimmer=0.22), 0.00, 0.85)
    mix_into(buf, bell_tone(523.25, 0.55, decay=0.24, shimmer=0.25), 0.18, 0.90)
    mix_into(buf, bell_tone(783.99, 0.55, decay=0.24, shimmer=0.20), 0.18, 0.55)
    return normalize_and_fade(buf, target_peak=0.36)


SOUNDS = {
    "swap": gen_swap,
    "error": gen_error,
    "match1": lambda: gen_chime_seq([523.25], 0.0, 0.28, 0.12, peak=0.36),
    "match2": lambda: gen_chime_seq([587.33, 739.99], 0.07, 0.28, 0.12, peak=0.38),
    "match3": lambda: gen_chime_seq([659.25, 783.99, 987.77], 0.065, 0.30, 0.13, peak=0.40),
    "cascade4": lambda: gen_chime_seq([659.25, 783.99, 987.77, 1174.66], 0.055, 0.32, 0.14, peak=0.42),
    "cascade5": lambda: gen_chime_seq([523.25, 659.25, 783.99, 1046.50, 1318.51], 0.05, 0.36, 0.18, peak=0.44, shimmer=0.40),
    "special_line": gen_special_line,
    "special_blast": gen_special_blast,
    "special_prism": gen_special_prism,
    "reshuffle": gen_reshuffle,
    "click": gen_click,
    "record": gen_record,
    "achievement": gen_achievement,
    "go": gen_go,
    "land": gen_land,
}


def write_ogg(samples, out_path):
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tf:
        wav_path = tf.name
    try:
        with wave.open(wav_path, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(SAMPLE_RATE)
            pcm = bytearray()
            for x in samples:
                clamped = max(-1.0, min(1.0, x))
                pcm.extend(struct.pack("<h", int(round(clamped * 32767))))
            wf.writeframes(bytes(pcm))
        cmd = [
            "ffmpeg", "-y", "-v", "error",
            "-i", wav_path,
            "-c:a", "libvorbis", "-q:a", "3",
            "-ac", "1", "-ar", str(SAMPLE_RATE),
            out_path,
        ]
        subprocess.run(cmd, check=True)
    finally:
        if os.path.exists(wav_path):
            os.remove(wav_path)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    total_bytes = 0
    for name, fn in SOUNDS.items():
        samples = fn()
        out_path = os.path.join(OUT_DIR, f"{name}.ogg")
        write_ogg(samples, out_path)
        size = os.path.getsize(out_path)
        total_bytes += size
        print(f"  {name}.ogg  ({len(samples)/SAMPLE_RATE:.2f}s, {size/1024:.1f} KB)")
    print(f"Generated {len(SOUNDS)} sounds, total {total_bytes/1024:.1f} KB")


if __name__ == "__main__":
    main()
