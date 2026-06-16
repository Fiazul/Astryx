#!/usr/bin/env python3
# Generator for the tutorial-notification chime ("ting-tong") -> assets/notify.wav
# Two soft bell tones: a higher "ting" then a lower "tong", each a quick-decay sine with
# a harmonic shimmer, so a new tip announcing itself is pleasant, not jarring. Pure stdlib.
import math, struct, wave, os

SR = 44100
DUR = 0.55
N = int(SR * DUR)
# Two notes (Hz) and when each starts (fraction of DUR): ting (high) then tong (lower).
notes = [(1320.0, 0.00), (880.0, 0.42)]
samples = []
for i in range(N):
    t = i / SR
    s = 0.0
    for freq, start in notes:
        lt = t - start * DUR
        if lt < 0.0:
            continue
        env = math.exp(-lt * 9.0)                 # fast bell decay
        s += math.sin(2 * math.pi * freq * lt) * env
        s += 0.3 * math.sin(2 * math.pi * freq * 2.0 * lt) * env   # shimmer
    samples.append(s)

peak = max(abs(x) for x in samples) or 1.0
gain = 0.8 / peak
data = b"".join(struct.pack("<h", int(max(-1, min(1, x * gain)) * 32767)) for x in samples)
out = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "assets", "notify.wav"))
with wave.open(out, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(data)
print("wrote", out, "(%.0fms)" % (DUR * 1000))
