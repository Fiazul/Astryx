#!/usr/bin/env python3
# Temp generator for a seamless looping LASER BEAM hum -> assets/laser_loop.wav
# Smooth, comfortable ELECTRIC tone: pure sine partials with slightly detuned
# twins (gentle 1-2 Hz beating = a soft electric shimmer) and a faint high sparkle.
# 1.0s loop on a 1 Hz grid, so every partial is an integer freq and wraps clean.
import math, struct, wave, os

SR = 44100
LOOP = 1.0
N = int(SR * LOOP)
TAU = 2 * math.pi

# (freq, amp) partials. Detuned twins (e.g. 220/221) beat slowly -> electric shimmer.
partials = [
    (220, 0.50), (221, 0.42),     # fundamental + 1 Hz beat
    (330, 0.22), (331, 0.18),     # fifth, gentle
    (440, 0.14),                  # octave
    (1760, 0.05), (1763, 0.05),   # faint high sparkle (3 Hz beat) for "electric"
]

samples = []
for i in range(N):
    t = i / SR
    s = sum(a * math.sin(TAU * f * t) for f, a in partials)
    s *= 0.92 + 0.08 * math.sin(TAU * 2.0 * t)   # very shallow 2 Hz breathing
    samples.append(s)

peak = max(abs(x) for x in samples) or 1.0
gain = 0.8 / peak
data = b"".join(struct.pack("<h", int(max(-1, min(1, x * gain)) * 32767)) for x in samples)

out = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "assets", "laser_loop.wav"))
with wave.open(out, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(data)
print("wrote", out, "(%.2fs, %d frames)" % (LOOP, N))
