#!/usr/bin/env python3
# Generator for the capture-reward fanfare ("happy" chime) -> assets/reward.wav
# A bright rising major arpeggio (C-E-G-C) with a shimmer + soft bell decay — a quick,
# cheerful "you did it!" sting for capturing a body. Pure stdlib.
import math, struct, wave, os

SR = 44100
DUR = 0.9
N = int(SR * DUR)
# Ascending major arpeggio: note (Hz) and start fraction.
notes = [(523.25, 0.00), (659.25, 0.12), (783.99, 0.24), (1046.50, 0.38)]
samples = []
for i in range(N):
    t = i / SR
    s = 0.0
    for freq, start in notes:
        lt = t - start * DUR
        if lt < 0.0:
            continue
        env = math.exp(-lt * 3.2)                      # gentle bell decay
        s += math.sin(2 * math.pi * freq * lt) * env
        s += 0.3 * math.sin(2 * math.pi * freq * 2.0 * lt) * env   # shimmer
        s += 0.15 * math.sin(2 * math.pi * freq * 3.0 * lt) * env
    samples.append(s)

peak = max(abs(x) for x in samples) or 1.0
gain = 0.85 / peak
data = b"".join(struct.pack("<h", int(max(-1, min(1, x * gain)) * 32767)) for x in samples)
out = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "assets", "reward.wav"))
with wave.open(out, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(data)
print("wrote", out, "(%.0fms)" % (DUR * 1000))
