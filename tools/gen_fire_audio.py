#!/usr/bin/env python3
# Generator for the ray-bullet FIRE "zap" -> assets/sfx_fire.wav
# A crisp laser shot to match the hitscan ray bullets: a bright noise crack on the
# attack, then a fast EXPONENTIAL downward pitch sweep (the classic "pew") with a
# snappy decay. Punchier + more electric than the old sample. Pure stdlib.
import math, struct, wave, os, random

SR = 44100
DUR = 0.12
N = int(SR * DUR)
random.seed(11)
samples = []
phase = 0.0
for i in range(N):
    t = i / SR
    p = t / DUR
    # Exponential pitch drop 1900 -> 320 Hz: fast at the start = the "pew" snap.
    freq = 320.0 + 1580.0 * math.exp(-7.0 * p)
    phase += 2 * math.pi * freq / SR        # integrate freq so the sweep is smooth
    tone = math.sin(phase)
    tone += 0.35 * math.sin(2.0 * phase)    # harmonic for an electric edge
    env = (1.0 - p) ** 2.2                   # instant attack, snappy decay
    s = tone * env
    if p < 0.06:                             # bright noise crack on the attack
        s += random.uniform(-1.0, 1.0) * 0.6 * (1.0 - p / 0.06)
    samples.append(s)

peak = max(abs(x) for x in samples) or 1.0
gain = 0.85 / peak
data = b"".join(struct.pack("<h", int(max(-1, min(1, x * gain)) * 32767)) for x in samples)
out = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "assets", "sfx_fire.wav"))
with wave.open(out, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(data)
print("wrote", out, "(%.0fms)" % (DUR * 1000))
