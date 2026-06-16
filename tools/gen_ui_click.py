#!/usr/bin/env python3
# Generator for a crisp, short UI CLICK -> assets/ui_click.wav
# A sharp little "tick": a fast pitch-dropping blip with a quick noise transient
# at the very front (the clicky attack) and a fast decay, so each button/menu
# press reads as a snappy "click" rather than a soft chirp. Pure stdlib.
import math, struct, wave, os, random

SR = 44100
DUR = 0.045                 # very short -> snappy
N = int(SR * DUR)
random.seed(3)
samples = []
for i in range(N):
    t = i / SR
    p = t / DUR
    freq = 2100.0 - 1200.0 * p              # quick downward chirp -> "tick"
    env = (1.0 - p) ** 1.6                   # fast attack, fast decay
    s = math.sin(2 * math.pi * freq * t) * env
    s += 0.25 * math.sin(2 * math.pi * freq * 2.0 * t) * env   # harmonic sparkle
    if p < 0.12:                             # tiny noise transient = the clicky edge
        s += random.uniform(-1.0, 1.0) * 0.5 * (1.0 - p / 0.12)
    samples.append(s)

peak = max(abs(x) for x in samples) or 1.0
gain = 0.75 / peak
data = b"".join(struct.pack("<h", int(max(-1, min(1, x * gain)) * 32767)) for x in samples)
out = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "assets", "ui_click.wav"))
with wave.open(out, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(data)
print("wrote", out, "(%.0fms)" % (DUR * 1000))
