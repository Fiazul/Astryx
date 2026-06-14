#!/usr/bin/env python3
# Temp generator for a smooth, soft UI CLICK -> assets/ui_click.wav
# A short blip: a quick pitch-dropping sine with a fast attack + smooth decay
# (no harsh transient), so clicking feels satisfying and gentle.
import math, struct, wave, os

SR = 44100
DUR = 0.09
N = int(SR * DUR)
samples = []
for i in range(N):
    t = i / SR
    p = t / DUR
    freq = 1300.0 - 500.0 * p          # gentle downward chirp
    env = math.sin(math.pi * p) ** 0.8 # smooth fade in/out, no click-edge
    s = math.sin(2 * math.pi * freq * t) * env
    s += 0.3 * math.sin(2 * math.pi * freq * 2.0 * t) * env   # soft harmonic sparkle
    samples.append(s)

peak = max(abs(x) for x in samples) or 1.0
gain = 0.7 / peak
data = b"".join(struct.pack("<h", int(max(-1, min(1, x * gain)) * 32767)) for x in samples)
out = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "assets", "ui_click.wav"))
with wave.open(out, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(data)
print("wrote", out, "(%.0fms)" % (DUR * 1000))
