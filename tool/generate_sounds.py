#!/usr/bin/env python3
"""Synthesizes LinkMesh's notification sounds. Pure Python, no dependencies.

  message_chime.wav  - two-note glass chime (D6 -> A6, a rising fifth)
  sos_alert.wav      - "... --- ..." in Morse, bright two-tone beeps, played twice

Output: 48 kHz / 16-bit / mono WAV, peak-normalised to -1 dBFS, with
click-free envelopes, a short room reverb and TPDF dither.

    python3 tool/generate_sounds.py
"""
import math
import os
import random
import struct
import wave

SR = 48_000
ROOT = os.path.join(os.path.dirname(__file__), "..")
# Android notification channels read res/raw; iOS reads the Flutter asset;
# the website plays the docs copy.
OUTS = [
    os.path.join(ROOT, "android", "app", "src", "main", "res", "raw"),
    os.path.join(ROOT, "assets", "sounds"),
    os.path.join(ROOT, "docs", "sounds"),
]


def silence(seconds):
    return [0.0] * int(seconds * SR)


def mix_into(buf, sound, at_seconds, gain=1.0):
    start = int(at_seconds * SR)
    need = start + len(sound)
    if need > len(buf):
        buf.extend([0.0] * (need - len(buf)))
    for i, s in enumerate(sound):
        buf[start + i] += s * gain


def bell(freq, seconds, decay=0.42, bright=1.0):
    """FM bell: inharmonic modulator, index decaying faster than amplitude,
    so the strike is shimmery and the tail settles into a pure tone."""
    n = int(seconds * SR)
    out = []
    ratio = 1.4                       # inharmonic -> glass/bell character
    for i in range(n):
        t = i / SR
        attack = min(1.0, t / 0.003)  # 3 ms, avoids a click
        amp = attack * math.exp(-t / decay)
        index = bright * 2.2 * math.exp(-t / 0.08)
        mod = index * math.sin(2 * math.pi * freq * ratio * t)
        body = math.sin(2 * math.pi * freq * t + mod)
        # Soft octave-below partial for warmth, and a faint 2.76x "glass" partial.
        warm = 0.18 * math.sin(2 * math.pi * freq * 0.5 * t) * math.exp(-t / (decay * 1.4))
        glass = 0.10 * math.sin(2 * math.pi * freq * 2.76 * t) * math.exp(-t / 0.06)
        out.append(amp * (body + glass) + attack * warm)
    return out


def beep(seconds, f1=880.0, f2=1318.5):
    """Bright alarm beep: two tones a fifth apart with a few odd harmonics,
    5 ms attack / 12 ms release so the Morse rhythm stays crisp but clean."""
    n = int(seconds * SR)
    out = []
    for i in range(n):
        t = i / SR
        env = min(1.0, t / 0.005, (seconds - t) / 0.012)
        s = 0.0
        for f, g in ((f1, 1.0), (f2, 0.7)):
            s += g * (math.sin(2 * math.pi * f * t)
                      + 0.30 * math.sin(2 * math.pi * 3 * f * t)
                      + 0.12 * math.sin(2 * math.pi * 5 * f * t))
        out.append(max(0.0, env) * s)
    return out


def reverb(dry, wet=0.18, seconds_tail=0.6):
    """Small Schroeder room: 4 parallel combs into 2 allpasses."""
    x = dry + [0.0] * int(seconds_tail * SR)
    combs = [(1557, 0.80), (1617, 0.79), (1491, 0.78), (1422, 0.77)]
    acc = [0.0] * len(x)
    for delay, fb in combs:
        d = int(delay * SR / 44_100)
        buf = [0.0] * d
        idx = 0
        for i, s in enumerate(x):
            y = buf[idx]
            buf[idx] = s + y * fb
            idx = (idx + 1) % d
            acc[i] += y * 0.25
    for delay, g in ((225, 0.5), (556, 0.5)):
        d = int(delay * SR / 44_100)
        buf = [0.0] * d
        idx = 0
        out = []
        for s in acc:
            b = buf[idx]
            y = -s * g + b
            buf[idx] = s + b * g
            idx = (idx + 1) % d
            out.append(y)
        acc = out
    return [(1 - wet) * d + wet * w for d, w in zip(x, acc)]


def finish(samples, fade_out=0.08, peak_db=-1.0):
    # Trim trailing near-silence, fade, normalise, dither, quantise.
    end = len(samples)
    while end > 0 and abs(samples[end - 1]) < 1e-4:
        end -= 1
    samples = samples[:end]
    fade = int(fade_out * SR)
    for i in range(fade):
        samples[-1 - i] *= i / fade
    peak = max(abs(s) for s in samples) or 1.0
    gain = 10 ** (peak_db / 20) / peak
    rnd = random.Random(7)
    pcm = []
    for s in samples:
        dither = (rnd.random() - rnd.random()) / 32768
        v = max(-1.0, min(1.0, s * gain + dither))
        pcm.append(int(round(v * 32767)))
    return pcm


def write(name, pcm):
    for out in OUTS:
        os.makedirs(out, exist_ok=True)
        path = os.path.join(out, name)
        with wave.open(path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(struct.pack(f"<{len(pcm)}h", *pcm))
    rms = math.sqrt(sum(p * p for p in pcm) / len(pcm)) / 32768
    print(f"{path}: {len(pcm) / SR:.2f}s, rms {20 * math.log10(rms):.1f} dBFS")


def message_chime():
    buf = silence(0.05)
    mix_into(buf, bell(1174.66, 0.9), 0.0, 0.8)    # D6
    mix_into(buf, bell(1760.00, 1.1), 0.095, 1.0)  # A6
    return finish(reverb(buf, wet=0.16))


def sos_alert():
    u = 0.075                       # Morse unit
    pattern = "... --- ..."
    buf = []
    t = 0.0
    for rep in range(2):
        for ch in pattern:
            if ch == " ":
                t += 2 * u          # letter gap is 3u (1u already added)
                continue
            length = u if ch == "." else 3 * u
            mix_into(buf, beep(length), t)
            t += length + u
        t += 0.45                   # pause between repeats
    return finish(reverb(buf, wet=0.10, seconds_tail=0.4), fade_out=0.05)


if __name__ == "__main__":
    write("message_chime.wav", message_chime())
    write("sos_alert.wav", sos_alert())
